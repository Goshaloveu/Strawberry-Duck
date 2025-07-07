-- Таблица для хранения информации об источниках данных
CREATE TABLE IF NOT EXISTS sources (
    id SERIAL PRIMARY KEY,
    url VARCHAR(2048) UNIQUE NOT NULL, -- URL источника, UNIQUE, чтобы избежать дубликатов
    type VARCHAR(50) NOT NULL,        -- Тип источника (например, 'telegram_channel', 'news_website', 'api_feed')
    name VARCHAR(255) UNIQUE NOT NULL, -- Человекочитаемое имя источника (например, 'РИА Новости', 'Коммерсантъ', 'Telegram: Новости')
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
    title VARCHAR(1024),                 -- Заголовок статьи (может быть NULL, если не удалось извлечь)
    published_at TIMESTAMP WITH TIME ZONE, -- Оригинальная дата публикации статьи (если доступна)
    collected_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- Дата и время, когда статья была собрана
    is_processed BOOLEAN DEFAULT FALSE,  -- Флаг, указывающий, была ли статья обработана NER
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
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
    meta JSON,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Индексы для быстрого поиска по сущностям
CREATE INDEX IF NOT EXISTS idx_named_entities_canonical_name ON named_entities (canonical_name);
CREATE INDEX IF NOT EXISTS idx_named_entities_type ON named_entities (type);
CREATE INDEX IF NOT EXISTS idx_named_entities_last_seen ON named_entities (last_seen_at DESC);

-- Таблица для связей между статьей и обнаруженной сущностью
-- Это будет содержать каждое упоминание сущности в статье
CREATE TABLE IF NOT EXISTS entity_mentions (
    id BIGSERIAL PRIMARY KEY, -- Используем BIGSERIAL, так как упоминаний может быть очень много
    article_id INTEGER NOT NULL,         -- Внешний ключ к таблице articles
    entity_id INTEGER NOT NULL,          -- Внешний ключ к таблице named_entities
    -- position_in_text INTEGER,         -- Начальная позиция (индекс символа) в полном тексте статьи (опционально, если будете хранить полный текст)
    -- end_position_in_text INTEGER,     -- Конечная позиция (индекс символа)
    -- context_snippet TEXT,                -- Небольшой фрагмент текста, где найдена сущность (для контекста)
    confidence_score NUMERIC(5,4),       -- Оценка уверенности модели NER (от 0.0 до 1.0)
    
    CONSTRAINT fk_article
        FOREIGN KEY (article_id)
        REFERENCES articles (id)
        ON DELETE CASCADE, -- Если статья удалена, удалить и упоминания в ней
    CONSTRAINT fk_entity
        FOREIGN KEY (entity_id)
        REFERENCES named_entities (id)
        ON DELETE CASCADE, -- Если сущность удалена, удалить и упоминания о ней
    
    -- Комбинированный индекс для быстрого поиска упоминаний сущности в статье
    UNIQUE (article_id, entity_id) -- предотвратить дубликаты упоминаний в одной статье
);

-- Индексы для быстрого поиска упоминаний
CREATE INDEX IF NOT EXISTS idx_entity_mentions_article_id ON entity_mentions (article_id);
CREATE INDEX IF NOT EXISTS idx_entity_mentions_entity_id ON entity_mentions (entity_id);

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