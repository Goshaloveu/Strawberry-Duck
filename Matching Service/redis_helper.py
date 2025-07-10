import os
import redis
import pickle
import numpy as np # Добавляем numpy для работы с эмбеддингами

class RedisHelper:
    def __init__(self, host=None, port=None, db=0):
        # Получаем хост и порт из переменных окружения, если не переданы
        self.host = host if host else os.getenv("REDIS_HOST", "redis")
        self.port = int(port) if port else int(os.getenv("REDIS_PORT", 6379))
        self.db = db
        self.client = self._connect()

    def _connect(self):  
        """Пытаемся подключиться к Redis."""
        try:
            r = redis.Redis(host=self.host, port=self.port, db=self.db, decode_responses=False) # decode_responses=False для pickle/numpy.tobytes
            r.ping() # Проверяем соединение
            print(f"✅ Connected to Redis at {self.host}:{self.port}")
            return r
        except redis.exceptions.ConnectionError as e:
            print(f"❌ Could not connect to Redis at {self.host}:{self.port}: {e}")
            # В продакшене здесь можно добавить болееRobust логику повторных попыток или exit
            raise

    def get_client(self):
        """Возвращает прямой клиент Redis."""
        return self.client

    def save_to_redis(self, key: str, data, expire_hours: int = 24):
        """Сохраняет данные в Redis, сериализуя их с помощью pickle."""
        try:
            serialized = pickle.dumps(data)
            self.client.set(key, serialized)
            if expire_hours > 0:
                self.client.expire(key, expire_hours * 3600)
            print(f"✅ Saved to Redis: {key}")
        except Exception as e:
            print(f"❌ Error saving to Redis key {key}: {e}")
            raise

    def load_from_redis(self, key: str):
        """Загружает данные из Redis, десериализуя их с помощью pickle."""
        try:
            data = self.client.get(key)
            if data is None:
                # В зависимости от логики, можно вернуть None или вызвать исключение
                print(f"ℹ️ No data found for key: {key}")
                return None
            print(f"✅ Loaded from Redis: {key}")
            return pickle.loads(data)
        except Exception as e:
            print(f"❌ Error loading from Redis key {key}: {e}")
            raise

    def get_all_stored_clusters(self, cluster_prefix: str, embed_prefix: str):
        """Получает все хранимые кластеры из Redis."""
        cluster_keys = self.client.keys(f"{cluster_prefix}*")
        clusters = {}
        for key in cluster_keys:
            cluster_id = key.decode().split(":")[-1] if isinstance(key, bytes) else key.split(":")[-1]
            # decode_responses=True в инициализации клиента Redis для lrange и get
            # Но если вы используете pickle.dumps для embedding, то клиент должен быть decode_responses=False
            # Давайте предположим, что lrange будет возвращать байты, а мы их декодируем
            members_bytes = self.client.lrange(key, 0, -1)
            members = [m.decode('utf-8') for m in members_bytes] # Декодируем члены кластера

            emb_key = f"{embed_prefix}{cluster_id}"
            emb_bytes = self.client.get(emb_key) # Получаем эмбеддинг как байты

            if emb_bytes:
                # Предполагаем, что эмбеддинги сохраняются как байты numpy
                # Если вы сохраняете через np.array2string, то нужно будет раскомментировать строку ниже
                # emb = np.fromstring(emb_bytes.decode('utf-8').strip('[]'), sep=',')
                emb = np.frombuffer(emb_bytes, dtype=np.float32) # Или тот dtype, который вы используете для эмбеддингов
                clusters[cluster_id] = {"members": members, "embedding": emb}
        return clusters

    def store_cluster(self, cluster_id: str, entity: str, embedding: np.ndarray, cluster_prefix: str, embed_prefix: str):
        """Сохраняет новый кластер в Redis."""
        self.client.rpush(f"{cluster_prefix}{cluster_id}", entity.encode('utf-8')) # Кодируем сущность в байты
        # Сохраняем эмбеддинг как байты (наиболее эффективно)
        self.client.set(f"{embed_prefix}{cluster_id}", embedding.tobytes())
        # Если вы хотите сохранять как строку, используйте:
        # self.client.set(f"{embed_prefix}{cluster_id}", np.array2string(embedding, separator=',').encode('utf-8'))

    def rpush_to_cluster(self, cluster_id: str, entity: str, cluster_prefix: str):
        """Добавляет сущность в существующий кластер."""
        self.client.rpush(f"{cluster_prefix}{cluster_id}", entity.encode('utf-8')) # Кодируем сущность в байты

    def prune_clusters_if_needed(self, cluster_prefix: str, embed_prefix: str, max_clusters: int):
        """Удаляет старые кластеры, если их количество превышает MAX_CLUSTERS."""
        cluster_keys = self.client.keys(f"{cluster_prefix}*")
        if len(cluster_keys) <= max_clusters:
            return

        cluster_sizes = []
        for key in cluster_keys:
            size = self.client.llen(key)
            cluster_sizes.append((key, size))

        cluster_sizes.sort(key=lambda x: x[1])
        to_remove = len(cluster_keys) - max_clusters

        for i in range(to_remove):
            self.client.delete(cluster_sizes[i][0])
            self.client.delete(cluster_sizes[i][0].replace(cluster_prefix, embed_prefix))