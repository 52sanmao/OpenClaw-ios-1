# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

- Never build automatically — user runs manually via Xcode.
- **Project**: `OpenClaw.xcodeproj` (no workspace)
- **Dependencies**: MarkdownUI via SPM (`https://github.com/gonzalezreal/swift-markdown-ui`), Charts (system framework)
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

- **`LoadableViewModel<T>`** (`Core/LoadableViewModel.swift`): `@Observable @MainActor` base. Handles `data`, `isLoading`, `error`, `isStale`, `start()`, `refresh()`, `cancel()`, `startPolling(interval:)`, `stopPolling()`. Feature VMs are one-liner subclasses.

- **`GatewayClientProtocol`** (`Core/GatewayClient.swift`): Five method groups: `stats()` (GET, `.convertFromSnakeCase`), `statsPost()` (POST to `/stats/*`, `.convertFromSnakeCase`), `invoke()` (POST to `/tools/invoke`, camelCase — no conversion), `chatCompletion()` / `streamChat()` (compatibility surface now mapped onto `/api/chat/thread/new`, `/api/chat/send`, `/api/chat/history`), plus thread helpers for history/thread operations.

- **Repository protocols** (`Core/Repositories/`): One per feature. `Remote*Repository` owns a `MemoryCache<T>` actor and maps DTO→domain.

- **DTOs vs Domain models**: `Decodable` types in `Core/Networking/DTOs/` (suffixed `DTO`). Domain models in feature folders with `init(dto:)` mappers. Domain types use `Date`, `URL?` etc.

### Navigation

`ContentView` (auth gate) → `MainTabView` (5 tabs): Home, Crons, Mem & Skills, Sessions, More (placeholder). Chat accessible via Home nav bar left icon. Settings via Home toolbar gear.

Shared state: `CronSummaryViewModel`, `CronDetailRepository`, `MemoryViewModel`, `SessionsViewModel`, `SessionRepository`, and `GatewayClient` created once in `MainTabView`, shared across tabs.

Depth:
- Home → OpenClaw icon (left nav) → `ChatView` (streaming SSE chat). Home → wrench icon → `ToolsConfigView`. Home → gear icon → `SettingsView`. Home → TokenUsageCard "View Details" → `TokenDetailView`.
- Commands & Admin → wrench icon → `ToolsConfigView` → server.rack icon → `McpServersView`.
- Crons tab: segmented **Cron Jobs** / **History**. Cron Jobs → `CronDetailView` → `SessionTraceView`. History → `SessionTraceView` directly.
- Mem & Skills tab: segmented **Memory** / **Skills**. Memory → `MemoryFileView`. Skills → `SkillDetailView` (file tree) → `MemoryFileView` (.md) or `ReadOnlyFileView` (scripts/config).
- Sessions tab: segmented **Chat History** / **Subagents**. Both → `SessionTraceView`. Chat history shows newest first.
- Crons tab: calendar icon (top right) → `ScheduleTimelineView` (24-hour timeline of today's scheduled runs).

### Design system

All views use semantic tokens — never raw literals:
- `Spacing` — 4pt grid (xxs=4 through xxl=48)
- `AppColors` — `.success`, `.danger`, `.metricPrimary`, `.gauge(percent:warn:critical:)`
- `AppTypography` — `.heroNumber`, `.cardTitle`, `.actionIcon`, `.badgeIcon`, `.statusIcon`, `.nano`
- `AppRadius` — `.sm`(8), `.md`(10), `.lg`(12), `.card`(16)
- `Formatters` — cached date formatters, `Formatters.tokens()` for token counts, `Formatters.cost()` for USD, `Formatters.modelShortName()` for model display names, `Formatters.copyToClipboard()` for clipboard with haptic + reset timer

Sub-grid visual details (2pt padding, 6pt dots, 8pt indicator circles) are acceptable as raw values.

### Shared components

- `CronStatusDot` / `CronStatusBadge` — reused across cron list, detail, and trace. Badge supports `.small` and `.large` styles.
- `TokenBreakdownBar` / `TokenLegendItem` — proportional bar + legend (input/output/cache split). `TokenLegendItem` is shared across all token bar variants.
- `ModelPill` — capsule badge with `ProviderIcon` + model name. Uses `Formatters.modelShortName()`. Used in 10+ places.
- `ProviderIcon` — maps provider strings to custom image assets (claude, github, openai, gemini, openclaw). Infers provider from model name when no `/` prefix (e.g. `claude-sonnet-4-6` → anthropic). Falls back to SF Symbol `cpu` for unknown providers.
- `DetailTitleView` — shared inline nav bar title with subtitle. Used on Home ("All systems OK"), Crons ("12 jobs · 2 failed"), Mem & Skills ("8 files · 10 skills"), Sessions ("Running · 149k"), and cron detail (job name + status badge).
- `CopyButton` / `CopyToolbarButton` — full-width copy button with success state, and toolbar icon variant.
- `CardContainer`, `CardLoadingView`, `CardErrorView` — dashboard card shells.
- `CommandButton` — reusable quick action button with icon, label, loading state.
- `ElapsedTimer` — live-updating elapsed time counter for long-running agent calls.
- `ParagraphRow` — paragraph-level markdown viewer with annotation support. Reused for both memory and skill markdown files.
- `CommentSheet` — unified comment sheet with three modes: `.paragraph` (inline annotation), `.page` (whole-file instruction), `.skill` (skill-level instruction — agent reads `create-skill` first). All use `CommentInputBar`.
- `CommentInputBar` — reusable chat-style input bar (multiline text field + send button). Used across comment sheets and chat.
- `QuickCommand.gridColumns` — shared 3-column grid layout constant used by `CommandsCard` and `CommandsDetailView`.

### Local storage

- `InvestigationStore` (`Core/Storage/InvestigationStore.swift`): `InvestigationStoring` protocol + UserDefaults implementation. Stores latest `SavedInvestigation` per cron job ID. Used to show "Last investigated X ago" link in cron detail.

## Conventions

- **New features**: DTO in `Core/Networking/DTOs/` (never in feature folders), domain model in feature folder with `init(dto:)`, repository protocol + `Remote*` in `Core/Repositories/`, VM subclass of `LoadableViewModel<T>`, view using `CardContainer` for dashboard cards.
- **Detail page titles**: Use `DetailTitleView` with `.toolbar(placement: .principal)` + `.navigationBarTitleDisplayMode(.inline)`. Title + dynamic subtitle (status, counts, etc.).
- **Concurrency**: `@MainActor` on all ViewModels. `@Sendable` closures for loaders. Actor-based `MemoryCache`. No `@unchecked Sendable`.
- **Logging**: `os.Logger` (subsystem: `co.uk.appwebdev.openclaw`), never `print()`.
- **Accessibility**: All custom visual components need `.accessibilityElement` + `.accessibilityLabel`.
- **Haptics**: `Haptics.shared` for user action feedback (refresh, save, errors).
- **UI**: Design tokens only. Skeleton shimmer via `.shimmer()`. `CardLoadingView`/`CardErrorView` for card states.
- **File size**: Keep files under 300 lines. Extract into separate files when growing.
- **Pagination**: Limit/offset with "Load More" button. Deduplicate on append by ID. See `CronDetailViewModel`.
- **Formatters**: `Formatters.relativeString(for:)` / `Formatters.absoluteString(for:)` for dates. `Formatters.tokens()` for token counts. `Formatters.cost()` for USD. `Formatters.modelShortName()` for model names. `Formatters.copyToClipboard()` for clipboard. Never duplicate these utilities — single source in `Formatters.swift`.
- **Markdown**: `Markdown(text).markdownTheme(.openClaw)` for LLM content. Never `AttributedString(markdown:)`. MarkdownUI v2 has no `.table` theme API.
- **Terminal output**: Strip ANSI codes with `CommandsViewModel.stripAnsi()`. Display in monospace (`AppTypography.captionMono`) with tinted background.
- **Confirmations**: Destructive actions (run cron, disable job, run command) must show an alert with confirmation before executing.
- **Prompt templates**: All agent prompts live in `Core/Prompts/PromptTemplates.swift` — one file, easy to tune.
- **Comment system**: Three comment modes via unified `CommentSheet`: `.paragraph` (inline annotation on a paragraph), `.page` (whole-file instruction), `.skill` (skill-level instruction — agent reads `create-skill` first for best practices, then the target skill). All share `CommentInputBar`. Paragraph comments queue up and batch-submit via `SubmitEditsSheet` (swipe-to-delete before submitting). Page and skill comments submit immediately to the agent.
- **Memory/skill annotation pattern**: Files are read-only in the UI. Users add comments on paragraphs, then submit as a batch to the agent. Never write files directly — always agent-mediated. `MemoryFileView` accepts optional `skillEntry` to use `skill-read` instead of `memory_get`.
- **Skill file reading**: Always use `POST /stats/exec` with `skill-read` command — not `memory_get`. Pass `"skillId relativePath"` as args.
- **Skill prompt pattern**: Skill-level prompts MUST instruct the agent to read the `create-skill` skill first (master guide for skill structure and conventions), then the target skill's SKILL.md, before acting. Never let the agent modify a skill without understanding both.
- **Long-running agent calls**: Use `ElapsedTimer` to show live elapsed time. Never set short timeouts on `chatCompletion()` — agent may take 15+ minutes for complex tasks (investigations, file edits).
- **Investigation persistence**: Save latest investigation per job to `InvestigationStore`. Show "Last investigated X ago" link to reopen previous result without re-running.
- **Investigate with AI**: Available on both cron errors (`CronDetailView`) and command results (`CommandResultSheet`). Sends structured prompt to agent, shows markdown response with model/token info.
- **`@Bindable` for passed-in VMs**: When a view receives an `@Observable` VM from outside and needs bindings (`$vm.property`), use `@Bindable var vm` — not `@State`.
- **Exit code checking**: All `stats/exec` calls go through `RemoteMemoryRepository.exec()` helper which throws `MemoryError.commandFailed` on non-zero exit codes.
- **Agent constants**: `AppConstants.agentId` (`"orchestrator"`) is the single source for the agent name. `AppConstants.workspaceRoot` and all `SessionKeys` derive from it. Never hardcode `"orchestrator"` — use these constants. Will be dynamic for multi-agent.
- **Trace comments**: Users can annotate trace steps with comments (same UX as memory paragraphs). Comments queue with inline display + swipe-to-delete. `PromptTemplates.investigateTrace()` includes session type context (main/cron/subagent) derived from the session key via `describeSessionType()`.
- **Streaming chat**: `GatewayClient.streamChat()` returns `AsyncThrowingStream<String, Error>`. Uses SSE via `URLSession.bytes(for:)`, parses `data:` lines, decodes `ChatStreamChunk` deltas, yields text tokens. Stops on `[DONE]`. Uses `longRunningSession` (15min timeout). Send only the user message — session key manages history server-side. Empty system prompt is skipped.
- **Chat history**: Load via `sessions_history` with `includeTools: false` and `limit: 50` on appear. Only user + assistant text messages (no tool calls). Loaded once per chat view lifecycle. Reload button in toolbar re-fetches latest.
- **Chat safety**: Use message UUID for index lookups during streaming (never captured `Int` index — array may change). `hasPendingSend` flag prevents history reload from overwriting in-flight messages.
- **Keyboard UX**: `.scrollDismissesKeyboard(.interactively)` on chat scroll view — keyboard follows drag gesture.
- **Cron schedule parsing**: `CronJob.scheduledTimes(for:)` computes run times for a given day from the cron expression. `parseCronField()` handles `*`, `*/N`, `N`, `N,M`, `N-M`. Interval jobs (`every Xh/Xm`) step from midnight. All client-side, no server calls.
- **Admin data commands**: `models-status`, `agents-list`, `channels-list` return JSON in stdout. Parse via `JSONDecoder` on the stdout string. `AdminViewModel` fetches all three in parallel using `async let` with `nonisolated` fetch functions for true concurrency.
- **Provider display**: Extract provider from model string (`anthropic/claude-sonnet-4-6` → "Anthropic"). `ModelRow` in `ModelsSection` shows provider label alongside `ModelPill`.

## Prompt Engineering

All prompts sent to the agent follow these principles:

- **Never send full file content** — the agent has the file on disk. Send the path, line numbers, and a few lines of context (±2 lines around the target). The agent reads the file itself with the `read` tool.
- **Tell the agent what tools to use** — explicitly say "use the read tool", "use the write tool".
- **Give the workspace root path** — use `AppConstants.workspaceRoot` (currently `~/.openclaw/workspace/orchestrator/`).
- **Thread continuity matters** — the maintained chat path uses IronClaw thread IDs. Persist the active thread ID when you want server-side context to continue across requests.
- **Structure: task → steps → rules** — system prompt says what the task is, numbered steps to follow, then rules/constraints. User message has only the data.
- **Context padding** — include 2 lines before and after the target section in a code block.
- **Agent should act, not just report** — for investigations, the prompt tells the agent to fix the issue in the same call if possible, then report what it did. Don't just suggest next steps.
- **Skill prompts: read before act** — skill-level prompts tell the agent to read `create-skill` first (best practices), then the target skill, then act. Don't hardcode the `create-skill` path — the agent resolves it from the workspace root. This two-step read produces significantly higher quality responses.

## Gateway API Gotchas

- **Client methods**: `stats()` (GET, snake_case decoder), `statsPost()` (POST `/stats/*`, snake_case decoder), `invoke()` (POST `/tools/invoke`, camelCase, no conversion), `chatCompletion()` / `streamChat()` (compatibility surface mapped to `/api/chat/thread/new`, `/api/chat/send`, `/api/chat/history`), plus explicit thread helpers.
- **URL construction**: `stats()` and `statsPost()` build URLs via string interpolation, not `.appending(path:)` — the latter percent-encodes `?` breaking query strings.
- **Shell commands**: `exec` tool blocked over HTTP (needs agent sandbox). Use `POST /stats/exec` with allowlisted command key.
- **Skill file commands**: `skills-list` (list folders), `skill-files` (list files in a skill, takes skill name as args), `skill-read` (read a file, takes "skillId relativePath" as args). All via `POST /stats/exec`.
- **Cron list**: Pass `includeDisabled: true` to get all jobs including disabled ones.
- **Cron schedules**: `kind: "cron"` has `expr`, `kind: "every"` has `everyMs` (no `expr`). DTO `expr` must be optional.
- **Session keys**: All session key strings come from `SessionKeys` constants (`.main`, `.cronPrefix`, `.subagentPrefix`), derived from `AppConstants.agentId`. Never hardcode session key prefixes.
- **Session list**: Tool is `sessions_list`. Response is wrapped: `{"count": N, "sessions": [...]}` — decode via `SessionListResponseDTO`, not a raw array. Returns all session types (main, cron persistent, subagents). Filter client-side by key prefix.
- **Session history**: Tool is `sessions_history` (not `sessions`). Takes `sessionKey` (full format), not `sessionId` (bare UUID).
- **Session types**: `agent:orchestrator:main` (one, the live chat), `agent:orchestrator:cron:<jobId>` (persistent cron sessions — skip, covered by Crons tab), `agent:orchestrator:subagent:<uuid>` (spawned subagents). Cron run sessions (`...:run:<uuid>`) do NOT appear in `sessions_list`.
- **SessionTraceView dual init**: Accepts either `CronRun` + `CronDetailRepository` (cron context) or `sessionKey` + `SessionRepository` (sessions tab). A `SessionRepositoryAdapter` bridges the two. Pass `newestFirst: true` for chat history.
- **Error responses**: Gateway in-envelope errors (200 OK with `{"status":"error"}`) surface as decode failures. Handle gracefully in VMs.
- **System health polling**: `SystemHealthViewModel` subclasses `LoadableViewModel` and uses `startPolling(interval: 15)` — starts on `onAppear`, stops on `onDisappear`.
- **Memory tools**: `memory_get` requires `sessionKey: "agent:orchestrator:main"`. Used for workspace memory files only — NOT for skill files (use `skill-read` instead).
- **Long-running agent requests**: Agent-oriented calls may take minutes for investigations or file edits. The client maintains a dedicated long-timeout session for these operations.
- **Token usage DTO**: `ModelUsageDTO` includes full per-model fields (input/output/cache/thinking/tools/cost). The `stats()` decoder handles snake_case automatically — no `CodingKeys` needed.
- **Pipeline token attribution**: Client-side aggregation. `PipelineTokenViewModel` fetches last 100 runs per cron job in parallel, filters by period date range, sums tokens. Known pipeline groups defined in `PipelineUsage.pipelines`.
- **Thread polling chat**: The maintained chat path creates or reuses a thread, sends a turn with `/api/chat/send`, then polls `/api/chat/history` until a terminal turn is available.
- **Chat session continuity**: Persist the current thread ID and reuse it for subsequent turns. The compatibility `ChatCompletionResponse.id` now carries the thread ID for callers that still store a response identifier.
- **Stream cancellation**: Dropping the client stream does NOT cancel the server-side run — it continues until IronClaw finishes processing the thread turn.
- **Admin exec commands**: `models-status`, `agents-list`, `channels-list` all return JSON in `stdout`. Parse with `JSONDecoder` after extracting `response.stdout?.data(using: .utf8)`. `agents-list` returns an array, the others return objects. `channels-list` has nested `chat` (channel dict), `usage.providers` (quota bars). No args needed for any of them.
- **Tools exec commands**: `tools-list` (native tools + profile + MCP server names, fast), `mcp-list` (MCP server configs, ~9s), `mcp-tools` (MCP tool lists per server, 10-30s — always lazy load on expand, never on appear). All return JSON in stdout. `tools-list` has `mcp_servers` key requiring `CodingKeys`.
- **DI pattern**: Never create concrete repository/client instances inside views or VMs. Always inject via `init` parameters. `MainTabView` is the composition root — creates all shared instances once and passes them down.
- **Memory maintenance**: `MemoryActionSheet` delegates to `MemoryViewModel.runMaintenanceAction(prompt:)` — never accesses client directly from views. Prompts in `MemoryActionPrompts.swift` extension. Agent always reads `/app/docs` memory best practices before acting.
