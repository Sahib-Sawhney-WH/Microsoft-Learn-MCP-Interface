# LEARN:MCP

**A zero-LLM, multi-cloud documentation browser built on the Model Context Protocol.**

Search, read, and ask questions about Microsoft Learn and AWS documentation - all from a single HTML file. No AI models, no API keys, no backend, no build step. Just MCP over JSON-RPC 2.0 through a Cloudflare Worker CORS proxy.

```
Browser  -->  Cloudflare Worker  -->  Microsoft Learn MCP Server
  HTML         (CORS proxy)          learn.microsoft.com/api/mcp
  976 lines     /mslearn
                /aws             -->  AWS Knowledge MCP Server
                                      knowledge-mcp.global.api.aws
```

## What This Is

A 976-line single HTML file that acts as a full MCP client, talking directly to both Microsoft's Learn and AWS's Knowledge MCP servers. It includes:

- **Multi-Provider** - toggle between Microsoft Learn and AWS docs from the header
- **Doc Search** - query `microsoft_docs_search` or `aws___search_documentation`
- **Code Sample Search** - query `microsoft_code_sample_search` with syntax-highlighted previews
- **Full Doc Viewer** - fetch and render complete pages via `microsoft_docs_fetch` or `aws___read_documentation`
- **Extractive Q&A** - ask questions about any doc using BM25 section matching (no LLM)
- **Auto-Summarizer** - TF-IDF extractive summarization runs on every doc load (no LLM)
- **Tabs, TOC, Bookmarks, History** - full browsing experience with keyboard shortcuts
- **Command Palette** - `Ctrl+K` to search commands, history, bookmarks, and switch providers
- **Dark/Light Mode** - toggle with persisted preference
- **Session Auto-Reconnect** - detects 401/404/410 and re-initializes automatically
- **AWS Doc Pagination** - "Load more" for long AWS docs using `start_index`
- **AWS SOP Detection** - recognizes Standard Operating Procedure results with special badges
- **Smart Link Routing** - PDFs, `go.microsoft.com/fwlink` redirects, and GitHub links open externally

All state (bookmarks, history, theme) persists via localStorage. Doc cache uses LRU eviction at 50 entries. Separate MCP sessions per provider.

## Why

MCP is a protocol. It doesn't need an LLM to work. This project proves it by building a fully functional multi-cloud documentation browser where the only "intelligence" is ~120 lines of TF-IDF and BM25 - algorithms from the 1970s.

## Quick Start

### 1. Deploy the CORS Proxy (Cloudflare Worker)

The MCP endpoints don't set CORS headers, so browsers can't call them directly. A tiny Cloudflare Worker fixes this. Free tier covers 100,000 requests/day - no credit card, no auto-charges, requests just stop if you exceed the limit.

```bash
mkdir mcp-proxy && cd mcp-proxy && mkdir src
```

Create `src/index.js`:

```javascript
const TARGETS = {
  "/mslearn": "https://learn.microsoft.com/api/mcp",
  "/aws": "https://knowledge-mcp.global.api.aws",
};

export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Accept, Mcp-Session-Id",
        },
      });
    }

    const target = TARGETS[url.pathname];
    if (!target) {
      return new Response(JSON.stringify({ error: "Use /mslearn or /aws" }), {
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

    const res = await fetch(target, { method: "POST", headers, body: request.body });
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
  "devDependencies": { "wrangler": "^3.0.0" }
}
```

Deploy:

```bash
npm install
npx wrangler login
npx wrangler deploy
```

You'll get a URL like `https://mcp-proxy.YOUR_SUBDOMAIN.workers.dev`.

### 2. Configure the Client

Open `ms-learn-mcp-client.html` and replace the placeholder:

```
Find:    YOUR_WORKER_URL_HERE
Replace: https://mcp-proxy.YOUR_SUBDOMAIN.workers.dev
```

### 3. Open and Go

Open the HTML file in any browser. Click **INIT**. Switch between MS Learn and AWS using the header toggle.

## Keyboard Shortcuts

| Key | Action |
|---|---|
| `/` | Focus search |
| `Enter` | Search / open result |
| `Arrow Up/Down` | Navigate results |
| `Escape` | Go back |
| `Ctrl+K` / `Cmd+K` | Command palette |
| `Ctrl+J` / `Cmd+J` | Toggle ASK panel |

## How the NLP Works

No neural networks. No embeddings. No API calls. Just classical information retrieval.

**Summarizer** - TF-IDF scoring with section-aware diversity. Picks the best sentence from each section for coverage, re-sorts by original position for coherent reading.

**Q&A** - BM25 section matching with 5x heading bonus per query token match, 1.3x code bonus for "how do I" questions. Returns best section with keyword highlighting and inline code.

**MS Learn-specific** - strips boilerplate, merges language tab headers into parent sections, filters noise sections.

**Cloud-aware tokenizer** - keeps short terms: `az`, `acr`, `aks`, `cli`, `mcp`, `sdk`, `vpc`, `ec2`, `iam`, `api`, etc.

## MCP Tools Used

### Microsoft Learn
- `microsoft_docs_search` - search documentation
- `microsoft_docs_fetch` - fetch full doc pages
- `microsoft_code_sample_search` - find code snippets

### AWS Knowledge
- `aws___search_documentation` - search docs, blogs, whitepapers
- `aws___read_documentation` - fetch pages with `start_index` pagination
- `aws___list_regions` - list AWS regions
- `aws___recommend` - related content recommendations
- `aws___retrieve_agent_sop` - Standard Operating Procedures

## The Cost

| Component | Cost | Limit |
|---|---|---|
| Cloudflare Worker | $0 | 100,000 requests/day |
| MS Learn MCP | $0 | Public endpoint |
| AWS Knowledge MCP | $0 | Public endpoint |
| LLM API calls | $0 | There are none |

Exceed 100k/day and Cloudflare just stops serving. No surprise charges. No credit card needed.

## Adding More MCP Servers

1. Add a route in the Worker: `"/newprovider": "https://server.example.com/mcp"`
2. Add a provider config in the HTML's `PROVIDERS` object
3. Add a toggle button in the header
4. Handle response format differences in `doSearch` and `openDoc`

## License

Do whatever you want with it.
