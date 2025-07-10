from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta, timezone
import asyncio
import sqlite3
import logging
import os # Для проверки наличия config.py

# Настройка логирования для DAG
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class TelegramParser:
    def __init__(self, api_id, api_hash, phone_number, db_path='telegram_posts.db', days_back=7):
        """
        Инициализирует парсер Telegram.
        :param api_id: API ID для Telegram API.
        :param api_hash: API Hash для Telegram API.
        :param phone_number: Номер телефона для авторизации.
        :param db_path: Путь к файлу базы данных SQLite.
        :param days_back: Количество дней, за которые нужно парсить посты.
        """
        self.api_id = api_id
        self.api_hash = api_hash
        self.phone_number = phone_number
        self.db_path = db_path
        self.days_back = days_back
        # Имя файла сессии Telethon. Этот файл будет создан/использован Telethon.
        # В Airflow предполагается, что он уже существует.
        self.client = TelegramClient('telegram_session', api_id, api_hash)

        # Дата, начиная с которой будут парситься посты (UTC)
        self.start_date = datetime.now(timezone.utc) - timedelta(days=days_back)

        self.channels = {} # Этот словарь будет заполнен из базы данных

        self.init_database()        # Инициализация таблицы 'posts'
        self.init_channels_table()  # Инициализация таблицы 'channels' и добавление каналов по умолчанию
        self.get_channels_from_db() # Загрузка каналов из БД в self.channels

    def init_database(self):
        """Инициализирует таблицу 'posts' в базе данных SQLite."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Проверка существования таблицы 'posts'
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='posts'")
        table_exists = cursor.fetchone()

        if table_exists:
            # Проверка структуры таблицы 'posts'
            cursor.execute("PRAGMA table_info(posts)")
            columns = cursor.fetchall()
            column_names = [col[1] for col in columns]

            required_columns = ['resource_name', 'post_text', 'publication_date', 'message_id']
            missing_columns = [col for col in required_columns if col not in column_names]

            if missing_columns:
                logger.error(f"Таблица 'posts' имеет неправильную структуру!")
                logger.error(f"Недостающие колонки: {missing_columns}")
                # В контексте Airflow, выбрасывание исключения здесь приведет к сбою задачи.
                raise Exception("Неправильная структура базы данных 'posts'")
        else:
            # Создание таблицы 'posts', если она не существует
            cursor.execute('''
                CREATE TABLE posts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    resource_name TEXT NOT NULL,
                    post_text TEXT NOT NULL,
                    publication_date TEXT NOT NULL,
                    message_id INTEGER,
                    UNIQUE(resource_name, message_id)
                )
            ''')
            logger.info("Таблица 'posts' создана.")

        conn.commit()
        conn.close()
        logger.info(f"База данных 'posts' инициализирована: {self.db_path}")

    def init_channels_table(self):
        """Инициализирует таблицу 'channels' и добавляет каналы по умолчанию, если их нет."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS channels (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                channel_username TEXT NOT NULL UNIQUE,
                resource_name TEXT NOT NULL
            )
        ''')
        conn.commit()
        logger.info("Таблица 'channels' инициализирована.")

        # Добавление каналов по умолчанию, если их нет
        default_channels = {
            'rian_ru': 'РИА Новости',
            'mash': 'Mash'
        }
        for username, name in default_channels.items():
            try:
                cursor.execute("INSERT OR IGNORE INTO channels (channel_username, resource_name) VALUES (?, ?)",
                               (username, name))
                if cursor.rowcount > 0:
                    logger.info(f"Добавлен канал в базу данных: {name} ({username})")
            except sqlite3.Error as e:
                logger.error(f"Ошибка при добавлении канала '{name}' в БД: {e}")
        conn.commit()
        conn.close()

    def get_channels_from_db(self):
        """Загружает имена пользователей каналов и их названия из таблицы 'channels' в self.channels."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT channel_username, resource_name FROM channels")
        channels_list = cursor.fetchall()
        conn.close()
        self.channels = {username: name for username, name in channels_list}
        logger.info(f"Загружены каналы из БД: {self.channels}")

    async def authenticate(self):
        """
        Аутентифицирует клиент Telethon.
        В контексте Airflow предполагается, что файл сессии ('telegram_session.session')
        уже существует после предыдущего ручного интерактивного запуска.
        """
        try:
            await self.client.start()
            if not await self.client.is_user_authorized():
                logger.error("Пользователь не авторизован. Сессия Telethon не найдена или недействительна.")
                logger.error("Пожалуйста, запустите скрипт вручную один раз для интерактивной авторизации и создания файла сессии 'telegram_session.session'.")
                raise Exception("Ошибка аутентификации Telethon. Файл сессии отсутствует или недействителен.")
            logger.info("Авторизация успешна (используется существующая сессия)")
        except Exception as e:
            logger.error(f"Ошибка при старте клиента Telethon: {e}")
            raise # Перевыбрасываем исключение, чтобы задача Airflow завершилась ошибкой

    def is_post_exists(self, resource_name, message_id):
        """Проверяет, существует ли пост с данным resource_name и message_id в базе данных."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        try:
            cursor.execute('''
                SELECT COUNT(*) FROM posts
                WHERE resource_name = ? AND message_id = ?
            ''', (resource_name, message_id))
            count = cursor.fetchone()[0]
            return count > 0
        except sqlite3.Error as e:
            logger.error(f"Ошибка проверки существования поста: {e}")
            return False
        finally:
            conn.close()

    def save_post(self, resource_name, post_text, publication_date, message_id):
        """Сохраняет новый пост в базу данных, игнорируя дубликаты."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        try:
            cursor.execute('''
                INSERT OR IGNORE INTO posts
                (resource_name, post_text, publication_date, message_id)
                VALUES (?, ?, ?, ?)
            ''', (resource_name, post_text, publication_date, message_id))
            conn.commit()
            if cursor.rowcount > 0:
                logger.info(f"Сохранен пост от {resource_name}, ID: {message_id}")
        except sqlite3.Error as e:
            logger.error(f"Ошибка сохранения поста: {e}")
        finally:
            conn.close()

    def clean_text(self, text):
        """Очищает и нормализует текст, удаляя лишние пробелы."""
        if not text:
            return ""
        cleaned = " ".join(text.split())
        return cleaned.strip()

    def normalize_datetime(self, dt):
        """Нормализует объект datetime до часового пояса UTC."""
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        else:
            return dt.astimezone(timezone.utc)

    async def parse_channel(self, channel_username, resource_name):
        """Парсит сообщения из одного Telegram-канала."""
        try:
            entity = await self.client.get_entity(channel_username)
            logger.info(f"Начинаем парсинг канала: {resource_name} ({channel_username})")
            logger.info(f"Парсим посты с {self.start_date.strftime('%Y-%m-%d %H:%M:%S')} по настоящее время")

            posts_count = 0
            skipped_count = 0

            # Итерация по сообщениям в канале
            async for message in self.client.iter_messages(entity):
                message_date_normalized = self.normalize_datetime(message.date)
                start_date_normalized = self.normalize_datetime(self.start_date)

                # Остановка, если сообщение старше начальной даты
                if message_date_normalized < start_date_normalized:
                    logger.info(f"Достигнута дата {message.date.strftime('%Y-%m-%d %H:%M:%S')}, останавливаем парсинг")
                    break

                if message.text:
                    clean_text = self.clean_text(message.text)
                    pub_date = message.date.strftime('%Y-%m-%d %H:%M:%S')

                    # Проверка на дубликаты перед сохранением
                    if self.is_post_exists(resource_name, message.id):
                        skipped_count += 1
                        continue

                    self.save_post(
                        resource_name=resource_name,
                        post_text=clean_text,
                        publication_date=pub_date,
                        message_id=message.id
                    )
                    posts_count += 1

                    if posts_count % 10 == 0:
                        logger.info(f"Обработано {posts_count} новых постов из {resource_name}")

            logger.info(f"Завершен парсинг канала {resource_name}:")
            logger.info(f"  - Новых постов: {posts_count}")
            logger.info(f"  - Пропущено (дубли): {skipped_count}")

        except Exception as e:
            logger.error(f"Ошибка при парсинге канала {resource_name}: {e}")
            raise # Перевыбрасываем исключение, чтобы задача Airflow завершилась ошибкой

    async def parse_all_channels(self):
        """Аутентифицирует и затем парсит все каналы, загруженные из базы данных."""
        await self.authenticate()

        logger.info(f"Начинаем парсинг всех каналов за последние {self.days_back} дней")

        current_time = datetime.now(timezone.utc)
        logger.info(
            f"Период: с {self.start_date.strftime('%Y-%m-%d %H:%M:%S')} по {current_time.strftime('%Y-%m-%d %H:%M:%S')}")

        for channel_username, resource_name in self.channels.items():
            await self.parse_channel(channel_username, resource_name)

    async def close(self):
        """Отключает клиент Telethon."""
        if self.client.is_connected():
            await self.client.disconnect()
            logger.info("Клиент Telethon отключен.")

# --- Определение DAG Airflow ---

def run_telegram_parser_task():
    """
    Вызываемая функция Airflow для запуска парсера Telegram.
    Эта функция обрабатывает создание экземпляра и выполнение TelegramParser.
    """
    # Конфигурация для парсера.
    # В производственной среде Airflow эти данные должны загружаться из Airflow Variables
    # или переменных окружения для безопасности и гибкости.
    # В этом примере мы проверяем наличие файла config.py или используем жестко закодированные значения по умолчанию.
    API_ID = None
    API_HASH = None
    PHONE_NUMBER = None
    DB_PATH = 'telegram_posts.db'
    DAYS_BACK = 7

    try:
        # Попытка импортировать из config.py
        # Убедитесь, что config.py находится в папке DAGs или доступен через PYTHONPATH
        from config import API_ID as CFG_API_ID, API_HASH as CFG_API_HASH, \
                           PHONE_NUMBER as CFG_PHONE_NUMBER, DB_PATH as CFG_DB_PATH, \
                           DAYS_BACK as CFG_DAYS_BACK
        API_ID = CFG_API_ID
        API_HASH = CFG_API_HASH
        PHONE_NUMBER = CFG_PHONE_NUMBER
        DB_PATH = CFG_DB_PATH
        DAYS_BACK = CFG_DAYS_BACK
        logger.info("Конфигурация загружена из config.py")
    except ImportError:
        logger.warning("Файл config.py не найден. Используются значения по умолчанию. "
                       "Пожалуйста, убедитесь, что API_ID, API_HASH и PHONE_NUMBER заданы корректно.")
        # Возврат к жестко закодированным значениям, если config.py не найден
        # !!! ВАЖНО: Замените эти значения на свои фактические или используйте Airflow Variables !!!
        API_ID = 26848708
        API_HASH = '158436ee644201845b15ed4cd6e08d99'
        PHONE_NUMBER = '+79168365960'
        # DB_PATH и DAYS_BACK могут оставаться значениями по умолчанию, если это необходимо

    if not all([API_ID, API_HASH, PHONE_NUMBER]):
        raise ValueError("API_ID, API_HASH и PHONE_NUMBER должны быть предоставлены либо в config.py, либо жестко закодированы.")

    parser = TelegramParser(API_ID, API_HASH, PHONE_NUMBER, DB_PATH, DAYS_BACK)

    try:
        # Запуск асинхронной логики парсинга с использованием asyncio.run
        asyncio.run(parser.parse_all_channels())
    except Exception as e:
        logger.error(f"Ошибка при выполнении парсера Telegram: {e}")
        raise # Перевыбрасываем исключение, чтобы задача Airflow завершилась ошибкой
    finally:
        # Убедитесь, что клиент отключен, даже если произошла ошибка
        asyncio.run(parser.close())


# Определение DAG Airflow
with DAG(
    dag_id='telegram_channel_parser_v2', # Изменен ID на v2, чтобы избежать конфликтов
    start_date=datetime(2023, 1, 1), # Дата начала для DAG
    schedule_interval=timedelta(days=1), # Запуск ежедневно
    catchup=False, # Не запускать пропущенные прошлые запуски
    tags=['telegram', 'parser', 'data_ingestion'], # Теги для более легкой фильтрации в UI Airflow
    default_args={
        'owner': 'airflow',
        'depends_on_past': False,
        'email_on_failure': False, # Установите True для получения писем при сбое задачи
        'email_on_retry': False,
        'retries': 1, # Количество повторных попыток задачи в случае сбоя
        'retry_delay': timedelta(minutes=5), # Задержка между повторными попытками
    }
) as dag:
    # Определение задачи PythonOperator
    parse_telegram_channels_task = PythonOperator(
        task_id='parse_telegram_channels',
        python_callable=run_telegram_parser_task,
    )
