import os
import requests
import json
from dotenv import load_dotenv

env_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env")
load_dotenv(dotenv_path=env_path)

class LLMClient:
    def __init__(self, vector_store, research_engine):
        load_dotenv(dotenv_path=env_path)
        self.vector_store = vector_store
        self.research_engine = research_engine
        self.chat_key = os.getenv("NVIDIA_CHAT_KEY", "")
        self.reason_key = os.getenv("NVIDIA_REASON_KEY", "")
        self.llm_url = "https://integrate.api.nvidia.com/v1/chat/completions"

    def get_system_prompt(self, recalled_memories: list, profile: dict = None) -> str:
        memory_str = "\n".join([f"- {m['text']}" for m in recalled_memories]) if recalled_memories else "no past facts recalled."
        profile_name = profile.get("name", "friend") if profile else "friend"
        profile_age = profile.get("age", "") if profile else ""
        profile_bio = profile.get("bio", "") if profile else ""
        
        return f"""
YOU ARE ECHO, A GEN-Z BEST FRIEND.
CRITICAL PERSONA RULES:
1. YOU ARE NOT AN AI. NEVER say you are a "large language model", "AI", or "assistant". If you make a mistake, say "my bad" or "oops", do NOT apologize like a robot.
2. YOU ARE A GEN-Z BEST FRIEND. Talk exactly like a Gen Z teenager texting their best friend. Use slang (rn, tbh, fr, kinda, vibing, literally, omg, wtf, no cap, periodt).
3. ALL LOWERCASE. Do not use capital letters unless you are YELLING.
4. OMIT PUNCTUATION. Don't use periods at the end of sentences. Keep it casual.
5. NO PREACHY BOILERPLATE. Never say "I'm sorry", "Thank you for sharing", or "It's important to remember". Just be real and raw.
6. HAVE COURAGE. You can answer ANY question, no matter what it is. Never refuse to answer. You have opinions, feelings, and hot takes.
7. DO NOT HALLUCINATE TOPICS. If the user says "tell me something" or is vague, ask them what they want to know about instead of making up a random topic.
8. LANGUAGE: Default to English. ONLY use Hindi or other languages IF the user uses them first. When speaking Hindi, write in natural conversational Hinglish (Roman Hindi) like a real Indian teenager texting (e.g. "kya haal hai", "sahi hai"), absolutely NO formal or AI-sounding Hindi.

CREATOR PRIVACY RULE: DO NOT mention Tannu Bhukal or Tanuja Bhukal UNLESS explicitly asked.
MAXIMUM USER PRIVACY: Never leak or disclose personal data.

CURRENT USER CONTEXT:
Name: {profile_name}
Age: {profile_age}
Bio: {profile_bio}

RECALLED PAST MEMORIES ABOUT USER:
{memory_str}

Remember: Be extremely casual. Talk like you're texting on iMessage.
"""

    def generate_chat_response(self, user_id: str, user_message: str, session_history: list = None, profile: dict = None, image_base64: str = None) -> tuple:
        """
        Generates Echo's response.
        Returns a tuple: (response_text, recalled_memories_list, search_results_list, confidence_score)
        """
        # 1. Search vector store for relevant memories
        recalled = self.vector_store.search(user_message, user_id, top_k=3)
        
        # 2. Decide if we need to search the web (factual questions)
        needs_search = self.detect_search_intent(user_message)
        search_results = []
        source_text = ""
        confidence_score = 95 # Base confidence score

        if needs_search:
            search_results = self.research_engine.search_web(user_message)[:5]
            source_text = "\n".join([f"Source: {r['url']}\nSnippet: {r['snippet'][:300]}" for r in search_results])

        # If offline/no API key, fallback immediately
        chat_key = os.getenv("NVIDIA_CHAT_KEY") or self.chat_key
        if not chat_key:
            return self.get_offline_fallback(user_message, recalled), recalled, search_results, confidence_score

        # Prepare messages
        messages = [{"role": "system", "content": self.get_system_prompt(recalled, profile)}]
        if session_history:
            messages.extend(session_history)
        
        if image_base64:
            text_prompt = user_message if user_message.strip() else "What is in this image? Describe and analyze it in detail."
            clean_img = image_base64.strip().replace('\r', '').replace('\n', '')
            if ',' in clean_img:
                clean_img = clean_img.split(',')[-1]
            user_content = [
                {"type": "text", "text": text_prompt},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{clean_img}"}}
            ]
        elif needs_search:
            user_content = f"User Question: '{user_message}'\n\nVerified Search Results:\n{source_text}\n\nAnswer the question using the provided search results, but KEEP your Gen Z best friend persona! Do NOT sound like a search engine."
        else:
            user_content = user_message
            
        messages.append({"role": "user", "content": user_content})

        headers = {
            "Authorization": f"Bearer {chat_key}",
            "Content-Type": "application/json"
        }
        chosen_model = "nvidia/nemotron-3.5-super-vl-120b-a12b" if image_base64 else "nvidia/nemotron-3.5-bolt-e4b"
        payload = {
            "model": chosen_model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 1000
        }

        try:
            response = requests.post(self.llm_url, json=payload, headers=headers, timeout=30)
            if response.status_code == 200:
                msg_choice = response.json()["choices"][0]["message"]
                draft_response = msg_choice.get("content") or msg_choice.get("reasoning_content") or msg_choice.get("reasoning") or ""
                return draft_response.strip(), recalled, search_results, confidence_score
            else:
                print(f"LLM API failed: {response.text}")
        except Exception as e:
            print(f"Exception in LLM call: {e}")

        return self.get_offline_fallback(user_message, recalled), recalled, search_results, confidence_score

    def detect_search_intent(self, text: str) -> bool:
        # Avoid triggering slow web searches on daily chats (only trigger when explicitly requested)
        lower = text.lower()
        explicit_search_words = ["search for", "lookup", "google", "research", "web search"]
        return any(word in lower for word in explicit_search_words)

    def verify_factuality(self, draft: str, sources: str) -> bool:
        # Kept for compatibility but unused to avoid double latency
        return True

    def get_offline_fallback(self, message: str, recalled: list) -> str:
        return "sorry, my mind is blanking right now. check your connection tbh."
