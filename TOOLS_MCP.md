# Tools & MCP — iOS Implementation Brief

Add a **Tools** tab (or section within the existing Commands/Admin area) that shows native built-in tools and MCP server tools. View-only for now.

---

## Three New Stats Server Commands

All called via `POST https://api.appwebdev.co.uk/stats/exec` with the standard bearer token and `{"command": "<name>"}` body. Same pattern as `models-status`, `agents-list`, etc.

---

### 1. `tools-list` — Native tools + config

**Request:**
```json
POST /stats/exec
{ "command": "tools-list" }
```

**Response shape** (parse `stdout` as JSON):
```json
{
  "profile": "full",
  "allow": [],
  "deny": [],
  "mcp_servers": ["brightdata", "replicate"],
  "native": [
    { "name": "exec",        "group": "runtime",   "description": "Run shell commands" },
    { "name": "process",     "group": "runtime",   "description": "Manage background processes" },
    { "name": "read",        "group": "fs",        "description": "Read file contents" },
    { "name": "write",       "group": "fs",        "description": "Write file contents" },
    { "name": "edit",        "group": "fs",        "description": "Edit files with precise replacements" },
    { "name": "web_search",  "group": "web",       "description": "Search the web" },
    { "name": "web_fetch",   "group": "web",       "description": "Fetch and extract content from a URL" },
    { "name": "browser",     "group": "ui",        "description": "Control a Chromium browser" },
    { "name": "canvas",      "group": "ui",        "description": "Drive node Canvas" },
    { "name": "message",     "group": "messaging", "description": "Send messages across channels" },
    { "name": "cron",        "group": "automation","description": "Manage scheduled jobs" },
    { "name": "gateway",     "group": "automation","description": "Restart and configure gateway" },
    { "name": "nodes",       "group": "nodes",     "description": "Discover and control paired devices" },
    { "name": "image",       "group": "media",     "description": "Analyze images with vision model" },
    { "name": "tts",         "group": "media",     "description": "Convert text to speech" },
    { "name": "pdf",         "group": "media",     "description": "Analyze PDF documents" },
    { "name": "sessions_list",    "group": "sessions", "description": "List sessions" },
    { "name": "sessions_history", "group": "sessions", "description": "Fetch session history" },
    { "name": "sessions_send",    "group": "sessions", "description": "Send message to session" },
    { "name": "sessions_spawn",   "group": "sessions", "description": "Spawn sub-agent" },
    { "name": "sessions_yield",   "group": "sessions", "description": "End current turn" },
    { "name": "session_status",   "group": "sessions", "description": "Show session status" },
    { "name": "subagents",        "group": "sessions", "description": "List/steer/kill sub-agents" },
    { "name": "agents_list",      "group": "sessions", "description": "List available agent IDs" },
    { "name": "memory_search",    "group": "memory",   "description": "Semantic search memory files" },
    { "name": "memory_get",       "group": "memory",   "description": "Read snippet from memory file" },
    { "name": "search_engine",       "group": "web", "description": "Scrape Google/Bing/Yandex results" },
    { "name": "search_engine_batch", "group": "web", "description": "Run multiple search queries" },
    { "name": "scrape_as_markdown",  "group": "web", "description": "Scrape a webpage to markdown" },
    { "name": "scrape_batch",        "group": "web", "description": "Scrape multiple webpages" }
  ]
}
```

**Notes:**
- `profile`: `"full"` | `"coding"` | `"messaging"` | `"minimal"` — the base tool set
- `allow` / `deny`: overrides on top of the profile (usually empty arrays)
- `mcp_servers`: names of configured MCP servers (cross-reference with `mcp-list` / `mcp-tools`)
- `native` is a fixed 30-tool list — always complete regardless of profile

---

### 2. `mcp-list` — MCP server config

**Request:**
```json
POST /stats/exec
{ "command": "mcp-list" }
```

**Response shape** (parse `stdout` as JSON):
```json
{
  "brightdata": {
    "command": "npx",
    "args": ["-y", "@brightdata/mcp"],
    "env": { "API_TOKEN": "..." }
  },
  "replicate": {
    "command": "npx",
    "args": ["-y", "replicate-mcp"],
    "env": { "REPLICATE_API_TOKEN": "..." }
  }
}
```

**Notes:**
- Keys are server names. `command` + `args` show what binary runs it.
- `env` may contain API keys — **do not display env values** in UI, just show key names if needed.
- Use this to show server name + runtime (e.g. "npx @brightdata/mcp").

---

### 3. `mcp-tools` — Tools exposed by each MCP server

This is the slow one (~5–30s) — spawns each MCP server process briefly to query its tool list via JSON-RPC. **Load lazily** on tap/expand, not on screen appear.

**Request:**
```json
POST /stats/exec
{ "command": "mcp-tools" }
```

**Response shape** (parse `stdout` as JSON):
```json
{
  "servers": {
    "brightdata": {
      "status": "ok",
      "tool_count": 4,
      "tools": [
        { "name": "search_engine",       "description": "Scrape search results from Google, Bing or Yandex..." },
        { "name": "scrape_as_markdown",  "description": "Scrape a single webpage URL..." },
        { "name": "search_engine_batch", "description": "Run multiple search queries simultaneously..." },
        { "name": "scrape_batch",        "description": "Scrape multiple webpages URLs..." }
      ]
    },
    "replicate": {
      "status": "ok",
      "tool_count": 35,
      "tools": [
        { "name": "list_collections", "description": "..." },
        { "name": "get_collections",  "description": "..." },
        ...
      ]
    }
  }
}
```

**Status values:** `"ok"` | `"timeout"` | `"error"`
- `"timeout"`: server took >20s to respond — show "timed out" badge
- `"error"`: show error badge, `error` field contains message

---

## Suggested UI Structure

```
Admin / Commands
  └── Tools & MCP  ← new section (same level as Models & Config, Channels)
        ├── Native Tools
        │     ├── Profile: full  (badge)
        │     ├── Active overrides: none  (or list allow/deny)
        │     └── Tool grid grouped by category:
        │           runtime · fs · web · ui · messaging · automation · nodes · media · sessions · memory
        └── MCP Servers
              ├── brightdata  [npx]  [4 tools]  ▶ expand
              │     search_engine · scrape_as_markdown · search_engine_batch · scrape_batch
              └── replicate   [npx]  [35 tools] ▶ expand
                    list_collections · get_collections · ...
```

**Load strategy:**
- `tools-list` → load on section appear (fast, <1s)
- `mcp-list` → load on section appear alongside tools-list (fast)
- `mcp-tools` → load **only on server row tap/expand** (slow, lazy)

---

## Group → SF Symbol suggestions

| Group | Symbol |
|-------|--------|
| runtime | `terminal` |
| fs | `doc.text` |
| web | `globe` |
| ui | `macwindow` |
| messaging | `message` |
| automation | `clock.arrow.circlepath` |
| nodes | `iphone.radiowaves.left.and.right` |
| media | `photo` |
| sessions | `person.2` |
| memory | `brain` |

---

## Profile colour coding

| Profile | Colour |
|---------|--------|
| full | green |
| coding | blue |
| messaging | purple |
| minimal | orange |

---

## Timing notes
- `tools-list`: ~500ms
- `mcp-list`: ~9s (openclaw CLI startup)
- `mcp-tools`: ~10–30s (spawns MCP processes) — always lazy load

Consider showing a spinner with "Querying MCP servers..." for the mcp-tools call.
