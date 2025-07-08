from fastapi import FastAPI
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity
# from sklearn.cluster import AffinityPropagation
import redis
import numpy as np
import hashlib
# import json

app = FastAPI()

redis_client = redis.Redis(host="localhost", port=6379, db=0, decode_responses=True)

model = SentenceTransformer("ai-forever/ru-en-RoSBERTa")

EMBED_PREFIX = "embed:"
CLUSTER_PREFIX = "cluster:"
MAX_CLUSTERS = 10_000
SIMILARITY_THRESHOLD = 0.8

class EntitiesRequest(BaseModel):
    entities: list[str]


def get_embeddings(entities):
    return model.encode(entities, convert_to_numpy=True, normalize_embeddings=True)


def get_all_stored_clusters():
    cluster_keys = redis_client.keys(f"{CLUSTER_PREFIX}*")
    clusters = {}
    for key in cluster_keys:
        cluster_id = key.split(":")[-1]
        members = redis_client.lrange(key, 0, -1)
        emb_key = f"{EMBED_PREFIX}{cluster_id}"
        emb = np.fromstring(redis_client.get(emb_key), sep=',')
        clusters[cluster_id] = {"members": members, "embedding": emb}
    return clusters


def store_cluster(cluster_id, entity, embedding):
    redis_client.rpush(f"{CLUSTER_PREFIX}{cluster_id}", entity)
    redis_client.set(f"{EMBED_PREFIX}{cluster_id}", np.array2string(embedding, separator=','))


def prune_clusters_if_needed():
    cluster_keys = redis_client.keys(f"{CLUSTER_PREFIX}*")
    if len(cluster_keys) <= MAX_CLUSTERS:
        return

    cluster_sizes = []
    for key in cluster_keys:
        size = redis_client.llen(key)
        cluster_sizes.append((key, size))

    cluster_sizes.sort(key=lambda x: x[1])
    to_remove = len(cluster_keys) - MAX_CLUSTERS

    for i in range(to_remove):
        redis_client.delete(cluster_sizes[i][0])
        redis_client.delete(cluster_sizes[i][0].replace(CLUSTER_PREFIX, EMBED_PREFIX))


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
    clusters = get_all_stored_clusters()
    new_assignments = {}

    for entity, emb in zip(entities, embeddings):
        cluster_id = find_best_cluster(emb, clusters)
        if cluster_id is None:
            prune_clusters_if_needed()
            cluster_id = hashlib.md5(entity.encode()).hexdigest()
            store_cluster(cluster_id, entity, emb)
            clusters[cluster_id] = {"members": [entity], "embedding": emb}
        else:
            redis_client.rpush(f"{CLUSTER_PREFIX}{cluster_id}", entity)
        new_assignments.setdefault(cluster_id, []).append(entity)

    return {"clusters": new_assignments}
