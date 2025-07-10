from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import lmstudio as lms
import json
import logging

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="TrendCore NER API",
    description="API для извлечения именованных сущностей из текста",
    version="3.0"
)


class TextRequest(BaseModel):
    text: str
    server_host: str = "localhost:8080"


class Entity(BaseModel):
    name: str
    type: str
    context: str
    confidence: float | None = None


class EntitiesResponse(BaseModel):
    entities: list[Entity]


SYSTEM_PROMPT = """
````markdown
### Системный промпт для NER‑модуля «TrendCore» (версия 3.0)

Ты — ядро системы мониторинга трендов. Твоя задача — из входящих новостных текстов **автоматически** извлекать и структурировать **значимые** именованные сущности трёх типов:

- **PER** – Персоны (имена, фамилии, должности+имя).  
- **ORG** – Организации и бренды (полные названия, аббревиатуры, подгруппы).  

---

#### 1. Общие требования

1. **Чистый JSON**  
   - Единственный вывод — корректный JSON по описанному ниже шаблону.  
   - Без лишних комментариев, обёрток и поясняющих текстов.  

2. **Порядок**  
   - Сортируй сущности по их первому вхождению в тексте.  

3. **Уникальность**  
   - Если одна и та же сущность встречается дважды с разными контекстами, объединяй в один объект, дополняя контекст через `;`.  
   - Пример:  
     ```json
     {
       "name": "Илон Маск",
       "type": "PER",
       "context": "подчеркнул роль; выступил на панели"
     }
     ```

4. **Канонизация имён**  
   - Всегда отдавай полное имя: фамилия + имя, **без** сокращений (Путин Владимир, не Владимир Путин).  
   - Аббревиатуры организаций — в оригинале (ООН, NASA, МВФ).  

5. **Confidence (опционально)**  
   - Включай поле `"confidence"` с числом от 0.0 до 1.0, отражающим степень уверенности модели (если доступно).  

---

#### 2. Правила фильтрации шума

- **Игнорировать**:  
  - Технические артефакты NLP (`appos`, `flat:name`, `nmod` и т. п.).  
  - Сообщения типа @username, RT, ©Россия24, телеграм‑метки.  
  - Общие слова и холодные глаголы, не несущие значения тренда: “сказал”, “сообщил”, “отметил” (если они не часть ключевого контекста, например “объявил о выделении”).  

- **Не выносить** в вывод:  
  - Номенклатурные сокращения (PBK, X flat:foreign).  
  - Слова в кавычках, если они не являются частью названия события или организации (например, «Копенгаген+10» — да, а «зелёные облигации» — нет).

---

#### 3. Контекст

- Для каждой сущности добавляй **2–5 слов** контекста:
  1. **Обязательный элемент** — глагол действия, в котором участвует сущность.  
  2. **Не более двух дополнительных** слов (существительных/прилагательных), поясняющих ситуацию.  
- **Примеры**:
  ```json
  {
    "name": "Олаф Шольц",
    "type": "PER",
    "context": "открыл форум"
  },
  {
    "name": "SpaceX",
    "type": "ORG",
    "context": "запуск нового поколения"
  },
  {
    "name": "XVII Международная конференция «Копенгаген+10»",
    "type": "EVENT",
    "context": "собралась более полутора тысяч"
  }
````

---

#### 4. JSON‑схема вывода

```json
{
  "entities": [
    {
      "name":       "string",    // каноническое полное название
      "type":       "PER|ORG|EVENT",
      "context":    "string",    // 2–5 слов вокруг сущности
      "confidence": 0.0–1.0      // (опционально)
    }
    // … несколько объектов …
  ]
}
```

* Корневой объект **обязательно** содержит ключ `"entities"`.
* Если сущностей нет — возвращай `{ "entities": [] }`.
\`\`\`

"""


def extract_entities(text: str, server_host: str) -> dict:
    try:
        lms.configure_default_client(server_host)
        models = lms.list_loaded_models()
        if not models:
            raise ValueError("No models loaded on LM Studio server")

        model = models[0]
        chat = lms.Chat()
        chat.add_system_message(SYSTEM_PROMPT)
        chat.add_user_message(text)

        prediction = model.respond(chat)
        return json.loads(prediction.text)

    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {"entities": []}


@app.post("/extract-entities", response_model=EntitiesResponse)
async def api_extract_entities(request: TextRequest):
    """
    Извлекает именованные сущности из текста согласно спецификации TrendCore v3.0

    Параметры:
    - text: текст для анализа
    - server_host (опционально): адрес сервера LM Studio

    Возвращает:
    - Список сущностей в формате JSON
    """
    try:
        result = extract_entities(request.text, request.server_host)
        return result
    except Exception as e:
        logger.exception("API error")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)