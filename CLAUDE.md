# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

- Never build automatically — user runs manually via Xcode.
- **Project**: `OpenClaw.xcodeproj` (no workspace)
- **Dependencies**: MarkdownUI via SPM (`https://github.com/gonzalezreal/swift-markdown-ui`)
- **Bundle ID**: `co.uk.appwebdev.OpenClaw`
- **Deployment**: iOS 17+, Swift 6 patterns (`@Observable`, strict `Sendable`)

## Architecture

Clean Architecture with MVVM per feature, protocol-based DI, and a generic ViewModel base.

### Layer flow

```
View → LoadableViewModel<T> → Repository protocol → GatewayClientProtocol → URLSession
                                      ↓
                                 MemoryCache (actor, TTL)
```

### Key abstractions

- **`LoadableViewModel<T>`** (`Core/LoadableViewModel.swift`): `@Observable @MainActor` base. Handles `data`, `isLoading`, `error`, `isStale`, `start()`, `refresh()`, `cancel()`. Feature VMs are one-liner subclasses.

- **`GatewayClientProtocol`** (`Core/GatewayClient.swift`): Four methods: `stats()` (GET, `.convertFromSnakeCase`), `statsPost()` (POST to `/stats/*`, `.convertFromSnakeCase`), `invoke()` (POST to `/tools/invoke`, camelCase — no conversion), `chatCompletion()` (POST to `/v1/chat/completions` with session key header).

- **Repository protocols** (`Core/Repositories/`): One per feature. `Remote*Repository` owns a `MemoryCache<T>` actor and maps DTO→domain.

- **DTOs vs Domain models**: `Decodable` types in `Core/Networking/DTOs/` (suffixed `DTO`). Domain models in feature folders with `init(dto:)` mappers. Domain types use `Date`, `URL?` etc.

### Navigation

`ContentView` (auth gate) → `MainTabView` (5 tabs): Home, Crons, Pipelines (placeholder), Memory (placeholder), Chat (placeholder). Settings via Home toolbar gear.

Shared state: `CronSummaryViewModel` and `CronDetailRepository` created once in `MainTabView`, shared across tabs.

Depth: Crons tab → `CronDetailView` → tap run → `SessionTraceView`.

### Design system

All views use semantic tokens — never raw literals:
- `Spacing` — 4pt grid (xxs=4 through xxl=48)
- `AppColors` — `.success`, `.danger`, `.metricPrimary`, `.gauge(percent:warn:critical:)`
- `AppTypography` — `.heroNumber`, `.cardTitle`, `.actionIcon`, `.badgeIcon`, `.statusIcon`, `.nano`
- `AppRadius` — `.sm`(8), `.md`(10), `.lg`(12), `.card`(16)
- `Formatters` — cached `RelativeDateTimeFormatter` and `DateFormatter`

Sub-grid visual details (2pt padding, 6pt dots, 8pt indicator circles) are acceptable as raw values — they're too small for tokens.

### Shared components

- `CronStatusDot` / `CronStatusBadge` — reused across cron list, detail, and trace. Badge supports `.small` and `.large` styles.
- `TokenBreakdownBar` — proportional bar + legend (input/output/reasoning split).
- `CardContainer`, `CardLoadingView`, `CardErrorView` — dashboard card shells.
- `CommandButton` — reusable quick action button with icon, label, loading state.

## Conventions

- **New features**: DTO in `Core/Networking/DTOs/`, domain model in feature folder with `init(dto:)`, repository protocol + `Remote*` in `Core/Repositories/`, VM subclass of `LoadableViewModel<T>`, view using `CardContainer` for dashboard cards.
- **Concurrency**: `@MainActor` on all ViewModels. `@Sendable` closures for loaders. Actor-based `MemoryCache`. No `@unchecked Sendable`.
- **Logging**: `os.Logger` (subsystem: `co.uk.appwebdev.openclaw`), never `print()`.
- **Accessibility**: All custom visual components need `.accessibilityElement` + `.accessibilityLabel`.
- **Haptics**: `Haptics.shared` for user action feedback (refresh, save, errors).
- **UI**: Design tokens only. Skeleton shimmer via `.shimmer()`. `CardLoadingView`/`CardErrorView` for card states.
- **File size**: Keep files under 300 lines. Extract into separate files when growing.
- **Pagination**: Limit/offset with "Load More" button. Deduplicate on append by ID. See `CronDetailViewModel`.
- **Formatters**: Always use `Formatters.relativeString(for:)` / `Formatters.absoluteString(for:)`. Never instantiate inline.
- **Markdown**: `Markdown(text).markdownTheme(.openClaw)` for LLM content. Never `AttributedString(markdown:)`. MarkdownUI v2 has no `.table` theme API.
- **Terminal output**: Strip ANSI codes with `CommandsViewModel.stripAnsi()`. Display in monospace (`AppTypography.captionMono`) with tinted background.
- **Confirmations**: Destructive actions (run cron, disable job, run command) must show an alert with confirmation before executing.
- **Prompt templates**: All agent prompts live in `Core/Prompts/PromptTemplates.swift` — one file, easy to tune. Use `ChatCompletionRequest`/`ChatCompletionResponse` for `/v1/chat/completions` calls.
- **Memory annotation pattern**: Files are read-only in the UI. Users add comments on paragraphs, then submit as a batch to the agent. Never write files directly — always agent-mediated.

## Prompt Engineering

All prompts sent to the agent follow these principles:

- **Never send full file content** — the agent has the file on disk. Send the path, line numbers, and a few lines of context (±2 lines around the target). The agent reads the file itself with the `read` tool. This saves tokens massively (14KB file → ~200 byte reference).
- **Tell the agent what tools to use** — explicitly say "use the read tool", "use the write tool". Agents in fresh sessions may not know what's available unless told.
- **Give the workspace root path** — `~/.openclaw/workspace/orchestrator/`. The agent needs to know where files live. Relative paths work for `read`/`write` but being explicit avoids ambiguity.
- **Session key matters** — `/v1/chat/completions` without `x-openclaw-session-key` header starts a blank isolated session with NO workspace access. Must use `chatCompletion()` method with `sessionKey: "agent:orchestrator:main"` for the agent to have `read`/`write`/`edit` tools.
- **Structure: task → steps → rules** — system prompt says what the task is, numbered steps to follow, then rules/constraints. User message has only the data (file path, line references, change requests).
- **Context padding** — include 2 lines before and after the target section in a code block so the agent can locate the exact position even if line numbers shift slightly.

## Gateway API Gotchas

- **Three client methods**: `stats()` for GET (snake_case decoder), `statsPost()` for POST to `/stats/*` (snake_case decoder), `invoke()` for POST to `/tools/invoke` (camelCase, no conversion). DTOs for `stats`/`statsPost` don't need `CodingKeys`; DTOs for `invoke` only need `CodingKeys` for nested snake_case fields.
- **URL construction**: `stats()` and `statsPost()` build URLs via string interpolation, not `.appending(path:)` — the latter percent-encodes `?` breaking query strings.
- **Shell commands**: The `exec` tool is NOT available via `/tools/invoke` (requires agent sandbox). Use `POST /stats/exec` instead with an allowlisted command key (e.g. `{"command": "doctor"}`). The server maps keys to actual commands.
- **Cron list**: Pass `includeDisabled: true` to get all jobs including disabled ones.
- **Cron schedules**: `kind: "cron"` has `expr`, `kind: "every"` has `everyMs` (no `expr`). DTO `expr` must be optional.
- **Session history**: Tool is `sessions_history` (not `sessions`). Takes `sessionKey` (full format), not `sessionId` (bare UUID). Domain model stores both, trace view tries `sessionKey` first.
- **Error responses**: Gateway in-envelope errors (200 OK with `{"status":"error"}`) surface as decode failures. Handle gracefully in VMs.
- **System health polling**: `SystemHealthViewModel` has its own polling loop (15s) — starts on `onAppear`, stops on `onDisappear`. Not a `LoadableViewModel` subclass.
- **Memory tools**: `memory_get` and `memory_search` require `sessionKey: "agent:orchestrator:main"` in the request body. Without it, the tool returns `disabled: true`. Config must have `memorySearch.extraPaths` pointing to workspace root for non-memory files (SOUL.md, AGENTS.md, etc.).
- **Chat completions**: Use `chatCompletion()` method (not `statsPost`) — it adds the `x-openclaw-session-key` header. Without this header, the agent starts a blank session with no tools or workspace. Four client methods total: `stats()`, `statsPost()`, `invoke()`, `chatCompletion()`.
