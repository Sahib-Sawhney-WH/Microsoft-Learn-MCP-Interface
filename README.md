# LEARN:MCP

**A zero-LLM Microsoft Learn documentation browser built entirely on the Model Context Protocol.**

Search, read, and ask questions about Microsoft Learn docs - all from a single HTML file. No AI models, no API keys, no backend, no build step. Just MCP over JSON-RPC 2.0 through a Cloudflare Worker CORS proxy.

```
Browser  -->  Cloudflare Worker  -->  Microsoft Learn MCP Server
  HTML          (CORS proxy)           learn.microsoft.com/api/mcp
```

## What This Is

A 772-line single HTML file that acts as a full MCP client, talking directly to Microsoft's Learn documentation MCP server. It includes:

- **Doc Search** - query `microsoft_docs_search` and browse results
- **Code Sample Search** - query `microsoft_code_sample_search` with syntax-highlighted previews
- **Full Doc Viewer** - fetch and render complete documentation pages via `microsoft_docs_fetch`
- **Extractive Q&A** - ask questions about any doc using BM25 section matching (no LLM)
- **Auto-Summarizer** - TF-IDF extractive summarization runs on every doc load (no LLM)
- **Tabs, TOC, Bookmarks, History** - full browsing experience with keyboard shortcuts
- **Command Palette** - `Ctrl+K` to search commands, history, and bookmarks
- **Dark/Light Mode** - toggle with persisted preference
- **Session Auto-Reconnect** - detects 401/404/410 and re-initializes automatically

All state (bookmarks, history, theme) persists via localStorage. Doc cache uses LRU eviction at 50 entries.

## Why

MCP is a protocol. It doesn't need an LLM to work. This project proves it by building a fully functional documentation browser where the only "intelligence" is ~80 lines of TF-IDF and BM25 - algorithms from the 1970s.

## Quick Start

### 1. Deploy the CORS Proxy (Cloudflare Worker)

The Microsoft Learn MCP endpoint doesn't set CORS headers, so browsers can't call it directly. A tiny Cloudflare Worker fixes this. Free tier covers 100,000 requests/day.

```bash
# Create the project
mkdir mcp-proxy && cd mcp-proxy
mkdir src
```

Create `src/index.js`:

```javascript
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
```

Create `wrangler.toml`:

```toml
name = "mcp-proxy"
main = "src/index.js"
compatibility_date = "2024-01-01"
```

Create `package.json`:

```json
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
```

Deploy:

```bash
npm install
npx wrangler login
npx wrangler deploy
```

You'll get a URL like `https://mcp-proxy.YOUR_SUBDOMAIN.workers.dev`. That's your proxy.

### 2. Configure the Client

Open `ms-learn-mcp-client.html` and replace the placeholder:

```
Find:    YOUR_WORKER_URL_HERE
Replace: https://mcp-proxy.YOUR_SUBDOMAIN.workers.dev
```

There are two occurrences - the `PROXY` constant in the JS and the sidebar footer display text.

### 3. Open and Go

Open `ms-learn-mcp-client.html` in any browser. Click **INIT** to handshake with the MCP server. Once the status dot goes green, you're live.

Or use the automated setup script:

```bash
chmod +x setup-learn-mcp.sh
./setup-learn-mcp.sh
```

The script handles everything: project creation, Cloudflare login, deploy, and auto-patches the HTML with your worker URL.

## Keyboard Shortcuts

| Key | Action |
|---|---|
| `/` | Focus search input |
| `Enter` | Search / open focused result |
| `Arrow Up/Down` | Navigate search results |
| `Escape` | Go back to results |
| `Ctrl+K` / `Cmd+K` | Open command palette |
| `Ctrl+J` / `Cmd+J` | Toggle ASK panel |

## How the NLP Works

No neural networks. No embeddings. No API calls. Just classical information retrieval.

**Summarizer (TF-IDF, section-aware)**

1. Parse the doc into sections by headings
2. Extract clean sentences (strip markdown, images, boilerplate, tab selectors)
3. Score each sentence: term frequency * inverse document frequency
4. Boost first sentence of each section (position prior)
5. Diversify: pick top sentence from each section before filling globally
6. Re-sort by original position for coherent reading order

**Q&A (BM25 + heading match)**

1. Parse doc into sections, preserving code blocks
2. Tokenize the question (Azure-aware: keeps short terms like `az`, `acr`, `aks`, `cli`)
3. Score each section using BM25 (same algorithm as Elasticsearch)
4. Apply heading bonus: 5x multiplier per query token found in section heading
5. Apply code bonus: 1.3x for "how do I" questions when section has code
6. Return best section with keyword highlighting and inline code preview

**Boilerplate filtering**

MS Learn docs contain recurring patterns that pollute results: "Having issues? Let us know on GitHub", "Was this page helpful?", tab selectors like `* [Bash](#tabpanel...)`, and sections like "Feedback" and "Additional Resources". These are stripped before any NLP processing.

**Tab header merging**

`### **Bash**` and `### **PowerShell**` headings in MS Learn docs are language tab selectors, not real sections. They're merged into their parent section so "Deploy your image" stays as one coherent section instead of fragmenting into six tiny pieces.

## Architecture

```
ms-learn-mcp-client.html     Single-file browser client (772 lines)
  |
  |-- MCP Client              JSON-RPC 2.0 over Streamable HTTP
  |-- NLP Engine              TF-IDF summarizer + BM25 Q&A (~120 lines)
  |-- Markdown Renderer       Tables, code blocks, images, lists, blockquotes
  |-- Tab Manager             Multi-doc browsing with cached content
  |-- Command Palette         Fuzzy search across commands, history, bookmarks
  |-- Chat Panel              Extractive Q&A with follow-up chips
  |
  v
Cloudflare Worker             CORS proxy (30 lines)
  |
  v
learn.microsoft.com/api/mcp   Microsoft Learn MCP Server
  |-- microsoft_docs_search
  |-- microsoft_docs_fetch
  |-- microsoft_code_sample_search
```

## MCP Protocol Flow

```
1. POST initialize         { protocolVersion, capabilities, clientInfo }
2. POST notifications/initialized    (no response expected)
3. POST tools/list         -> returns available tools
4. POST tools/call         { name: "microsoft_docs_search", arguments: { query } }
5. Parse SSE or JSON response, extract result.content[0].text
```

Session is maintained via `Mcp-Session-Id` header. If the session dies (401/404/410), the client auto-reconnects and retries.

## What it Doesn't Do

- No authentication required
- No data leaves your browser (except MCP queries to Microsoft via the proxy)
- No telemetry, analytics, or tracking
- No LLM calls anywhere in the stack
- No build step, no dependencies, no node_modules

## Adapting for Other MCP Servers

The proxy and client pattern works with any MCP server that supports Streamable HTTP transport. To point at a different server:

1. Change the target URL in the Cloudflare Worker (`learn.microsoft.com/api/mcp` to your server)
2. Update the tool names in the client JS (`microsoft_docs_search` etc.)
3. Adjust the response parsing if the server returns different field names

## Tech Stack

- **Client**: Vanilla HTML/CSS/JS, IBM Plex Sans + JetBrains Mono
- **Proxy**: Cloudflare Workers (free tier)
- **Protocol**: MCP (Model Context Protocol) over JSON-RPC 2.0
- **NLP**: TF-IDF, BM25 (in-browser, ~120 lines)
- **Storage**: localStorage for persistence, in-memory LRU cache for docs
- **Cost**: $0/month

## License

Do whatever you want with it.
