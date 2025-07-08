from fastapi import FastAPI, Body, HTTPException
from pydantic import BaseModel
from typing import List, Union
# import psycopg2  # PostgreSQL connection закомментировано для локального запуска
# import os        # переменные окружения для БД
import spacy

# Загрузка модели spaCy для русского языка
nlp = spacy.load("ru_core_news_lg")

# Pydantic models
class Entity(BaseModel):
    name: str
    type: str
    context: str

app = FastAPI(
    title="NER Service",
    version="1.0",
)

# Закомментировано: подключение к PostgreSQL
# conn = psycopg2.connect(
#     dbname=os.getenv("POSTGRES_DB"),
#     user=os.getenv("POSTGRES_USER"),
#     password=os.getenv("POSTGRES_PASSWORD"),
#     host=os.getenv("POSTGRES_HOST"),
# )

@app.post("/process", response_model=List[Entity])
def process(text: Union[str, dict]):
    # Получить сырой текст
    raw = text if isinstance(text, str) else text.get("text")
    if not raw:
        raise HTTPException(status_code=400, detail="Empty text")

    # Вызов модели NER (spaCy)
    entities = run_ner_model(raw)

    # Закомментировано: сохранение в БД
    # with conn.cursor() as cur:
    #     for ent in entities:
    #         cur.execute(
    #             "INSERT INTO entities (name, type, context) VALUES (%s, %s, %s)",
    #             (ent.name, ent.type, ent.context)
    #         )
    #     conn.commit()

    return [ent.dict() for ent in entities]


def run_ner_model(text: str) -> List[Entity]:
    """
    Извлекает именованные сущности из текста с помощью spaCy и возвращает список Pydantic моделей Entity
    """
    doc = nlp(text)
    results: List[Entity] = []
    for ent in doc.ents:
        sent = ent.sent.text if ent.sent else text
        results.append(Entity(name=ent.text, type=ent.label_, context=sent))
    return results

# Локальный запуск без FastAPI и без запросов
if __name__ == "__main__":
    sample_text = input("Введите текст для обработки: ")
    ents = run_ner_model(sample_text)
    for e in ents:
        print(f"Name: {e.name}, Type: {e.type}, Context: {e.context}")
