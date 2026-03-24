// Multi-MCP CORS Proxy
// Routes: /mslearn -> learn.microsoft.com/api/mcp
//         /aws     -> knowledge-mcp.global.api.aws
const TARGETS = {
  "/mslearn": "https://learn.microsoft.com/api/mcp",
  "/aws": "https://knowledge-mcp.global.api.aws",
};

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    // CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Accept, Mcp-Session-Id",
        },
      });
    }

    // Find target
    const target = TARGETS[path];
    if (!target) {
      return new Response(JSON.stringify({ error: "Unknown path. Use /mslearn or /aws" }), {
        status: 404,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }

    const headers = {
      "Content-Type": "application/json",
      "Accept": "application/json, text/event-stream",
    };

    const sessionId = request.headers.get("Mcp-Session-Id");
    if (sessionId) headers["Mcp-Session-Id"] = sessionId;

    const res = await fetch(target, {
      method: "POST",
      headers,
      body: request.body,
    });

    const response = new Response(res.body, res);
    response.headers.set("Access-Control-Allow-Origin", "*");
    response.headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    response.headers.set("Access-Control-Allow-Headers", "Content-Type, Accept, Mcp-Session-Id");
    response.headers.set("Access-Control-Expose-Headers", "Mcp-Session-Id");
    return response;
  },
};
