import asyncio
import sqlite3
from datetime import datetime, timedelta, timezone
from telethon import TelegramClient
from telethon.errors import SessionPasswordNeededError
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class TelegramParser:
    def __init__(self, api_id, api_hash, phone_number, db_path='telegram_posts.db', days_back=7):
        self.api_id = api_id
        self.api_hash = api_hash
        self.phone_number = phone_number
        self.db_path = db_path
        self.days_back = days_back
        self.client = TelegramClient('session', api_id, api_hash)

        self.start_date = datetime.now(timezone.utc) - timedelta(days=days_back)

        self.channels = {
            'rian_ru': 'РИА Новости',
            'mash': 'Mash'
        }

        self.init_database()

    def init_database(self):
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='posts'")
        table_exists = cursor.fetchone()

        if table_exists:
            cursor.execute("PRAGMA table_info(posts)")
            columns = cursor.fetchall()
            column_names = [col[1] for col in columns]

            required_columns = ['resource_name', 'post_text', 'publication_date', 'message_id']
            missing_columns = [col for col in required_columns if col not in column_names]

            if missing_columns:
                logger.error(f"Таблица posts имеет неправильную структуру!")
                logger.error(f"Недостающие колонки: {missing_columns}")
                logger.error("Запустите скрипт fix_database.py для исправления базы данных")
                conn.close()
                raise Exception("Неправильная структура базы данных")
        else:
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

        conn.commit()
        conn.close()
        logger.info(f"База данных инициализирована: {self.db_path}")

    async def authenticate(self):
        await self.client.start()

        if not await self.client.is_user_authorized():
            await self.client.send_code_request(self.phone_number)
            code = input('Введите код подтверждения: ')

            try:
                await self.client.sign_in(self.phone_number, code)
            except SessionPasswordNeededError:
                password = input('Введите двухфакторный пароль: ')
                await self.client.sign_in(password=password)

        logger.info("Авторизация успешна")

    def is_post_exists(self, resource_name, message_id):
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
        if not text:
            return ""

        cleaned = " ".join(text.split())
        return cleaned.strip()

    def normalize_datetime(self, dt):
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        else:
            return dt.astimezone(timezone.utc)

    async def parse_channel(self, channel_username, resource_name):
        try:
            entity = await self.client.get_entity(channel_username)
            logger.info(f"Начинаем парсинг канала: {resource_name}")
            logger.info(f"Парсим посты с {self.start_date.strftime('%Y-%m-%d %H:%M:%S')} по настоящее время")

            posts_count = 0
            skipped_count = 0

            async for message in self.client.iter_messages(entity):
                message_date_normalized = self.normalize_datetime(message.date)
                start_date_normalized = self.normalize_datetime(self.start_date)

                if message_date_normalized < start_date_normalized:
                    logger.info(f"Достигнута дата {message.date.strftime('%Y-%m-%d %H:%M:%S')}, останавливаем парсинг")
                    break

                if message.text:
                    clean_text = self.clean_text(message.text)
                    pub_date = message.date.strftime('%Y-%m-%d %H:%M:%S')

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

    async def parse_all_channels(self):
        await self.authenticate()

        logger.info(f"Начинаем парсинг всех каналов за последние {self.days_back} дней")

        current_time = datetime.now(timezone.utc)
        logger.info(
            f"Период: с {self.start_date.strftime('%Y-%m-%d %H:%M:%S')} по {current_time.strftime('%Y-%m-%d %H:%M:%S')}")

        for channel_username, resource_name in self.channels.items():
            await self.parse_channel(channel_username, resource_name)

    def get_stats(self):
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute('''
            SELECT resource_name, COUNT(*) as count
            FROM posts
            GROUP BY resource_name
        ''')

        stats = cursor.fetchall()
        conn.close()

        logger.info("Статистика по базе данных:")
        for resource, count in stats:
            logger.info(f"{resource}: {count} постов")

        return stats

    def get_posts_by_date_range(self, start_date=None, end_date=None, limit=None):
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        query = "SELECT resource_name, post_text, publication_date FROM posts"
        params = []

        if start_date or end_date:
            query += " WHERE"
            conditions = []

            if start_date:
                conditions.append("publication_date >= ?")
                params.append(start_date)

            if end_date:
                conditions.append("publication_date <= ?")
                params.append(end_date)

            query += " " + " AND ".join(conditions)

        query += " ORDER BY publication_date DESC"

        if limit:
            query += " LIMIT ?"
            params.append(limit)

        cursor.execute(query, params)
        posts = cursor.fetchall()
        conn.close()

        return posts

    def get_posts_stats_by_days(self):
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute('''
            SELECT 
                DATE(publication_date) as date,
                resource_name,
                COUNT(*) as count
            FROM posts
            WHERE publication_date >= ?
            GROUP BY DATE(publication_date), resource_name
            ORDER BY date DESC, resource_name
        ''', (self.start_date.strftime('%Y-%m-%d'),))

        stats = cursor.fetchall()
        conn.close()

        return stats

    async def close(self):
        await self.client.disconnect()


async def main():
    try:
        from config import API_ID, API_HASH, PHONE_NUMBER, DB_PATH, DAYS_BACK
    except ImportError:
        print("Файл config.py не найден. Используйте прямое указание данных:")
        print("Создайте файл config.py или замените значения ниже на ваши реальные данные")

        API_ID = 26848708
        API_HASH = '158436ee644201845b15ed4cd6e08d99'
        PHONE_NUMBER = '+79168365960'
        DB_PATH = 'telegram_posts.db'
        DAYS_BACK = 7

    parser = TelegramParser(API_ID, API_HASH, PHONE_NUMBER, DB_PATH, DAYS_BACK)

    try:
        await parser.parse_all_channels()
    except Exception as e:
        logger.error(f"Ошибка в main: {e}")
    finally:
        await parser.close()


if __name__ == "__main__":
    asyncio.run(main())