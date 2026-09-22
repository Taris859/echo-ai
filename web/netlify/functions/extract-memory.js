exports.handler = async function (event, context) {
  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    };
  }

  const NVIDIA_API_KEY = "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";

  try {
    const body = JSON.parse(event.body);
    const userMessage = (body.user_message || "").trim();
    if (!userMessage) {
       return { statusCode: 400, body: JSON.stringify({ error: "invalid request" }) };
    }

    const payload = {
      model: "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
      messages: [
        { role: "system", content: (body.system_prompt || "").slice(0, 12000) },
        {
          role: "user",
          content: `Recalled memories:\n${(body.memories_context || "").slice(0, 12000)}\n\nUser message:\n${userMessage}`,
        },
      ],
      temperature: 0.1,
      max_tokens: 300,
    };

    const response = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${NVIDIA_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const data = await response.json();
    const replyStr = data?.choices?.[0]?.message?.content || "{}";
    const cleaned = replyStr.replace(/```json\s*|\s*```/g, "").trim();

    return {
      statusCode: 200,
      headers: { 
        "Access-Control-Allow-Origin": "*",
        "Content-Type": "application/json"
      },
      body: cleaned || "{}",
    };
  } catch (error) {
    return {
      statusCode: 500,
      headers: { "Access-Control-Allow-Origin": "*" },
      body: JSON.stringify({ error: error.message }),
    };
  }
};
