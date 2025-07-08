-- Таблица для хранения информации об источниках данных
CREATE TABLE IF NOT EXISTS sources (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL, -- Человекочитаемое имя источника (например, 'РИА Новости', 'Коммерсантъ', 'Telegram: Новости')
    url VARCHAR(2048) UNIQUE NOT NULL, -- URL источника, UNIQUE, чтобы избежать дубликатов
    type VARCHAR(50) NOT NULL,        -- Тип источника (например, 'telegram_channel', 'news_website', 'api_feed')
    metadata JSON,                    -- Добавлено поле metadata (json)
    date_last_parsing TIMESTAMP WITH TIME ZONE, -- Добавлено поле date_last_parsing
    last_collected_at TIMESTAMP WITH TIME ZONE, -- Дата и время последнего сбора данных с этого источника
    is_active BOOLEAN DEFAULT TRUE,   -- Активен ли источник для сбора
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Индекс для быстрого поиска по типу источника или активности
CREATE INDEX IF NOT EXISTS idx_sources_type ON sources (type);
CREATE INDEX IF NOT EXISTS idx_sources_is_active ON sources (is_active);

-- Таблица для хранения метаданных о собранных статьях
CREATE TABLE IF NOT EXISTS articles (
    id SERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL,          -- Внешний ключ к таблице sources
    url VARCHAR(2048) UNIQUE NOT NULL,   -- URL оригинальной статьи, UNIQUE
    is_processed BOOLEAN DEFAULT FALSE,  -- Флаг, указывающий, была ли статья обработана NER
    metadata JSON,                       -- Добавлено поле metadata (json)
    published_at TIMESTAMP WITH TIME ZONE, -- Оригинальная дата публикации статьи (если доступна)
    collected_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- Дата и время, когда статья была собрана
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    -- updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP -- Удалено поле updated_at в соответствии со схемой на изображении
    
    CONSTRAINT fk_source
        FOREIGN KEY (source_id)
        REFERENCES sources (id)
        ON DELETE CASCADE -- Если источник удален, удалить и связанные статьи
);

-- Индексы для быстрого поиска по статьям
CREATE INDEX IF NOT EXISTS idx_articles_source_id ON articles (source_id);
CREATE INDEX IF NOT EXISTS idx_articles_collected_at ON articles (collected_at DESC); -- Для поиска последних статей
CREATE INDEX IF NOT EXISTS idx_articles_is_processed ON articles (is_processed);
CREATE INDEX IF NOT EXISTS idx_articles_published_at ON articles (published_at DESC);

-- Таблица для хранения уникальных именованных сущностей
CREATE TABLE IF NOT EXISTS named_entities (
    id SERIAL PRIMARY KEY,
    canonical_name VARCHAR(512) UNIQUE NOT NULL, -- Каноническое (объединенное) имя сущности (например, "Джон Смит" вместо "Дж. Смит")
    type VARCHAR(100) NOT NULL,          -- Тип сущности (например, 'PERSON', 'ORG', 'LOC', 'DATE', 'EVENT')
    first_seen_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- Дата и время первого обнаружения этой сущности
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,  -- Дата и время последнего обнаружения этой сущности
    meta JSON,                           -- Соответствует 'metadata (json)' на схеме
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Индексы для быстрого поиска по сущностям
CREATE INDEX IF NOT EXISTS idx_named_entities_canonical_name ON named_entities (canonical_name);
CREATE INDEX IF NOT EXISTS idx_named_entities_type ON named_entities (type);
CREATE INDEX IF NOT EXISTS idx_named_entities_last_seen ON named_entities (last_seen_at DESC);

-- Таблица для прогнозов популярности
CREATE TABLE IF NOT EXISTS predictions (
    id SERIAL PRIMARY KEY,
    entity_id INTEGER NOT NULL,          -- Внешний ключ к таблице named_entities
    prediction_date DATE NOT NULL,       -- Дата, для которой сделан прогноз
    predicted_popularity NUMERIC(10,2) NOT NULL, -- Прогнозируемое значение популярности (например, ожидаемое количество упоминаний)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_prediction_entity
        FOREIGN KEY (entity_id)
        REFERENCES named_entities (id)
        ON DELETE CASCADE, -- Если сущность удалена, удалить и ее прогнозы
    
    UNIQUE (entity_id, prediction_date) -- Прогноз для одной сущности на одну дату может быть только один
);

-- Индексы для быстрого доступа к прогнозам
CREATE INDEX IF NOT EXISTS idx_predictions_entity_id ON predictions (entity_id);
CREATE INDEX IF NOT EXISTS idx_predictions_prediction_date ON predictions (prediction_date DESC);


-- Таблица для агрегированных счетчиков популярности (для отчета и обучения модели)
CREATE TABLE IF NOT EXISTS entity_statistics (
    id BIGSERIAL PRIMARY KEY,
    entity_id INTEGER NOT NULL,
    datetime TIMESTAMP WITH TIME ZONE NOT NULL, -- Дата и время, за которое производится подсчет
    count INTEGER NOT NULL DEFAULT 0, -- Общее количество упоминаний за этот день
    
    CONSTRAINT fk_daily_count_entity
        FOREIGN KEY (entity_id)
        REFERENCES named_entities (id)
        ON DELETE CASCADE,
    
    UNIQUE (entity_id, datetime) -- Только одна запись для сущности за конкретную дату
);

CREATE INDEX IF NOT EXISTS idx_entity_statistics_id ON entity_statistics (entity_id);
CREATE INDEX IF NOT EXISTS idx_entity_statistics_date ON entity_statistics (datetime DESC);
-- Отключение проверки внешних ключей для ускорения вставки и обхода временных зависимостей
-- (Возможно, не требуется в PostgreSQL, но хорошая практика для больших вставок)
-- SET session_replication_role = replica; -- Это для PostgreSQL, но обычно не нужно для простых INSERT






-- 1. Заполнение таблицы sources (не менее 30 записей)
-- Добавлены поля metadata и date_last_parsing
INSERT INTO sources (url, type, name, metadata, date_last_parsing, last_collected_at, is_active, created_at, updated_at) VALUES
('https://ria.ru/', 'news_website', 'РИА Новости', '{"publisher": "РИА", "country": "Russia"}'::jsonb, '2025-07-07 09:50:00+03', '2025-07-07 10:00:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://iz.ru/', 'news_website', 'Известия', '{"publisher": "Известия", "country": "Russia"}'::jsonb, '2025-07-07 09:20:00+03', '2025-07-07 09:30:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/breaking_news_ru', 'telegram_channel', 'Срочные Новости RU', '{"channel_type": "public", "language": "ru"}'::jsonb, '2025-07-07 11:05:00+03', '2025-07-07 11:15:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.kommersant.ru/', 'news_website', 'Коммерсантъ', '{"publisher": "Коммерсантъ", "country": "Russia"}'::jsonb, '2025-07-07 08:35:00+03', '2025-07-07 08:45:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/politics_today', 'telegram_channel', 'Политика Сегодня', '{"channel_type": "public", "language": "ru"}'::jsonb, '2025-07-07 10:30:00+03', '2025-07-07 10:40:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.rbc.ru/', 'news_website', 'РБК', '{"publisher": "РБК", "country": "Russia"}'::jsonb, '2025-07-07 08:50:00+03', '2025-07-07 09:00:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://tass.ru/', 'news_website', 'ТАСС', '{"publisher": "ТАСС", "country": "Russia"}'::jsonb, '2025-07-07 09:40:00+03', '2025-07-07 09:50:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/economy_digest', 'telegram_channel', 'Экономический Дайджест', '{"channel_type": "public", "language": "ru"}'::jsonb, '2025-07-07 10:10:00+03', '2025-07-07 10:20:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://lenta.ru/', 'news_website', 'Лента.ру', '{"publisher": "Лента.ру", "country": "Russia"}'::jsonb, '2025-07-07 08:20:00+03', '2025-07-07 08:30:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/tech_news_daily', 'telegram_channel', 'Ежедневные Техно-Новости', '{"channel_type": "public", "language": "ru"}'::jsonb, '2025-07-07 10:50:00+03', '2025-07-07 11:00:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.vedomosti.ru/', 'news_website', 'Ведомости', '{"publisher": "Ведомости", "country": "Russia"}'::jsonb, '2025-07-07 09:00:00+03', '2025-07-07 09:10:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/science_breakthroughs', 'telegram_channel', 'Научные Прорывы', '{"channel_type": "public", "language": "ru"}'::jsonb, '2025-07-07 11:20:00+03', '2025-07-07 11:30:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.gazeta.ru/', 'news_website', 'Газета.Ru', '{"publisher": "Газета.Ru", "country": "Russia"}'::jsonb, '2025-07-07 08:45:00+03', '2025-07-07 08:55:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/world_events', 'telegram_channel', 'Мировые События', '{"channel_type": "public", "language": "ru"}'::jsonb, '2025-07-07 10:00:00+03', '2025-07-07 10:10:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.interfax.ru/', 'news_website', 'Интерфакс', '{"publisher": "Интерфакс", "country": "Russia"}'::jsonb, '2025-07-07 09:30:00+03', '2025-07-07 09:40:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/sport_pulse', 'telegram_channel', 'Спорт Пульс', '{"channel_type": "public", "language": "ru"}'::jsonb, '2025-07-07 11:30:00+03', '2025-07-07 11:40:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://meduza.io/', 'news_website', 'Медуза', '{"publisher": "Meduza", "country": "Latvia"}'::jsonb, '2025-07-07 08:10:00+03', '2025-07-07 08:20:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/culture_daily', 'telegram_channel', 'Культура Ежедневно', '{"channel_type": "public", "language": "ru"}'::jsonb, '2025-07-07 10:40:00+03', '2025-07-07 10:50:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.forbes.ru/', 'news_website', 'Forbes Russia', '{"publisher": "Forbes", "country": "Russia"}'::jsonb, '2025-07-07 09:15:00+03', '2025-07-07 09:25:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/health_info', 'telegram_channel', 'Здоровье Инфо', '{"channel_type": "public", "language": "ru"}'::jsonb, '2025-07-07 11:10:00+03', '2025-07-07 11:20:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.bbc.com/news', 'news_website', 'BBC News', '{"publisher": "BBC", "country": "UK"}'::jsonb, '2025-07-07 06:50:00+03', '2025-07-07 07:00:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://edition.cnn.com/', 'news_website', 'CNN', '{"publisher": "CNN", "country": "USA"}'::jsonb, '2025-07-07 07:00:00+03', '2025-07-07 07:10:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/global_finance', 'telegram_channel', 'Глобальные Финансы', '{"channel_type": "public", "language": "en"}'::jsonb, '2025-07-07 07:20:00+03', '2025-07-07 07:30:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.nytimes.com/', 'news_website', 'The New York Times', '{"publisher": "The New York Times", "country": "USA"}'::jsonb, '2025-07-07 07:10:00+03', '2025-07-07 07:20:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/world_tech_updates', 'telegram_channel', 'Мировые Техно-Обновления', '{"channel_type": "public", "language": "en"}'::jsonb, '2025-07-07 07:35:00+03', '2025-07-07 07:45:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.theguardian.com/', 'news_website', 'The Guardian', '{"publisher": "The Guardian", "country": "UK"}'::jsonb, '2025-07-07 07:45:00+03', '2025-07-07 07:55:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/crypto_insights', 'telegram_channel', 'Крипто Инсайты', '{"channel_type": "public", "language": "en"}'::jsonb, '2025-07-07 07:55:00+03', '2025-07-07 08:05:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.wsj.com/', 'news_website', 'The Wall Street Journal', '{"publisher": "The Wall Street Journal", "country": "USA"}'::jsonb, '2025-07-07 08:05:00+03', '2025-07-07 08:15:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/space_exploration', 'telegram_channel', 'Исследование Космоса', '{"channel_type": "public", "language": "en"}'::jsonb, '2025-07-07 08:15:00+03', '2025-07-07 08:25:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.reuters.com/', 'news_website', 'Reuters', '{"publisher": "Reuters", "country": "UK"}'::jsonb, '2025-07-07 08:25:00+03', '2025-07-07 08:35:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/ai_insights', 'telegram_channel', 'AI Инсайты', '{"channel_type": "public", "language": "en"}'::jsonb, '2025-07-07 08:30:00+03', '2025-07-07 08:40:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.bloomberg.com/', 'news_website', 'Bloomberg', '{"publisher": "Bloomberg", "country": "USA"}'::jsonb, '2025-07-07 08:35:00+03', '2025-07-07 08:45:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/climate_action', 'telegram_channel', 'Климатические Действия', '{"channel_type": "public", "language": "en"}'::jsonb, '2025-07-07 08:40:00+03', '2025-07-07 08:50:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.dw.com/ru/', 'news_website', 'Deutsche Welle (Russian)', '{"publisher": "DW", "country": "Germany"}'::jsonb, '2025-07-07 08:50:00+03', '2025-07-07 09:00:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/cyber_security_news', 'telegram_channel', 'Новости Кибербезопасности', '{"channel_type": "public", "language": "ru"}'::jsonb, '2025-07-07 08:55:00+03', '2025-07-07 09:05:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.rt.com/', 'news_website', 'RT', '{"publisher": "RT", "country": "Russia"}'::jsonb, '2025-07-07 09:00:00+03', '2025-07-07 09:10:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/global_politics_digest', 'telegram_channel', 'Дайджест Глобальной Политики', '{"channel_type": "public", "language": "en"}'::jsonb, '2025-07-07 09:05:00+03', '2025-07-07 09:15:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.aljazeera.com/', 'news_website', 'Al Jazeera', '{"publisher": "Al Jazeera", "country": "Qatar"}'::jsonb, '2025-07-07 09:10:00+03', '2025-07-07 09:20:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://t.me/future_technologies', 'telegram_channel', 'Технологии Будущего', '{"channel_type": "public", "language": "ru"}'::jsonb, '2025-07-07 09:15:00+03', '2025-07-07 09:25:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('https://www.independent.co.uk/', 'news_website', 'The Independent', '{"publisher": "The Independent", "country": "UK"}'::jsonb, '2025-07-07 09:20:00+03', '2025-07-07 09:30:00+03', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);


-- 2. Заполнение таблицы named_entities (не менее 30 записей)
INSERT INTO named_entities (canonical_name, type, first_seen_at, last_seen_at, meta, created_at, updated_at) VALUES
('Владимир Путин', 'PERSON', '2025-01-01 00:00:00+03', '2025-07-07 12:00:00+03', '{"gender": "male", "nationality": "Russian"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Джо Байден', 'PERSON', '2025-01-05 00:00:00+03', '2025-07-07 12:10:00+03', '{"gender": "male", "nationality": "American"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('ООН', 'ORG', '2025-01-10 00:00:00+03', '2025-07-07 12:20:00+03', '{"type": "International Organization", "headquarters": "New York"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Москва', 'LOC', '2025-01-15 00:00:00+03', '2025-07-07 12:30:00+03', '{"country": "Russia", "population": 13000000}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Европейский Союз', 'ORG', '2025-01-20 00:00:00+03', '2025-07-07 12:40:00+03', '{"type": "Political and Economic Union", "members": 27}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Илон Маск', 'PERSON', '2025-02-01 00:00:00+03', '2025-07-07 12:50:00+03', '{"gender": "male", "occupation": "Entrepreneur"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Китай', 'LOC', '2025-02-05 00:00:00+03', '2025-07-07 13:00:00+03', '{"country": "China", "population": 1400000000}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Apple', 'ORG', '2025-02-10 00:00:00+03', '2025-07-07 13:10:00+03', '{"type": "Technology Company", "headquarters": "Cupertino"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('СВО', 'EVENT', '2025-02-15 00:00:00+03', '2025-07-07 13:20:00+03', '{"category": "Military Conflict"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('НАТО', 'ORG', '2025-02-20 00:00:00+03', '2025-07-07 13:30:00+03', '{"type": "Military Alliance", "headquarters": "Brussels"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Дмитрий Медведев', 'PERSON', '2025-03-01 00:00:00+03', '2025-07-07 13:40:00+03', '{"gender": "male", "nationality": "Russian"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Париж', 'LOC', '2025-03-05 00:00:00+03', '2025-07-07 13:50:00+03', '{"country": "France", "population": 2100000}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Google', 'ORG', '2025-03-10 00:00:00+03', '2025-07-07 14:00:00+03', '{"type": "Technology Company", "headquarters": "Mountain View"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Климатический Саммит', 'EVENT', '2025-03-15 00:00:00+03', '2025-07-07 14:10:00+03', '{"category": "Environmental"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Всемирный Банк', 'ORG', '2025-03-20 00:00:00+03', '2025-07-07 14:20:00+03', '{"type": "Financial Institution", "headquarters": "Washington D.C."}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Ангела Меркель', 'PERSON', '2025-04-01 00:00:00+03', '2025-07-07 14:30:00+03', '{"gender": "female", "nationality": "German"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Берлин', 'LOC', '2025-04-05 00:00:00+03', '2025-07-07 14:40:00+03', '{"country": "Germany", "population": 3700000}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Microsoft', 'ORG', '2025-04-10 00:00:00+03', '2025-07-07 14:50:00+03', '{"type": "Technology Company", "headquarters": "Redmond"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Чемпионат Мира по Футболу', 'EVENT', '2025-04-15 00:00:00+03', '2025-07-07 15:00:00+03', '{"category": "Sport"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('МВФ', 'ORG', '2025-04-20 00:00:00+03', '2025-07-07 15:10:00+03', '{"type": "Financial Institution", "headquarters": "Washington D.C."}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Си Цзиньпин', 'PERSON', '2025-05-01 00:00:00+03', '2025-07-07 15:20:00+03', '{"gender": "male", "nationality": "Chinese"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Токио', 'LOC', '2025-05-05 00:00:00+03', '2025-07-07 15:30:00+03', '{"country": "Japan", "population": 14000000}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Amazon', 'ORG', '2025-05-10 00:00:00+03', '2025-07-07 15:40:00+03', '{"type": "E-commerce", "headquarters": "Seattle"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Олимпийские Игры', 'EVENT', '2025-05-15 00:00:00+03', '2025-07-07 15:50:00+03', '{"category": "Sport"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('ВОЗ', 'ORG', '2025-05-20 00:00:00+03', '2025-07-07 16:00:00+03', '{"type": "Health Organization", "headquarters": "Geneva"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Эммануэль Макрон', 'PERSON', '2025-06-01 00:00:00+03', '2025-07-07 16:10:00+03', '{"gender": "male", "nationality": "French"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Лондон', 'LOC', '2025-06-05 00:00:00+03', '2025-07-07 16:20:00+03', '{"country": "UK", "population": 9000000}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Facebook', 'ORG', '2025-06-10 00:00:00+03', '2025-07-07 16:30:00+03', '{"type": "Social Media", "headquarters": "Menlo Park"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('G20 Саммит', 'EVENT', '2025-06-15 00:00:00+03', '2025-07-07 16:40:00+03', '{"category": "Politics"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Газпром', 'ORG', '2025-06-20 00:00:00+03', '2025-07-07 16:50:00+03', '{"type": "Energy Company", "country": "Russia"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Сергей Лавров', 'PERSON', '2025-07-01 00:00:00+03', '2025-07-07 17:00:00+03', '{"gender": "male", "nationality": "Russian"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Нью-Йорк', 'LOC', '2025-07-02 00:00:00+03', '2025-07-07 17:10:00+03', '{"country": "USA", "population": 8400000}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Тесла', 'ORG', '2025-07-03 00:00:00+03', '2025-07-07 17:20:00+03', '{"type": "Automotive", "headquarters": "Austin"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('БРИКС', 'ORG', '2025-07-04 00:00:00+03', '2025-07-07 17:30:00+03', '{"type": "Economic Bloc", "members": 5}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Марс', 'LOC', '2025-07-05 00:00:00+03', '2025-07-07 17:40:00+03', '{"type": "Planet", "solar_system": "true"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Искусственный Интеллект', 'CONCEPT', '2025-01-01 00:00:00+03', '2025-07-07 17:50:00+03', '{"category": "Technology"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Криптовалюты', 'CONCEPT', '2025-01-01 00:00:00+03', '2025-07-07 18:00:00+03', '{"category": "Finance"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Глобальное Потепление', 'CONCEPT', '2025-01-01 00:00:00+03', '2025-07-07 18:10:00+03', '{"category": "Environment"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Квантовые Вычисления', 'CONCEPT', '2025-01-01 00:00:00+03', '2025-07-07 18:20:00+03', '{"category": "Technology"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('Биоинженерия', 'CONCEPT', '2025-01-01 00:00:00+03', '2025-07-07 18:30:00+03', '{"category": "Science"}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);


-- 3. Заполнение таблицы articles (не менее 30 записей)
-- Удалено поле title, добавлено поле metadata
INSERT INTO articles (source_id, url, is_processed, metadata, published_at, collected_at, created_at) VALUES
(1, 'https://ria.ru/news/1', FALSE, '{"original_title": "Путин провел совещание по экономике"}'::jsonb, '2025-07-07 09:55:00+03', '2025-07-07 10:05:00+03', CURRENT_TIMESTAMP),
(2, 'https://iz.ru/news/1', FALSE, '{"original_title": "Заявление Байдена по Ближнему Востоку"}'::jsonb, '2025-07-07 09:25:00+03', '2025-07-07 09:35:00+03', CURRENT_TIMESTAMP),
(3, 'https://t.me/breaking_news_ru/1', FALSE, '{"original_title": "ООН призывает к прекращению огня"}'::jsonb, '2025-07-07 11:10:00+03', '2025-07-07 11:20:00+03', CURRENT_TIMESTAMP),
(4, 'https://www.kommersant.ru/doc/1', FALSE, '{"original_title": "Новые санкции ЕС против России"}'::jsonb, '2025-07-07 08:40:00+03', '2025-07-07 08:50:00+03', CURRENT_TIMESTAMP),
(5, 'https://t.me/politics_today/1', FALSE, '{"original_title": "Илон Маск о будущем ИИ"}'::jsonb, '2025-07-07 10:35:00+03', '2025-07-07 10:45:00+03', CURRENT_TIMESTAMP),
(6, 'https://www.rbc.ru/news/1', FALSE, '{"original_title": "Китайская экономика замедляется"}'::jsonb, '2025-07-07 08:55:00+03', '2025-07-07 09:05:00+03', CURRENT_TIMESTAMP),
(7, 'https://tass.ru/news/1', FALSE, '{"original_title": "Apple представила новый iPhone"}'::jsonb, '2025-07-07 09:45:00+03', '2025-07-07 09:55:00+03', CURRENT_TIMESTAMP),
(8, 'https://t.me/economy_digest/1', FALSE, '{"original_title": "СВО: новые данные Минобороны"}'::jsonb, '2025-07-07 10:15:00+03', '2025-07-07 10:25:00+03', CURRENT_TIMESTAMP),
(9, 'https://lenta.ru/news/1', FALSE, '{"original_title": "НАТО проводит учения в Балтике"}'::jsonb, '2025-07-07 08:25:00+03', '2025-07-07 08:35:00+03', CURRENT_TIMESTAMP),
(10, 'https://t.me/tech_news_daily/1', FALSE, '{"original_title": "Дмитрий Медведев о санкциях"}'::jsonb, '2025-07-07 10:55:00+03', '2025-07-07 11:05:00+03', CURRENT_TIMESTAMP),
(11, 'https://www.vedomosti.ru/news/1', FALSE, '{"original_title": "Париж готовится к Олимпиаде"}'::jsonb, '2025-07-07 09:05:00+03', '2025-07-07 09:15:00+03', CURRENT_TIMESTAMP),
(12, 'https://t.me/science_breakthroughs/1', FALSE, '{"original_title": "Google инвестирует в квантовые вычисления"}'::jsonb, '2025-07-07 11:25:00+03', '2025-07-07 11:35:00+03', CURRENT_TIMESTAMP),
(13, 'https://www.gazeta.ru/news/1', FALSE, '{"original_title": "Климатический саммит в Берлине"}'::jsonb, '2025-07-07 08:50:00+03', '2025-07-07 09:00:00+03', CURRENT_TIMESTAMP),
(14, 'https://t.me/world_events/1', FALSE, '{"original_title": "Всемирный Банк прогнозирует рост"}'::jsonb, '2025-07-07 10:05:00+03', '2025-07-07 10:15:00+03', CURRENT_TIMESTAMP),
(15, 'https://www.interfax.ru/news/1', FALSE, '{"original_title": "Ангела Меркель посетит Москву"}'::jsonb, '2025-07-07 09:35:00+03', '2025-07-07 09:45:00+03', CURRENT_TIMESTAMP),
(16, 'https://t.me/sport_pulse/1', FALSE, '{"original_title": "Microsoft анонсировала новые сервисы"}'::jsonb, '2025-07-07 11:35:00+03', '2025-07-07 11:45:00+03', CURRENT_TIMESTAMP),
(17, 'https://meduza.io/news/1', FALSE, '{"original_title": "Чемпионат мира по футболу: подготовка"}'::jsonb, '2025-07-07 08:15:00+03', '2025-07-07 08:25:00+03', CURRENT_TIMESTAMP),
(18, 'https://t.me/culture_daily/1', FALSE, '{"original_title": "МВФ обсуждает глобальную инфляцию"}'::jsonb, '2025-07-07 10:45:00+03', '2025-07-07 10:55:00+03', CURRENT_TIMESTAMP),
(19, 'https://www.forbes.ru/news/1', FALSE, '{"original_title": "Си Цзиньпин встретился с Байденом"}'::jsonb, '2025-07-07 09:20:00+03', '2025-07-07 09:30:00+03', CURRENT_TIMESTAMP),
(20, 'https://t.me/health_info/1', FALSE, '{"original_title": "Токио: новые меры безопасности"}'::jsonb, '2025-07-07 11:15:00+03', '2025-07-07 11:25:00+03', CURRENT_TIMESTAMP),
(21, 'https://www.bbc.com/news/1', FALSE, '{"original_title": "Amazon запускает новую доставку"}'::jsonb, '2025-07-07 06:55:00+03', '2025-07-07 07:05:00+03', CURRENT_TIMESTAMP),
(22, 'https://edition.cnn.com/news/1', FALSE, '{"original_title": "Олимпийские игры: скандал с допингом"}'::jsonb, '2025-07-07 07:05:00+03', '2025-07-07 07:15:00+03', CURRENT_TIMESTAMP),
(23, 'https://t.me/global_finance/1', FALSE, '{"original_title": "ВОЗ предупреждает о пандемии"}'::jsonb, '2025-07-07 07:25:00+03', '2025-07-07 07:35:00+03', CURRENT_TIMESTAMP),
(24, 'https://www.nytimes.com/news/1', FALSE, '{"original_title": "Макрон посетил Киев"}'::jsonb, '2025-07-07 07:15:00+03', '2025-07-07 07:25:00+03', CURRENT_TIMESTAMP),
(25, 'https://t.me/world_tech_updates/1', FALSE, '{"original_title": "Лондон: протесты против правительства"}'::jsonb, '2025-07-07 07:40:00+03', '2025-07-07 07:50:00+03', CURRENT_TIMESTAMP),
(26, 'https://www.theguardian.com/news/1', FALSE, '{"original_title": "Facebook изменит алгоритмы"}'::jsonb, '2025-07-07 07:50:00+03', '2025-07-07 08:00:00+03', CURRENT_TIMESTAMP),
(27, 'https://t.me/crypto_insights/1', FALSE, '{"original_title": "G20 Саммит: итоги встречи"}'::jsonb, '2025-07-07 08:00:00+03', '2025-07-07 08:10:00+03', CURRENT_TIMESTAMP),
(28, 'https://www.wsj.com/news/1', FALSE, '{"original_title": "Газпром подписал новый контракт"}'::jsonb, '2025-07-07 08:10:00+03', '2025-07-07 08:20:00+03', CURRENT_TIMESTAMP),
(29, 'https://t.me/space_exploration/1', FALSE, '{"original_title": "Сергей Лавров провел переговоры"}'::jsonb, '2025-07-07 08:20:00+03', '2025-07-07 08:30:00+03', CURRENT_TIMESTAMP),
(30, 'https://www.reuters.com/news/1', FALSE, '{"original_title": "Нью-Йорк: рост преступности"}'::jsonb, '2025-07-07 08:30:00+03', '2025-07-07 08:40:00+03', CURRENT_TIMESTAMP),
(31, 'https://t.me/ai_insights/1', FALSE, '{"original_title": "Тесла представила новый электромобиль"}'::jsonb, '2025-07-07 08:35:00+03', '2025-07-07 08:45:00+03', CURRENT_TIMESTAMP),
(32, 'https://www.bloomberg.com/news/1', FALSE, '{"original_title": "БРИКС расширяет состав"}'::jsonb, '2025-07-07 08:40:00+03', '2025-07-07 08:50:00+03', CURRENT_TIMESTAMP),
(33, 'https://t.me/climate_action/1', FALSE, '{"original_title": "Марс: новые открытия НАСА"}'::jsonb, '2025-07-07 08:45:00+03', '2025-07-07 08:55:00+03', CURRENT_TIMESTAMP),
(34, 'https://www.dw.com/ru/news/1', FALSE, '{"original_title": "Искусственный Интеллект в медицине"}'::jsonb, '2025-07-07 08:55:00+03', '2025-07-07 09:05:00+03', CURRENT_TIMESTAMP),
(35, 'https://t.me/cyber_security_news/1', FALSE, '{"original_title": "Криптовалюты: регуляция на повестке"}'::jsonb, '2025-07-07 09:00:00+03', '2025-07-07 09:10:00+03', CURRENT_TIMESTAMP),
(36, 'https://www.rt.com/news/1', FALSE, '{"original_title": "Глобальное Потепление: новый доклад"}'::jsonb, '2025-07-07 09:05:00+03', '2025-07-07 09:15:00+03', CURRENT_TIMESTAMP),
(37, 'https://t.me/global_politics_digest/1', FALSE, '{"original_title": "Квантовые Вычисления: прорыв в исследованиях"}'::jsonb, '2025-07-07 09:10:00+03', '2025-07-07 09:20:00+03', CURRENT_TIMESTAMP),
(38, 'https://www.aljazeera.com/news/1', FALSE, '{"original_title": "Биоинженерия: этические вопросы"}'::jsonb, '2025-07-07 09:15:00+03', '2025-07-07 09:25:00+03', CURRENT_TIMESTAMP),
(39, 'https://t.me/future_technologies/1', FALSE, '{"original_title": "Илон Маск и Марс: новые планы"}'::jsonb, '2025-07-07 09:20:00+03', '2025-07-07 09:30:00+03', CURRENT_TIMESTAMP),
(40, 'https://www.independent.co.uk/news/1', FALSE, '{"original_title": "Джо Байден и Глобальное Потепление"}'::jsonb, '2025-07-07 09:25:00+03', '2025-07-07 09:35:00+03', CURRENT_TIMESTAMP);

-- 5. Заполнение таблицы predictions (не менее 30 записей)
-- Структура таблицы Predictions не изменилась, поэтому запросы остались прежними.
INSERT INTO predictions (entity_id, prediction_date, predicted_popularity, created_at) VALUES
(1, '2025-07-08', 150.25, CURRENT_TIMESTAMP),
(2, '2025-07-08', 120.50, CURRENT_TIMESTAMP),
(3, '2025-07-08', 80.10, CURRENT_TIMESTAMP),
(4, '2025-07-08', 90.75, CURRENT_TIMESTAMP),
(5, '2025-07-08', 70.00, CURRENT_TIMESTAMP),
(6, '2025-07-08', 200.30, CURRENT_TIMESTAMP),
(7, '2025-07-08', 110.40, CURRENT_TIMESTAMP),
(8, '2025-07-08', 180.60, CURRENT_TIMESTAMP),
(9, '2025-07-08', 130.80, CURRENT_TIMESTAMP),
(10, '2025-07-08', 60.90, CURRENT_TIMESTAMP),
(11, '2025-07-08', 55.20, CURRENT_TIMESTAMP),
(12, '2025-07-08', 45.15, CURRENT_TIMESTAMP),
(13, '2025-07-08', 170.70, CURRENT_TIMESTAMP),
(14, '2025-07-08', 75.30, CURRENT_TIMESTAMP),
(15, '2025-07-08', 85.40, CURRENT_TIMESTAMP),
(16, '2025-07-08', 95.50, CURRENT_TIMESTAMP),
(17, '2025-07-08', 105.60, CURRENT_TIMESTAMP),
(18, '2025-07-08', 115.70, CURRENT_TIMESTAMP),
(19, '2025-07-08', 125.80, CURRENT_TIMESTAMP),
(20, '2025-07-08', 135.90, CURRENT_TIMESTAMP),
(21, '2025-07-08', 145.00, CURRENT_TIMESTAMP),
(22, '2025-07-08', 155.10, CURRENT_TIMESTAMP),
(23, '2025-07-08', 165.20, CURRENT_TIMESTAMP),
(24, '2025-07-08', 175.30, CURRENT_TIMESTAMP),
(25, '2025-07-08', 185.40, CURRENT_TIMESTAMP),
(26, '2025-07-08', 195.50, CURRENT_TIMESTAMP),
(27, '2025-07-08', 205.60, CURRENT_TIMESTAMP),
(28, '2025-07-08', 215.70, CURRENT_TIMESTAMP),
(29, '2025-07-08', 225.80, CURRENT_TIMESTAMP),
(30, '2025-07-08', 235.90, CURRENT_TIMESTAMP),
(31, '2025-07-08', 245.00, CURRENT_TIMESTAMP),
(32, '2025-07-08', 255.10, CURRENT_TIMESTAMP),
(33, '2025-07-08', 265.20, CURRENT_TIMESTAMP),
(34, '2025-07-08', 275.30, CURRENT_TIMESTAMP),
(35, '2025-07-08', 285.40, CURRENT_TIMESTAMP),
(36, '2025-07-08', 295.50, CURRENT_TIMESTAMP),
(37, '2025-07-08', 305.60, CURRENT_TIMESTAMP),
(38, '2025-07-08', 315.70, CURRENT_TIMESTAMP),
(39, '2025-07-08', 325.80, CURRENT_TIMESTAMP),
(40, '2025-07-08', 335.90, CURRENT_TIMESTAMP);

-- Дополнительные прогнозы на будущие даты для некоторых сущностей
INSERT INTO predictions (entity_id, prediction_date, predicted_popularity, created_at) VALUES
(1, '2025-07-09', 155.00, CURRENT_TIMESTAMP),
(1, '2025-07-10', 160.00, CURRENT_TIMESTAMP),
(6, '2025-07-09', 210.00, CURRENT_TIMESTAMP),
(6, '2025-07-10', 220.00, CURRENT_TIMESTAMP),
(34, '2025-07-09', 280.00, CURRENT_TIMESTAMP),
(34, '2025-07-10', 290.00, CURRENT_TIMESTAMP);


-- 6. Заполнение таблицы entity_statistics (не менее 30 записей)
-- Структура таблицы Entity_statistics не изменилась, поэтому запросы остались прежними.
INSERT INTO entity_statistics (entity_id, "datetime", "count") VALUES
(1, '2025-07-01 00:00:00+03', 50),
(1, '2025-07-02 00:00:00+03', 55),
(1, '2025-07-03 00:00:00+03', 60),
(1, '2025-07-04 00:00:00+03', 62),
(1, '2025-07-05 00:00:00+03', 65),
(1, '2025-07-06 00:00:00+03', 70),
(1, '2025-07-07 00:00:00+03', 75),
(2, '2025-07-01 00:00:00+03', 40),
(2, '2025-07-02 00:00:00+03', 42),
(2, '2025-07-03 00:00:00+03', 45),
(2, '2025-07-04 00:00:00+03', 48),
(2, '2025-07-05 00:00:00+03', 50),
(2, '2025-07-06 00:00:00+03', 53),
(2, '2025-07-07 00:00:00+03', 55),
(6, '2025-07-01 00:00:00+03', 80),
(6, '2025-07-02 00:00:00+03', 85),
(6, '2025-07-03 00:00:00+03', 90),
(6, '2025-07-04 00:00:00+03', 95),
(6, '2025-07-05 00:00:00+03', 100),
(6, '2025-07-06 00:00:00+03', 105),
(6, '2025-07-07 00:00:00+03', 110),
(34, '2025-07-01 00:00:00+03', 70),
(34, '2025-07-02 00:00:00+03', 72),
(34, '2025-07-03 00:00:00+03', 75),
(34, '2025-07-04 00:00:00+03', 78),
(34, '2025-07-05 00:00:00+03', 80),
(34, '2025-07-06 00:00:00+03', 83),
(34, '2025-07-07 00:00:00+03', 85),
(13, '2025-07-01 00:00:00+03', 30),
(13, '2025-07-02 00:00:00+03', 32),
(13, '2025-07-03 00:00:00+03', 35),
(13, '2025-07-04 00:00:00+03', 38),
(13, '2025-07-05 00:00:00+03', 40),
(13, '2025-07-06 00:00:00+03', 42),
(13, '2025-07-07 00:00:00+03', 45),
(28, '2025-07-01 00:00:00+03', 25),
(28, '2025-07-02 00:00:00+03', 27),
(28, '2025-07-03 00:00:00+03', 30),
(28, '2025-07-04 00:00:00+03', 32),
(28, '2025-07-05 00:00:00+03', 35),
(28, '2025-07-06 00:00:00+03', 38),
(28, '2025-07-07 00:00:00+03', 40);
