const NVIDIA_URL = 'https://integrate.api.nvidia.com/v1/chat/completions';
const ALLOWED_MODELS = new Set([
  'nvidia/nemotron-3.5-bolt-e4b',
  'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning',
  'nvidia/nemotron-3.5-lightning-30b-a3b',
  'nvidia/nemotron-3.5-super-vl-120b-a12b',
]);

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, User-Agent',
  'Access-Control-Max-Age': '86400',
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...CORS_HEADERS,
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
    : 'nvidia/nemotron-3.5-bolt-e4b';
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
    const message = data?.choices?.[0]?.message;
    const reply = message?.content || message?.reasoning_content || message?.reasoning;
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
    // 204 No Content responses MUST NOT have a response body in Fetch API
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: CORS_HEADERS,
      });
    }

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
        model: 'nvidia/nemotron-3.5-bolt-e4b',
        messages: [
          { role: 'system', content: String(body.system_prompt || '').slice(0, 12000) },
          {
            role: 'user',
            content: `Recalled memories:\n${String(body.memories_context || '').slice(0, 12000)}\n\nUser message:\n${userMessage}`,
          },
        ],
        temperature: 0.1,
        max_tokens: 512,
      };
    }

    const payload = providerPayload(body);
    if (!payload) return json({ error: 'messages must be a non-empty list' }, 400);
    const response = await callProvider(payload, env);

    if (url.pathname === '/api/extract-memory' && response.ok) {
      try {
        const result = await response.json();
        let cleaned = (result.reply || '').trim();
        if (cleaned.includes('```json')) {
          cleaned = cleaned.split('```json')[1].split('```')[0].trim();
        } else if (cleaned.includes('```')) {
          cleaned = cleaned.split('```')[1].split('```')[0].trim();
        }
        const start = cleaned.indexOf('{');
        const end = cleaned.lastIndexOf('}');
        if (start !== -1 && end !== -1) {
          cleaned = cleaned.slice(start, end + 1);
        }
        return json(JSON.parse(cleaned));
      } catch {
        return json({});
      }
    }
    return response;
  },
};
