import json
import os
from typing import Any

import requests
from firebase_functions import https_fn
from firebase_functions.options import set_global_options
from firebase_functions.params import SecretParam


set_global_options(max_instances=10, region="asia-south1")
NVIDIA_CHAT_KEY = SecretParam("NVIDIA_CHAT_KEY")
NVIDIA_URL = "https://integrate.api.nvidia.com/v1/chat/completions"
ALLOWED_MODELS = {
    "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
    "meta/llama-3.3-70b-instruct",
}


def _json_response(payload: dict[str, Any], status: int = 200) -> https_fn.Response:
    return https_fn.Response(
        json.dumps(payload),
        status=status,
        content_type="application/json",
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type",
            "Cache-Control": "no-store",
        },
    )


@https_fn.on_request(secrets=[NVIDIA_CHAT_KEY])
def echo_api(req: https_fn.Request) -> https_fn.Response:
    if req.method == "OPTIONS":
        return _json_response({}, 204)
    if req.method != "POST":
        return _json_response({"error": "method not allowed"}, 405)

    body = req.get_json(silent=True) or {}
    if not isinstance(body, dict):
        return _json_response({"error": "request body must be JSON"}, 400)

    path = req.path.rstrip("/")
    if path.endswith("/extract-memory"):
        return _extract_memory(body)
    if not path.endswith("/chat"):
        return _json_response({"error": "unknown API route"}, 404)

    messages = body.get("messages")
    if not isinstance(messages, list) or not messages or len(messages) > 30:
        return _json_response({"error": "messages must be a non-empty list"}, 400)

    model = body.get("model", "meta/llama-3.3-70b-instruct")
    if model not in ALLOWED_MODELS:
        model = "meta/llama-3.3-70b-instruct"

    payload = {
        "model": model,
        "messages": messages,
        "temperature": min(max(float(body.get("temperature", 0.7)), 0.0), 1.0),
        "max_tokens": min(max(int(body.get("max_tokens", 2048)), 1), 4096),
    }
    return _provider_request(payload)


def _provider_request(payload: dict[str, Any]) -> https_fn.Response:
    api_key = NVIDIA_CHAT_KEY.value
    if not api_key:
        return _json_response({"error": "AI provider is not configured"}, 503)
    try:
        response = requests.post(
            NVIDIA_URL,
            json=payload,
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            timeout=45,
        )
        try:
            data = response.json()
        except ValueError:
            data = {"error": "AI provider returned invalid JSON"}
        if response.status_code != 200:
            return _json_response({"error": "AI provider request failed", "provider_status": response.status_code}, 502)
        content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
        if not content:
            return _json_response({"error": "AI provider returned an empty response"}, 502)
        return _json_response({"reply": content})
    except requests.RequestException:
        return _json_response({"error": "AI provider request failed"}, 502)


def _extract_memory(body: dict[str, Any]) -> https_fn.Response:
    user_message = str(body.get("user_message", "")).strip()
    context = str(body.get("memories_context", ""))
    system_prompt = str(body.get("system_prompt", ""))
    if not user_message or len(user_message) > 12000:
        return _json_response({"error": "invalid memory request"}, 400)
    payload = {
        "model": "meta/llama-3.3-70b-instruct",
        "messages": [
            {"role": "system", "content": system_prompt[:12000]},
            {"role": "user", "content": f"Recalled memories:\n{context[:12000]}\n\nUser message:\n{user_message}"},
        ],
        "temperature": 0.1,
        "max_tokens": 300,
        "response_format": {"type": "json_object"},
    }
    response = _provider_request(payload)
    if response.status_code != 200:
        return response
    try:
        data = json.loads(response.get_data(as_text=True))
        return _json_response(json.loads(data["reply"]))
    except (KeyError, TypeError, ValueError):
        return _json_response({})
