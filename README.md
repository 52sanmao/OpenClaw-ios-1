# OpenClaw

A native iOS control room for the OpenClaw AI gateway. Monitor system health, run commands, manage cron jobs, inspect agent execution traces, track token usage, browse agent memory and skills, chat with your agent — all from your phone.

Built with SwiftUI, Swift Concurrency, and Charts. 128 files, ~10,000 lines. One external dependency: [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) for rendering LLM markdown output.

## Screens

| Tab | Description |
|-----|-------------|
| **Home** | Dashboard with 6 cards: System Health, Commands, Cron Jobs, Token Usage, Outreach Stats, Blog Pipeline. OpenClaw icon (left) → streaming chat. Wrench icon → Tools & MCP. Gear icon → Settings. Status subtitle: "All systems OK" / "N cron failures". |
| **Crons** | Segmented: **Cron Jobs** / **History**. Subtitle: "12 jobs · 2 failed". Calendar icon → 24-hour schedule timeline. Tap job → detail (about, stats, run history). Tap run → execution trace with step comments. |
| **Mem & Skills** | Segmented: **Memory** / **Skills**. Subtitle: "8 files · 10 skills". Wand icon → maintenance actions (Full Cleanup, Today Cleanup). Comment system: paragraph, page, and skill levels. |
| **Sessions** | Segmented: **Chat History** / **Subagents**. Subtitle: "Running · 149k". Main session hero card with context ring gauge. Step-level trace comments. |
| **More** | Placeholder for future features |

### Home Dashboard Cards

- **System Health** — CPU, RAM, Disk ring gauges with auto-polling every 15s. Uptime + load average. Manual refresh button.
- **Commands** — 6 quick action buttons. Each confirms before running, shows result with copy + "Investigate with AI". Tap "View Details" → full grid of all 12 commands + admin panels (Models & Config, Channels & Provider Usage). Wrench icon → Tools & MCP.
- **Cron Summary** — Last run status + next upcoming run.
- **Token Usage** — Period picker (Today/Yesterday/7 Days). Total tokens, cost, breakdown bar, model breakdown. Tap "View Details" → deep-dive analytics with charts and pipeline attribution.
- **Outreach Stats** — 6-cell grid with leads, channels, conversions.
- **Blog Pipeline** — Published count, active pipeline stage pills.

### Cron Detail View

- **About** — purpose (from job payload), configured model with provider icon, frequency, cron expression, timezone, last/next run, consecutive errors
- **Error** — error message + "Investigate with AI" button + previous investigation link
- **Run Stats** — avg duration, avg tokens, total tokens, success rate bar (computed from loaded runs)
- **Run History** — paginated with total count. Each entry: status, time, duration, model, tokens, breakdown bar. Tap row → trace with step comments.
- **Toolbar** — title with status badge subtitle, pause/play toggle, run button

### Schedule Timeline

24-hour timeline showing when all cron jobs run today. Job legend with color dots. Current hour highlighted. Client-side cron expression parsing.

### Token Detail Page

Summary grid, donut chart (token split), cache hit rate gauge, cost-by-model bar chart, expanded per-model cards with breakdown bars, per-pipeline token attribution.

### Agent Execution Trace

Step-by-step trace with metadata pills (model with provider icon, stop reason, tokens). Step types: System Prompt, Input Prompt, Thinking, Tool calls, Tool results, Text responses. Step comments: expand → "Add Comment" → inline orange cards with delete → batch submit. Agent investigates with session type context (main/cron/subagent).

### Commands & Admin Detail

Full 12-command grid. Models & Config (default model with provider icon, fallbacks, agent info, aliases). Channels (status dots, provider usage bars). Tools & MCP (nav bar icon).

### Tools & MCP

Accessible from Home and Commands detail via wrench icon. Native tools grouped by category (runtime, fs, web, ui, messaging, automation, nodes, media, sessions, memory) with profile badge and allow/deny overrides. MCP servers with runtime info — tap or nav bar server.rack icon → dedicated MCP detail page with full tool descriptions. `mcp-tools` lazy-loaded on expand (slow call).

### Mem & Skills Tab

- **Memory** — file browser (Memory Files, Daily Logs, Reference). Paragraph-level comments + page-level comments.
- **Skills** — skill folder browser → file tree (documents + scripts/config). Skill-level comments (agent reads `create-skill` first). `skill-read` for all file types.
- **Maintenance actions** — wand icon: Full Cleanup (read docs → update today → clean all), Today Cleanup (read docs → update today only). Agent reads `/app/docs` memory best practices first.
- **Comment system** — 3 levels (paragraph, page, skill). Shared `CommentInputBar` + `CommentSheet`. Paragraph comments queue with swipe-to-delete. Page/skill comments submit immediately.

### Sessions Tab

- **Chat History** — main session hero card: context ring gauge, model, tokens, cost, subagents, status. Tap → trace (newest first).
- **Subagents** — sorted by most recent. Model, tokens, last updated. Tap → trace (chronological).

### Chat

Accessible from Home nav bar OpenClaw icon. SSE streaming chat with the agent. Session-bound (server manages history). Loads last 50 messages on open. Chat bubbles with markdown rendering. Assistant messages show timestamp + copy button. Auto-scroll during streaming. Stop button. Interactive keyboard dismiss. Reload button.

### Settings

Authentication (token status, replace/set). Gateway info (URL, agent, TLS). Connection test (live system stats request). About section.

## Getting Started

1. Open `OpenClaw.xcodeproj` in Xcode
2. Build and run on a simulator or device (iOS 17+)
3. On first launch, paste your gateway Bearer token
4. The Home dashboard loads automatically — pull down to refresh

## API

All requests go to `https://api.appwebdev.co.uk` with `Authorization: Bearer <token>`.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/stats/system` | CPU, RAM, disk, uptime, load |
| GET | `/stats/outreach` | Leads, emails, WhatsApp, conversions |
| GET | `/stats/blog` | Published count, pipeline stages |
| GET | `/stats/tokens?period=` | Token usage with full model breakdown |
| POST | `/stats/exec` | Run predefined safe commands (allowlisted) |
| POST | `/tools/invoke` | Gateway tool calls (see below) |
| POST | `/v1/chat/completions` | Chat streaming (SSE) + agent prompts |

### Tool Actions (via /tools/invoke)

| Tool | Action | Args | Purpose |
|------|--------|------|---------|
| `cron` | `list` | `includeDisabled: true` | List all cron jobs |
| `cron` | `runs` | `jobId`, `limit`, `offset` | Paginated run history |
| `cron` | `run` | `jobId` | Manual trigger |
| `cron` | `update` | `jobId`, `patch: {enabled}` | Toggle enabled/disabled |
| `gateway` | `restart` | — | Restart gateway process |
| `sessions_list` | — | `limit` | List all sessions (`{count, sessions}`) |
| `sessions_history` | — | `sessionKey`, `limit`, `includeTools` | Agent execution trace |
| `memory_get` | — | `path`, `sessionKey` | Read workspace file content |

### Stats Exec Commands (via /stats/exec)

Action commands: `doctor`, `status`, `logs`, `security-audit`, `backup`, `channels-status`, `config-validate`, `memory-reindex`, `session-cleanup`, `plugin-update`.

Workspace commands: `memory-list`, `skills-list`, `skill-files` (args: skill name), `skill-read` (args: "skillId relativePath").

Admin commands: `models-status`, `agents-list`, `channels-list`, `tools-list`, `mcp-list`, `mcp-tools`.

### Gateway Config Required

- `tools.sessions.visibility = "all"` — allows reading cron run session traces
- `tools.profile = "full"` — enables sessions_history, sessions_list, memory_get
- `memorySearch.extraPaths` — must include workspace root for accessing all `.md` files
- `gateway.http.endpoints.chatCompletions.enabled = true` — for chat, investigations, and agent-mediated edits

## Requirements

- iOS 17+
- Xcode 16+
- MarkdownUI via SPM

## License

Private — all rights reserved.
