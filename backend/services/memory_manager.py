import json
import os
import requests

class MemoryManager:
    def __init__(self, cloud_db, vector_store):
        self.db = cloud_db
        self.vector_store = vector_store
        self.api_key = os.getenv("NVIDIA_CHAT_KEY", "")
        self.llm_url = "https://integrate.api.nvidia.com/v1/chat/completions"

    def analyze_and_extract_memories(self, user_id: str, user_message: str):
        """
        Queries Llama-3.1 via NVIDIA API to see if the message contains a fact that should be remembered,
        and determines its relationship state to existing memories (CONSISTENT, UPDATED, CONTRADICTED, UNCERTAIN).
        """
        if not self.api_key:
            return None

        # 1. Retrieve potentially related memories from vector search index
        related_memories = []
        try:
            related_memories = self.vector_store.search(user_message, user_id, top_k=5)
        except Exception as e:
            print(f"Failed to query vector store: {e}")

        memories_context = "\n".join([f"- Fact: '{m['text']}'" for m in related_memories]) if related_memories else "No related memories found."

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        system_prompt = f"""
        You are a memory extraction sub-system.
        Analyze the user's message alongside the list of recalled memories:
        
        RECALLED MEMORIES ABOUT THE USER:
        {memories_context}
        
        STRICT RULES FOR EXTRACTION:
        1. Only extract information that is actually stated or strongly implied by the user's message.
        2. NEVER infer:
           - personality traits
           - diagnoses
           - temporary emotions or daily actions (e.g. "had coffee today", "feeling sleepy")
           - casual statements, jokes, or sarcasm
           - hypothetical situations
           - details about third parties unless it materially defines the user's relationship with them.
        3. Identify if the user is explicitly correcting a fact in recalled memories.
        4. Determine transition state:
           - 'CONSISTENT': Reinforces an existing memory.
           - 'UPDATED': Updates an existing fact.
           - 'CONTRADICTED': Explicitly contradicts/corrects a stored memory.
           - 'UNCERTAIN': Statement is ambiguous or temporary. When UNCERTAIN, return {{}}.
           
        You MUST respond ONLY with a raw JSON object or an empty object {{}} if nothing permanent is shared.
        JSON format:
        {{
          "fact_type": "relationship" | "preference" | "general",
          "fact_text": "extracted fact text here",
          "transition_state": "CONSISTENT" | "UPDATED" | "CONTRADICTED" | "UNCERTAIN",
          "contradicts_fact_text": "exact text of contradicted/updated fact or null"
        }}
        """

        payload = {
            "model": "nvidia/nemotron-3-ultra-550b-a55b",
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"Analyze: '{user_message}'"}
            ],
            "temperature": 0.1,
            "response_format": {"type": "json_object"}
        }

        try:
            response = requests.post(self.llm_url, json=payload, headers=headers, timeout=10)
            if response.status_code == 200:
                res_data = response.json()
                content = res_data["choices"][0]["message"]["content"]
                extracted = json.loads(content)
                
                if extracted and "fact_text" in extracted:
                    fact_type = extracted.get("fact_type", "general")
                    fact_text = extracted["fact_text"]
                    state = extracted.get("transition_state", "UNCERTAIN")
                    contradicts_text = extracted.get("contradicts_fact_text")
                    
                    if state in ["CONTRADICTED", "UPDATED"] and contradicts_text:
                        try:
                            self.db.archive_fact_by_content(user_id, contradicts_text)
                        except Exception as ex:
                            print(f"Failed to archive conflicting memory fact: {ex}")
                    
                    if state != "UNCERTAIN":
                        # Store in database and vector search index segmented by user_id
                        self.db.add_vault_fact(user_id, fact_type, fact_text)
                        self.vector_store.add_item(fact_text, {"user_id": user_id, "type": fact_type})
                        return extracted
            else:
                print(f"Memory extraction model failed: {response.text}")
        except Exception as e:
            print(f"Error during memory extraction: {e}")

        return None
