import os
import sqlite3
import json
import requests
import base64
import hashlib
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad

class CloudDB:
    def __init__(self, db_path="E:/Echo_AI_APP/backend/data/echo_memory.db"):
        self.db_path = db_path
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        self.supabase_url = os.getenv("SUPABASE_URL", "")
        self.supabase_key = os.getenv("SUPABASE_KEY", "")
        
        # Key derivation for database level encryption
        secret_source = os.getenv("CHAT_ENCRYPTION_KEY") or os.getenv("NVIDIA_CHAT_KEY") or "echo_local_default_secure_salt"
        self.enc_key = hashlib.sha256(secret_source.encode()).digest()
        
        self.init_local_db()

    def _encrypt(self, plaintext: str) -> str:
        if not plaintext:
            return ""
        try:
            cipher = AES.new(self.enc_key, AES.MODE_CBC)
            ct_bytes = cipher.encrypt(pad(plaintext.encode('utf-8'), AES.block_size))
            iv = base64.b64encode(cipher.iv).decode('utf-8')
            ct = base64.b64encode(ct_bytes).decode('utf-8')
            return json.dumps({"iv": iv, "ciphertext": ct})
        except Exception as e:
            print(f"Encryption error: {e}")
            return plaintext

    def _decrypt(self, ciphertext_json: str) -> str:
        if not ciphertext_json:
            return ""
        try:
            data = json.loads(ciphertext_json)
            iv = base64.b64decode(data["iv"])
            ct = base64.b64decode(data["ciphertext"])
            cipher = AES.new(self.enc_key, AES.MODE_CBC, iv)
            pt = unpad(cipher.decrypt(ct), AES.block_size)
            return pt.decode('utf-8')
        except Exception:
            # Fallback if text is not encrypted
            return ciphertext_json

    def init_local_db(self):
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        # Chat sessions table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS chat_sessions (
                id TEXT PRIMARY KEY,
                user_id TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        # Messages table (stores encrypted content and links to user_id)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT,
                user_id TEXT,
                sender TEXT,
                content TEXT,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        # Memory Vault facts table with status
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS memory_vault (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT,
                fact_type TEXT, -- e.g., 'relationship', 'preference', 'general'
                fact_text TEXT,
                status TEXT DEFAULT 'active',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        # Profiles table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS profiles (
                user_id TEXT PRIMARY KEY,
                name TEXT,
                age INTEGER,
                gender TEXT,
                bio TEXT,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        # Users table for auth
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                email TEXT UNIQUE,
                password TEXT,
                google_id TEXT,
                name TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()
        conn.close()

    def save_profile(self, user_id: str, name: str, age: int, gender: str, bio: str):
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("""
            INSERT OR REPLACE INTO profiles (user_id, name, age, gender, bio, updated_at)
            VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        """, (user_id, name, age, gender, bio))
        conn.commit()
        conn.close()

    def get_profile(self, user_id: str) -> dict:
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT name, age, gender, bio FROM profiles WHERE user_id = ?", (user_id,))
        row = cursor.fetchone()
        conn.close()
        if row:
            return {"name": row[0], "age": row[1], "gender": row[2], "bio": row[3]}
        return {"name": "friend", "age": 0, "gender": "unknown", "bio": ""}

    # Cloud Sync Helpers (Supabase/PostgreSQL)
    def is_cloud_enabled(self) -> bool:
        return bool(self.supabase_url and self.supabase_key)

    def save_message(self, session_id: str, user_id: str, sender: str, content: str):
        encrypted_content = self._encrypt(content)
        
        # 1. Save Locally
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("INSERT OR IGNORE INTO chat_sessions (id, user_id) VALUES (?, ?)", (session_id, user_id))
        cursor.execute("INSERT INTO messages (session_id, user_id, sender, content) VALUES (?, ?, ?, ?)", 
                       (session_id, user_id, sender, encrypted_content))
        conn.commit()
        conn.close()

        # 2. Sync to Cloud
        if self.is_cloud_enabled():
            url = f"{self.supabase_url}/rest/v1/messages"
            headers = {
                "apikey": self.supabase_key,
                "Authorization": f"Bearer {self.supabase_key}",
                "Content-Type": "application/json",
                "Prefer": "return=minimal"
            }
            payload = {
                "session_id": session_id,
                "user_id": user_id,
                "sender": sender,
                "content": encrypted_content
            }
            try:
                requests.post(url, json=payload, headers=headers, timeout=3)
            except Exception as e:
                print(f"Cloud sync message error: {e}")

    def add_vault_fact(self, user_id: str, fact_type: str, fact_text: str):
        encrypted_fact = self._encrypt(fact_text)
        
        # 1. Save Locally
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("INSERT INTO memory_vault (user_id, fact_type, fact_text) VALUES (?, ?, ?)", 
                       (user_id, fact_type, encrypted_fact))
        conn.commit()
        conn.close()

        # 2. Sync to Cloud
        if self.is_cloud_enabled():
            url = f"{self.supabase_url}/rest/v1/memory_vault"
            headers = {
                "apikey": self.supabase_key,
                "Authorization": f"Bearer {self.supabase_key}",
                "Content-Type": "application/json"
            }
            payload = {
                "user_id": user_id,
                "fact_type": fact_type,
                "fact_text": encrypted_fact
            }
            try:
                requests.post(url, json=payload, headers=headers, timeout=3)
            except Exception as e:
                print(f"Cloud sync memory fact error: {e}")

    def get_all_vault_facts(self, user_id: str) -> list:
        raw_facts = []
        
        # Try Cloud first if available
        if self.is_cloud_enabled():
            url = f"{self.supabase_url}/rest/v1/memory_vault?user_id=eq.{user_id}&select=id,fact_type,fact_text"
            headers = {
                "apikey": self.supabase_key,
                "Authorization": f"Bearer {self.supabase_key}"
            }
            try:
                response = requests.get(url, headers=headers, timeout=3)
                if response.status_code == 200:
                    raw_facts = response.json()
            except Exception as e:
                print(f"Cloud fetch memory facts error, falling back to local: {e}")

        # Local Fallback
        if not raw_facts:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute("SELECT id, fact_type, fact_text FROM memory_vault WHERE user_id = ?", (user_id,))
            rows = cursor.fetchall()
            conn.close()
            raw_facts = [{"id": r[0], "fact_type": r[1], "fact_text": r[2]} for r in rows]
            
        # Decrypt facts before returning
        return [{"id": f.get("id"), "fact_type": f["fact_type"], "fact_text": self._decrypt(f["fact_text"])} for f in raw_facts]

    # User Authentication Helper Methods
    def register_user(self, email: str, password_raw: str, name: str) -> dict:
        password_hash = hashlib.sha256(password_raw.encode()).hexdigest()
        user_id = f"user_{hashlib.md5(email.lower().encode()).hexdigest()[:12]}"
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        try:
            cursor.execute("""
                INSERT INTO users (id, email, password, name)
                VALUES (?, ?, ?, ?)
            """, (user_id, email.lower(), password_hash, name))
            
            # Auto-create empty profile
            cursor.execute("""
                INSERT OR IGNORE INTO profiles (user_id, name, age, gender, bio)
                VALUES (?, ?, ?, ?, ?)
            """, (user_id, name, 0, "unknown", ""))
            
            conn.commit()
            return {"status": "success", "user_id": user_id, "name": name, "email": email}
        except sqlite3.IntegrityError:
            return {"status": "error", "message": "Email already registered."}
        finally:
            conn.close()

    def login_user(self, email: str, password_raw: str) -> dict:
        password_hash = hashlib.sha256(password_raw.encode()).hexdigest()
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT id, name, email FROM users WHERE email = ? AND password = ?", (email.lower(), password_hash))
        row = cursor.fetchone()
        conn.close()
        
        if row:
            return {"status": "success", "user_id": row[0], "name": row[1], "email": row[2]}
        return {"status": "error", "message": "Invalid email or password."}

    def login_or_register_google(self, google_id: str, email: str, name: str) -> dict:
        user_id = f"user_g_{hashlib.md5(google_id.encode()).hexdigest()[:12]}"
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Check if user exists
        cursor.execute("SELECT id, name, email FROM users WHERE google_id = ? OR email = ?", (google_id, email.lower()))
        row = cursor.fetchone()
        
        if row:
            # Update google_id if matched by email
            cursor.execute("UPDATE users SET google_id = ? WHERE id = ?", (google_id, row[0]))
            conn.commit()
            conn.close()
            return {"status": "success", "user_id": row[0], "name": row[1], "email": row[2]}
        
        # Create new user
        cursor.execute("""
            INSERT INTO users (id, email, google_id, name)
            VALUES (?, ?, ?, ?)
        """, (user_id, email.lower(), google_id, name))
        
        # Auto-create empty profile
        cursor.execute("""
            INSERT OR IGNORE INTO profiles (user_id, name, age, gender, bio)
            VALUES (?, ?, ?, ?, ?)
        """, (user_id, name, 0, "unknown", ""))
        
        conn.commit()
        conn.close()
        return {"status": "success", "user_id": user_id, "name": name, "email": email}

    # Delete fact
    def delete_vault_fact(self, user_id: str, fact_id: int):
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM memory_vault WHERE id = ? AND user_id = ?", (fact_id, user_id))
        conn.commit()
        conn.close()
        return {"status": "success"}

    # Sessions history helper
    def get_user_sessions(self, user_id: str) -> list:
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        # Find unique sessions for this user and their most recent message
        cursor.execute("""
            SELECT s.id, s.created_at, 
            (SELECT content FROM messages WHERE session_id = s.id ORDER BY timestamp DESC LIMIT 1) as last_msg
            FROM chat_sessions s
            WHERE s.user_id = ?
            ORDER BY s.created_at DESC
        """, (user_id,))
        rows = cursor.fetchall()
        conn.close()
        
        sessions = []
        for r in rows:
            last_msg = self._decrypt(r[1]) if r[1] else ""
            # If the last decrypted message is JSON (due to encryption formatting errors), extract plaintext
            if last_msg.startswith("{"):
                try:
                    last_msg = json.loads(last_msg).get("text", last_msg)
                except:
                    pass
            sessions.append({
                "session_id": r[0],
                "created_at": r[1],
                "last_message": last_msg
            })
        return sessions

    def get_session_messages(self, session_id: str) -> list:
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT sender, content, timestamp FROM messages WHERE session_id = ? ORDER BY id ASC", (session_id,))
        rows = cursor.fetchall()
        conn.close()
        
        messages = []
        for r in rows:
            text = self._decrypt(r[1])
            messages.append({
                "sender": r[0],
                "text": text,
                "timestamp": r[2]
            })
        return messages

    def archive_fact_by_content(self, user_id: str, old_fact_text: str):
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Load all active memory facts for this user
        cursor.execute("SELECT id, fact_text FROM memory_vault WHERE user_id = ? AND (status IS NULL OR status = 'active')", (user_id,))
        rows = cursor.fetchall()
        
        for row in rows:
            decrypted = self._decrypt(row[1])
            # Check overlap or containment
            if old_fact_text.lower() in decrypted.lower() or decrypted.lower() in old_fact_text.lower():
                cursor.execute("UPDATE memory_vault SET status = 'archived' WHERE id = ?", (row[0],))
                print(f"Archived conflicting fact: '{decrypted}'")
                
        conn.commit()
        conn.close()
