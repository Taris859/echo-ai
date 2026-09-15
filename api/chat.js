export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const chatKey = process.env.NVIDIA_CHAT_KEY || "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";
  const body = req.body || {};

  try {
    const response = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${chatKey}`,
        "Content-Type": "application/json",
      },
      body: typeof body === 'string' ? body : JSON.stringify(body),
    });

    const data = await response.json();
    return res.status(response.status).json(data);
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
}
