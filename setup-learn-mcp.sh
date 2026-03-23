#!/bin/bash
# ============================================
# LEARN:MCP - Zero-LLM Microsoft Learn Browser
# Quick setup script
# ============================================

set -e

echo ""
echo "  ⚡ LEARN:MCP Setup"
echo "  ===================="
echo "  Cloudflare Worker proxy + browser client"
echo ""

# --- Check prerequisites ---
if ! command -v npm &> /dev/null; then
  echo "  ✕ npm not found. Install Node.js first: https://nodejs.org"
  exit 1
fi
echo "  ✓ npm found"

# --- Create proxy project ---
echo ""
echo "  → Creating Cloudflare Worker proxy..."

mkdir -p mcp-proxy/src

cat > mcp-proxy/src/index.js << 'WORKER'
export default {
  async fetch(request) {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Accept, Mcp-Session-Id",
        },
      });
    }

    const headers = {
      "Content-Type": "application/json",
      "Accept": "application/json, text/event-stream",
    };

    const sessionId = request.headers.get("Mcp-Session-Id");
    if (sessionId) headers["Mcp-Session-Id"] = sessionId;

    const res = await fetch("https://learn.microsoft.com/api/mcp", {
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
WORKER

cat > mcp-proxy/wrangler.toml << 'TOML'
name = "mcp-proxy"
main = "src/index.js"
compatibility_date = "2024-01-01"
TOML

cat > mcp-proxy/package.json << 'PKG'
{
  "name": "mcp-proxy",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy"
  },
  "devDependencies": {
    "wrangler": "^3.0.0"
  }
}
PKG

echo "  ✓ Proxy project created in ./mcp-proxy"

# --- Install deps ---
echo ""
echo "  → Installing dependencies..."
cd mcp-proxy
npm install --silent 2>/dev/null
cd ..
echo "  ✓ Dependencies installed"

# --- Login and deploy ---
echo ""
echo "  → Logging in to Cloudflare..."
echo "    (A browser window will open)"
echo ""
cd mcp-proxy
npx wrangler login

echo ""
echo "  → Deploying worker..."
DEPLOY_OUTPUT=$(npx wrangler deploy 2>&1)
echo "$DEPLOY_OUTPUT"

# Extract the worker URL
WORKER_URL=$(echo "$DEPLOY_OUTPUT" | grep -oP 'https://[a-z0-9-]+\.[\w-]+\.workers\.dev' | head -1)

cd ..

if [ -z "$WORKER_URL" ]; then
  echo ""
  echo "  ⚠ Could not auto-detect worker URL."
  echo "    Check the output above and manually update the PROXY variable"
  echo "    in ms-learn-mcp-client.html"
  echo ""
  read -p "  Paste your worker URL: " WORKER_URL
fi

echo ""
echo "  ✓ Worker deployed: $WORKER_URL"

# --- Patch the HTML client ---
if [ -f "ms-learn-mcp-client.html" ]; then
  sed -i "s|https://mcp-proxy.sahibiscool.workers.dev|$WORKER_URL|g" ms-learn-mcp-client.html
  echo "  ✓ Updated proxy URL in ms-learn-mcp-client.html"
else
  echo "  ⚠ ms-learn-mcp-client.html not found in current directory."
  echo "    Place it here and run:"
  echo "    sed -i \"s|https://mcp-proxy.sahibiscool.workers.dev|$WORKER_URL|g\" ms-learn-mcp-client.html"
fi

# --- Done ---
echo ""
echo "  ============================================"
echo "  ✓ Setup complete!"
echo ""
echo "  Proxy:  $WORKER_URL"
echo "  Client: open ms-learn-mcp-client.html"
echo ""
echo "  Just open the HTML file in a browser,"
echo "  hit INIT, and start searching."
echo "  ============================================"
echo ""
