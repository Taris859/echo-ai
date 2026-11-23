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
    let model = body.model || "nvidia/nemotron-3.5-bolt-e4b";
    if (model.includes("llama-3.2") || model.includes("llama-3.1")) {
      model = "nvidia/nemotron-3.5-bolt-e4b";
    }
    
    // Extract last user message to perform a quick background search
    let lastUserMessage = "";
    if (body.messages && body.messages.length > 0) {
      const lastMsg = body.messages[body.messages.length - 1];
      if (lastMsg.role === "user") {
         lastUserMessage = typeof lastMsg.content === "string" ? lastMsg.content : (lastMsg.content[0]?.text || "");
      }
    }

    let searchContext = "";
    if (lastUserMessage.length > 2 && lastUserMessage.length < 100) {
      try {
        const searchRes = await fetch("https://html.duckduckgo.com/html/", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: "q=" + encodeURIComponent(lastUserMessage)
        });
        const html = await searchRes.text();
        const snippets = [];
        const regex = /<a class="result__snippet[^>]*>([\s\S]*?)<\/a>/g;
        let match;
        while ((match = regex.exec(html)) !== null && snippets.length < 2) {
          snippets.push(match[1].replace(/<[^>]+>/g, "").trim());
        }
        if (snippets.length > 0) {
          searchContext = "\n\n[System note: Web search results for context (use this to understand typos or real-world facts, but keep your Gen-Z persona): " + snippets.join(" | ") + "]";
          
          // Append to the last message
          if (typeof body.messages[body.messages.length - 1].content === "string") {
            body.messages[body.messages.length - 1].content += searchContext;
          } else {
            body.messages[body.messages.length - 1].content[0].text += searchContext;
          }
        }
      } catch (err) {
        console.log("Search failed", err);
      }
    }

    const payload = {
      model: model,
      messages: body.messages,
      temperature: body.temperature || 0.7,
      max_tokens: body.max_tokens || 2048,
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
    const msg = data?.choices?.[0]?.message;
    const reply = msg?.content || msg?.reasoning_content || msg?.reasoning || "";
    
    return {
      statusCode: 200,
      headers: { 
        "Access-Control-Allow-Origin": "*",
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ reply: reply }),
    };
  } catch (error) {
    return {
      statusCode: 500,
      headers: { "Access-Control-Allow-Origin": "*" },
      body: JSON.stringify({ error: error.message }),
    };
  }
};
