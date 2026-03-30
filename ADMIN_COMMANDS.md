# Admin Commands — New Stats Exec Endpoints

Three new commands have been added to `POST /stats/exec`. All return the standard exec response shape:

```json
{
  "command": "models-status",
  "exit_code": 0,
  "stdout": "<json string>",
  "stderr": "",
  "duration_ms": 123
}
```

Parse `stdout` as JSON for all three. On `exit_code != 0`, show `stderr` as the error.

---

## 1. `models-status` — Active Model Config

**Priority: Should Have**

```swift
POST /stats/exec
{ "command": "models-status" }
```

**stdout JSON shape:**
```json
{
  "configPath": "/home/node/.openclaw/openclaw.json",
  "defaultModel": "anthropic/claude-sonnet-4-6",
  "resolvedDefault": "anthropic/claude-sonnet-4-6",
  "fallbacks": ["github-copilot/claude-sonnet-4.6"],
  "imageModel": null,
  "imageFallbacks": [],
  "aliases": {
    "Claude Haiku 4.5": "github-copilot/claude-haiku-4.5",
    "GPT-5 mini": "github-copilot/gpt-5-mini"
    // ...more aliases
  }
}
```

**Suggested UI:** A small card or settings row showing:
- **Default model** (e.g. `claude-sonnet-4-6`) — main badge
- **Fallbacks** — secondary line (e.g. "Fallback: claude-sonnet-4.6")
- **Image model** — show "None" if null

No filter params — always returns full config. Cacheable for ~60s.

---

## 2. `agents-list` — All Configured Agents

**Priority: Should Have (future-proofs multi-agent)**

```swift
POST /stats/exec
{ "command": "agents-list" }
```

**stdout JSON shape (array):**
```json
[
  {
    "id": "orchestrator",
    "name": "Orchestrator",
    "identityName": "Claw",
    "identityEmoji": "🦞",
    "identitySource": "identity",
    "workspace": "/home/node/.openclaw/workspace/orchestrator",
    "agentDir": "/home/node/.openclaw/agents/orchestrator/agent",
    "model": "anthropic/claude-sonnet-4-6",
    "bindings": 0,
    "isDefault": true,
    "routes": ["default (no explicit rules)"]
  }
]
```

**Suggested UI:** A list/picker of agents. Currently always 1 entry (`orchestrator`). When multiple agents exist, show as a segmented control or dropdown so other tabs can filter by agent.

Key fields to surface:
- `identityEmoji + identityName` — display name with emoji
- `model` — current model badge
- `isDefault` — badge if multiple agents
- `routes` — show as small pills (optional)

No filter params.

---

## 3. `channels-list` — Channel Health + Auth + Usage

**Priority: Should Have**

```swift
POST /stats/exec
{ "command": "channels-list" }
```

**stdout JSON shape:**
```json
{
  "chat": {
    "telegram": ["default"],
    "whatsapp": ["default"]   // if connected
  },
  "auth": [
    {
      "id": "github-copilot:github",
      "provider": "github-copilot",
      "type": "token",
      "isExternal": false
    }
  ],
  "usage": {
    "updatedAt": 1774728054618,
    "providers": [
      {
        "provider": "github-copilot",
        "displayName": "Copilot",
        "windows": [
          { "label": "Premium", "usedPercent": 97.4 },
          { "label": "Chat",    "usedPercent": 0 }
        ],
        "plan": "individual_pro"
      }
    ]
  }
}
```

**Suggested UI — two sections:**

**Connected Channels** (from `chat` dict):
- One row per channel key (`telegram`, `whatsapp`, etc.) with account count
- Green dot if present in `chat`, grey dot if not
- Currently active: Telegram. WhatsApp shown as disconnected when not in `chat`.

**Provider Usage** (from `usage.providers[]`):
- One card per provider with a `usedPercent` bar per window
- `windows[].label` + `windows[].usedPercent` → thin progress bar (0–100)
- 97% Premium usage = show warning colour (orange)
- `plan` shown as a small badge

No filter params. Cacheable for ~120s (usage data updates slowly).

---

## Filter UI Notes

All three commands are read-only and take no args. But you could add a nice **Admin panel** or extra section in the More tab (or Settings) with:

- **Models card** — default model + fallbacks + aliases list
- **Agents card** — agent picker (useful later)
- **Channels card** — channel health + provider quota bars

A `FilterChip` row across the top (`Models` / `Agents` / `Channels`) would let you jump between them. Each section pulls from its own command on appear and caches locally.

---

## Existing Commands (for reference)

| Command | Args | What it returns |
|---|---|---|
| `doctor` | — | Health checks (ANSI text — strip escape codes before display) |
| `status` | — | Gateway + session status (ANSI text) |
| `logs` | — | Last 50 log lines (plain text) |
| `security-audit` | — | Security audit report (text) |
| `backup` | — | Creates backup, returns path |
| `channels-status` | — | Channel probe results (human text, not JSON) |
| `config-validate` | — | Schema validation result |
| `memory-reindex` | — | Reindex memory files |
| `restart-stats` | — | Force-kills and restarts the stats server |
| `memory-list` | — | `.md` filenames + daily log paths |
| `skills-list` | — | Skill folder names (one per line) |
| `skill-files` | `args: "skill-name"` | Recursive file list inside a skill folder |
| `skill-read` | `args: "skill-name path/to/file"` | Full file contents |

For `skill-files` and `skill-read`, pass args in the `args` field:
```swift
{ "command": "skill-files", "args": "skill-reddit" }
{ "command": "skill-read",  "args": "skill-reddit scripts/reddit_engage.py" }
```
