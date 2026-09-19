const NVIDIA_URL = 'https://integrate.api.nvidia.com/v1/chat/completions';
const ALLOWED_MODELS = new Set([
  'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning',
  'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning',
]);

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json',
    },
  });
}

function providerPayload(body) {
  const messages = body.messages;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > 30) {
    return null;
  }

  const model = ALLOWED_MODELS.has(body.model)
    ? body.model
    : 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning';
  const temperature = Number(body.temperature);
  const maxTokens = Number(body.max_tokens);

  return {
    model,
    messages,
    temperature: Number.isFinite(temperature) ? Math.min(Math.max(temperature, 0), 1) : 0.7,
    max_tokens: Number.isFinite(maxTokens) ? Math.min(Math.max(maxTokens, 1), 4096) : 2048,
  };
}

async function callProvider(payload, env) {
  if (!env.NVIDIA_CHAT_KEY) {
    return json({ error: 'AI provider is not configured' }, 503);
  }

  try {
    const response = await fetch(NVIDIA_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.NVIDIA_CHAT_KEY.trim()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const providerMessage = typeof data?.detail === 'string'
        ? data.detail.slice(0, 240)
        : typeof data?.message === 'string'
          ? data.message.slice(0, 240)
          : typeof data?.error === 'string'
            ? data.error.slice(0, 240)
            : 'provider rejected the request';
      console.error('NVIDIA provider rejected request', response.status, providerMessage);
      return json({
        error: 'AI provider request failed',
        provider_status: response.status,
        provider_message: providerMessage,
      }, 502);
    }
    const reply = data?.choices?.[0]?.message?.content;
    return typeof reply === 'string' && reply.trim()
      ? json({ reply: reply.trim() })
      : json({ error: 'AI provider returned an empty response' }, 502);
  } catch (error) {
    console.error('provider request failed', error);
    return json({ error: 'AI provider request failed' }, 502);
  }
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return json({}, 204);

    const url = new URL(request.url);
    if (request.method !== 'POST') return json({ error: 'method not allowed' }, 405);
    if (url.pathname !== '/api/chat' && url.pathname !== '/api/extract-memory') {
      return json({ error: 'unknown API route' }, 404);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: 'request body must be JSON' }, 400);
    }

    if (url.pathname === '/api/extract-memory') {
      const userMessage = String(body.user_message || '').trim();
      if (!userMessage || userMessage.length > 12000) {
        return json({ error: 'invalid memory request' }, 400);
      }
      body = {
        model: 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning',
        messages: [
          { role: 'system', content: String(body.system_prompt || '').slice(0, 12000) },
          {
            role: 'user',
            content: `Recalled memories:\n${String(body.memories_context || '').slice(0, 12000)}\n\nUser message:\n${userMessage}`,
          },
        ],
        temperature: 0.1,
        max_tokens: 300,
        response_format: { type: 'json_object' },
      };
    }

    const payload = providerPayload(body);
    if (!payload) return json({ error: 'messages must be a non-empty list' }, 400);
    const response = await callProvider(payload, env);

    if (url.pathname === '/api/extract-memory' && response.ok) {
      try {
        const result = await response.json();
        return json(JSON.parse(result.reply));
      } catch {
        return json({});
      }
    }
    return response;
  },
};
