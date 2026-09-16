import numpy as np
import json
import os
import requests

class VectorStore:
    def __init__(self, storage_path=None):
        if storage_path is None:
            storage_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data", "vector_store.json")
        self.storage_path = storage_path
        self.data = [] # List of dicts: {"text": str, "vector": list, "metadata": dict}
        self.api_key = os.getenv("NVIDIA_EMBED_KEY", "")
        self.embed_url = "https://integrate.api.nvidia.com/v1/embeddings"
        self.load()

    def load(self):
        if os.path.exists(self.storage_path):
            try:
                with open(self.storage_path, "r", encoding="utf-8") as f:
                    self.data = json.load(f)
            except Exception as e:
                print(f"Error loading vector store: {e}")
                self.data = []

    def save(self):
        os.makedirs(os.path.dirname(self.storage_path), exist_ok=True)
        try:
            with open(self.storage_path, "w", encoding="utf-8") as f:
                json.dump(self.data, f, indent=2, ensure_ascii=False)
        except Exception as e:
            print(f"Error saving vector store: {e}")

    def get_embedding(self, text: str) -> list:
        if not self.api_key:
            # Fallback/mock vector if no API key is set (simple hash vector for offline development)
            mock_vec = np.zeros(1024)
            for i, char in enumerate(text[:1024]):
                mock_vec[i % 1024] += ord(char)
            norm = np.linalg.norm(mock_vec)
            if norm > 0:
                mock_vec = mock_vec / norm
            return mock_vec.tolist()

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        payload = {
            "input": [text],
            "model": "nvidia/nemotron-3-embed-1b",
            "input_type": "query",
            "encoding_format": "float"
        }
        try:
            response = requests.post(self.embed_url, json=payload, headers=headers, timeout=5)
            if response.status_code == 200:
                res_data = response.json()
                return res_data["data"][0]["embedding"]
            else:
                print(f"Embedding API error: {response.text}")
                return []
        except Exception as e:
            print(f"Exception during embedding retrieval: {e}")
            return []

    def add_item(self, text: str, metadata: dict = None):
        embedding = self.get_embedding(text)
        if embedding:
            self.data.append({
                "text": text,
                "vector": embedding,
                "metadata": metadata or {}
            })
            self.save()

    def search(self, query: str, user_id: str, top_k: int = 3) -> list:
        query_vector = self.get_embedding(query)
        if not query_vector or not self.data:
            return []

        q_vec = np.array(query_vector)
        matches = []

        for item in self.data:
            # Skip records belonging to other users
            item_metadata = item.get("metadata", {})
            if item_metadata.get("user_id") != user_id:
                continue

            d_vec = np.array(item["vector"])
            # Cosine Similarity Calculation
            dot_product = np.dot(q_vec, d_vec)
            norm_q = np.linalg.norm(q_vec)
            norm_d = np.linalg.norm(d_vec)
            
            if norm_q > 0 and norm_d > 0:
                similarity = dot_product / (norm_q * norm_d)
            else:
                similarity = 0.0
            
            matches.append((similarity, item))

        # Sort matches by similarity descending
        matches.sort(key=lambda x: x[0], reverse=True)
        return [{"similarity": float(score), "text": item["text"], "metadata": item["metadata"]} for score, item in matches[:top_k]]
