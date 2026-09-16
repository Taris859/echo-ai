import os
import sys
import json
import requests

# Ensure backend directory is in the python path for robust module importing
backend_dir = os.path.dirname(os.path.abspath(__file__))
if backend_dir not in sys.path:
    sys.path.append(backend_dir)

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv
import firebase_admin
from firebase_admin import credentials, auth

# Load env variables (NVIDIA_API_KEY, TAVILY_API_KEY, SUPABASE_URL, etc.)
env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
load_dotenv(dotenv_path=env_path)

from services.cloud_db import CloudDB
from services.vector_store import VectorStore
from services.research_engine import ResearchEngine
from services.memory_manager import MemoryManager
from services.llm_client import LLMClient

# Initialize Firebase Admin safely
firebase_initialized = False
try:
    cred_path = os.path.join(os.path.dirname(__file__), "secrets", "firebase-admin.json")
    if os.path.exists(cred_path):
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
        firebase_initialized = True
        print("Firebase Admin SDK initialized successfully.")
    else:
        print("WARNING: secrets/firebase-admin.json not found. Token verification endpoint will run in mock/development mode.")
except Exception as e:
    print(f"Firebase Admin initialization failed: {e}")

app = FastAPI(title="Echo Companion Backend")

# Setup CORS for development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Services
db = CloudDB()
vector_store = VectorStore()
research_engine = ResearchEngine()
memory_manager = MemoryManager(db, vector_store)
llm_client = LLMClient(vector_store, research_engine)

@app.get("/health")
def health_check():
    return {"status": "online", "nvidia_connected": bool(os.getenv("NVIDIA_CHAT_KEY"))}

from pydantic import BaseModel

class ProfileModel(BaseModel):
    user_id: str
    name: str
    age: int
    gender: str
    bio: str

class RegisterModel(BaseModel):
    email: str
    password: str
    name: str

class LoginModel(BaseModel):
    email: str
    password: str

class TokenVerifyModel(BaseModel):
    id_token: str

@app.post("/auth/verify-token")
def verify_token_endpoint(data: TokenVerifyModel):
    if not firebase_initialized:
        # Development fallback mode
        print("Verification Fallback: Firebase Admin not configured. Bootstrapping user user_g_offline_fallback.")
        return db.login_or_register_google("user_g_offline_fallback", "alex.rivera@gmail.com", "Alex Rivera")
        
    try:
        decoded_token = auth.verify_id_token(data.id_token)
        uid = decoded_token['uid']
        email = decoded_token.get('email', '')
        name = decoded_token.get('name', 'friend')
        
        # Identity is validated - bootstrap user profile in database securely
        return db.login_or_register_google(uid, email, name)
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Unauthorized: ID Token verification failed: {e}")

@app.delete("/vault/delete")
def delete_vault_fact_endpoint(user_id: str, fact_id: int):
    return db.delete_vault_fact(user_id, fact_id)

@app.get("/sessions")
def get_sessions_endpoint(user_id: str):
    return db.get_user_sessions(user_id)

@app.get("/sessions/{session_id}/messages")
def get_session_messages_endpoint(session_id: str):
    return db.get_session_messages(session_id)

@app.get("/vault")
def get_vault_memories(user_id: str = "default_user"):
    """Returns all memories currently saved in the vault for a specific user"""
    return db.get_all_vault_facts(user_id)

@app.get("/profile")
def get_user_profile(user_id: str = "default_user"):
    """Returns the user's profile details"""
    return db.get_profile(user_id)

@app.post("/profile")
def save_user_profile(profile: ProfileModel):
    """Saves or updates the user's profile details"""
    db.save_profile(profile.user_id, profile.name, profile.age, profile.gender, profile.bio)
    return {"status": "success"}

@app.websocket("/chat")
async def websocket_chat(websocket: WebSocket, user_id: str = "default_user"):
    await websocket.accept()
    print(f"New WebSocket client connected for user: {user_id}")
    try:
        await websocket.send_json({
            "stage": "connected",
            "message": "Connection established successfully."
        })
    except Exception as e:
        print(f"Failed to send connection message: {e}")
    session_id = f"session_{user_id}"
    
    try:
        while True:
            # Receive user message
            data = await websocket.receive_text()
            
            # Step 1: Send 'analyzing' status to UI transparent drawer
            await websocket.send_json({
                "stage": "searching",
                "message": "searching web & recalling past memories...",
                "query": data
            })
            
            # Save user message to database
            db.save_message(session_id, user_id, "user", data)
            
            # Retrieve user profile metadata & recent session conversation history (last 15 messages)
            user_profile = db.get_profile(user_id)
            past_messages = db.get_session_messages(session_id)
            recent_history = []
            if past_messages:
                # Format recent messages for LLM context (exclude current prompt just saved)
                for msg in past_messages[-16:-1]:
                    role = "assistant" if msg.get("sender") == "echo" else "user"
                    recent_history.append({"role": role, "content": msg.get("text", "")})
            
            # Step 2: Trigger LLM generation with multi-turn conversation history
            reply, recalled_memories, search_results, confidence_score = llm_client.generate_chat_response(
                user_id, data, session_history=recent_history, profile=user_profile
            )
            
            # Step 3: Send 'evaluating' status to transparent drawer
            await websocket.send_json({
                "stage": "evaluating",
                "message": f"running safety audit. confidence score: {confidence_score}%",
                "recalled": recalled_memories,
                "sources": search_results,
                "confidence": confidence_score
            })
            
            # Save Echo's response to database
            db.save_message(session_id, user_id, "echo", reply)
            
            # Step 4: Run asynchronous memory extraction (to find new facts to remember)
            new_fact = memory_manager.analyze_and_extract_memories(user_id, data)
            
            # Step 5: Send final output response and updated vault status
            await websocket.send_json({
                "stage": "complete",
                "reply": reply,
                "confidence": confidence_score,
                "recalled": recalled_memories,
                "sources": search_results,
                "new_fact_learned": new_fact
            })
            
    except WebSocketDisconnect:
        print(f"Client disconnected: {user_id}")
    except Exception as e:
        print(f"WebSocket error for {user_id}: {e}")

class APIChatRequest(BaseModel):
    messages: list
    model: str = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning"
    temperature: float = 0.6
    top_p: float = 0.95
    max_tokens: int = 4096
    reasoning_budget: int = 2048

class APIExtractMemoryRequest(BaseModel):
    user_message: str
    memories_context: str
    system_prompt: str

@app.post("/api/chat")
def api_chat_proxy(req: APIChatRequest):
    """Secure proxy for LLM chat requests from Flutter app."""
    chat_key = os.getenv("NVIDIA_CHAT_KEY", "")
    if not chat_key:
        return {"reply": "sorry, my mind is blanking right now. check your connection tbh."}
    
    headers = {
        "Authorization": f"Bearer {chat_key}",
        "Content-Type": "application/json"
    }
    payload = {
        "model": req.model,
        "messages": req.messages,
        "temperature": req.temperature,
        "top_p": req.top_p,
        "max_tokens": req.max_tokens,
        "reasoning_budget": req.reasoning_budget,
    }
    try:
        res = requests.post("https://integrate.api.nvidia.com/v1/chat/completions", json=payload, headers=headers, timeout=60)
        if res.status_code == 200:
            msg = res.json()["choices"][0]["message"]
            # Nemotron reasoning models return content or reasoning field
            content = msg.get("content") or msg.get("reasoning") or msg.get("reasoning_content") or ""
            return {"reply": content.strip()}
        print(f"NVIDIA API error {res.status_code}: {res.text[:300]}")
    except Exception as e:
        print(f"API chat proxy error: {e}")
    return {"reply": "sorry, my mind is blanking right now. check your connection tbh."}

@app.post("/api/extract-memory")
def api_extract_memory_proxy(req: APIExtractMemoryRequest):
    """Secure proxy for memory extraction requests from Flutter app."""
    chat_key = os.getenv("NVIDIA_CHAT_KEY", "")
    if not chat_key:
        return {}
    
    headers = {
        "Authorization": f"Bearer {chat_key}",
        "Content-Type": "application/json"
    }
    payload = {
        "model": "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
        "messages": [
            {"role": "system", "content": req.system_prompt},
            {"role": "user", "content": f"Analyze and respond with ONLY a raw JSON object: '{req.user_message}'"}
        ],
        "temperature": 0.1,
        "max_tokens": 512,
        "reasoning_budget": 256,
    }
    try:
        res = requests.post("https://integrate.api.nvidia.com/v1/chat/completions", json=payload, headers=headers, timeout=25)
        if res.status_code == 200:
            msg = res.json()["choices"][0]["message"]
            # Reasoning models may return content or reasoning field
            raw = msg.get("content") or msg.get("reasoning") or msg.get("reasoning_content") or ""
            cleaned = raw.strip()
            # Strip markdown code fences if present
            if "```json" in cleaned:
                cleaned = cleaned.split("```json")[1].split("```")[0].strip()
            elif "```" in cleaned:
                cleaned = cleaned.split("```")[1].split("```")[0].strip()
            # Extract first JSON object
            start = cleaned.find("{")
            end = cleaned.rfind("}")
            if start != -1 and end != -1:
                cleaned = cleaned[start:end+1]
            return json.loads(cleaned)
        print(f"extract-memory NVIDIA error {res.status_code}: {res.text[:200]}")
    except Exception as e:
        print(f"API extract memory proxy error: {e}")
    return {}
