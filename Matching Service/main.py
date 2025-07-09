from fastapi import FastAPI
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity
import numpy as np
import hashlib
import os # Добавляем импорт os

# Импортируем RedisHelper из вашего redis_helper.py
from redis_helper import RedisHelper

app = FastAPI()

# Инициализируем RedisHelper
# Можно передать хост и порт явно, или он возьмет их из переменных окружения
redis_helper = RedisHelper()
redis_client = redis_helper.get_client() # Получаем прямой доступ к клиенту Redis, если это нужно

model = SentenceTransformer("ai-forever/ru-en-RoSBERTa")

EMBED_PREFIX = "embed:"
CLUSTER_PREFIX = "cluster:"
MAX_CLUSTERS = 10_000
SIMILARITY_THRESHOLD = 0.8

class EntitiesRequest(BaseModel):
    entities: list[str]


def get_embeddings(entities):
    return model.encode(entities, convert_to_numpy=True, normalize_embeddings=True)


# Теперь эти функции будут использовать методы из redis_helper
def get_all_stored_clusters():
    return redis_helper.get_all_stored_clusters(CLUSTER_PREFIX, EMBED_PREFIX)


def store_cluster(cluster_id, entity, embedding):
    redis_helper.store_cluster(cluster_id, entity, embedding, CLUSTER_PREFIX, EMBED_PREFIX)


def prune_clusters_if_needed():
    redis_helper.prune_clusters_if_needed(CLUSTER_PREFIX, EMBED_PREFIX, MAX_CLUSTERS)


def find_best_cluster(embedding, clusters):
    best_cluster_id = None
    best_sim = -1
    for cluster_id, data in clusters.items():
        sim = cosine_similarity([embedding], [data["embedding"]])[0][0]
        if sim > best_sim and sim >= SIMILARITY_THRESHOLD:
            best_sim = sim
            best_cluster_id = cluster_id
    return best_cluster_id


@app.post("/match")
async def match_entities(req: EntitiesRequest):
    entities = req.entities
    embeddings = get_embeddings(entities)
    clusters = get_all_stored_clusters() # Используем обернутую функцию
    new_assignments = {}

    for entity, emb in zip(entities, embeddings):
        cluster_id = find_best_cluster(emb, clusters)
        if cluster_id is None:
            prune_clusters_if_needed() # Используем обернутую функцию
            cluster_id = hashlib.md5(entity.encode()).hexdigest()
            store_cluster(cluster_id, entity, emb) # Используем обернутую функцию
            clusters[cluster_id] = {"members": [entity], "embedding": emb}
        else:
            # Используем rpush_to_cluster из redis_helper
            redis_helper.rpush_to_cluster(cluster_id, entity, CLUSTER_PREFIX)
        new_assignments.setdefault(cluster_id, []).append(entity)

    return {"clusters": new_assignments}