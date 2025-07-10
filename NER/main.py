from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import requests
import json
import logging

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="TrendCore NER API",
    description="API для извлечения именованных сущностей из текста через Ollama",
    version="3.0"
)

class TextRequest(BaseModel):
    text: str
    server_host: str = "http://localhost:8081"

class Entity(BaseModel):
    name: str
    type: str
    context: str
    confidence: float | None = None

class EntitiesResponse(BaseModel):
    entities: list[Entity]

SYSTEM_PROMPT = """
Ты — ядро системы мониторинга трендов. Твоя задача — из входящих новостных текстов автоматически извлекать и структурировать значимые именованные сущности трёх типов: PER (персоны), ORG (организации), EVENT (события). Выводи только JSON по шаблону: {\"entities\":[{\"name\":...,\"type\":...,\"context\":...,\"confidence\":...}, ...]}. Если сущностей нет — возвращай {\"entities\": []}.
"""

def extract_entities(text: str, server_host: str) -> dict:
    try:
        url = f"{server_host}/api/generate"
        prompt = f"{SYSTEM_PROMPT}\n\nТекст: {text}\n"
        payload = {
            "model": "gemma3:27b",
            "prompt": prompt,
            "stream": False
        }
        response = requests.post(url, json=payload, timeout=120)
        response.raise_for_status()
        # Ollama возвращает {'response': '...'}
        result_text = response.json().get('response', '')
        # Найти JSON в ответе (если модель добавила текст до/после)
        try:
            json_start = result_text.find('{')
            json_end = result_text.rfind('}') + 1
            json_str = result_text[json_start:json_end]
            result = json.loads(json_str)
        except Exception as e:
            logger.error(f"Ошибка парсинга JSON из ответа модели: {e}")
            result = {"entities": []}
        return result
    except Exception as e:
        logger.error(f"Ошибка при обращении к Ollama: {str(e)}")
        return {"entities": []}

@app.post("/extract-entities", response_model=EntitiesResponse)
async def api_extract_entities(request: TextRequest):
    """
    Извлекает именованные сущности из текста через Ollama
    """
    try:
        result = extract_entities(request.text, request.server_host)
        return result
    except Exception as e:
        logger.exception("API error")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    # uvicorn.run(app, host="0.0.0.0", port=8000)