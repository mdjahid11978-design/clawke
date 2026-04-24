# Task Management Design

Date: 2026-04-24

## Context

Clawke needs a first-class task management page for scheduled/background agent work. The page should support listing, creating, editing, deleting, enabling, pausing, manually triggering, and inspecting task run history and results.

The implementation should reference Hermes WebUI task management behavior, but it should not copy its web UI styling. Clawke should use its existing Flutter management-page style.

Existing `server/src/services/cron-service.ts` is an early mock/SDUI prototype. It stores local SQLite cron rows, only appears in mock mode, and is not wired into the current `ActionRouter` flow. It is not the design foundation for the new feature.

## Decisions

- Task management is an independent app page, not a chat/session message experience.
- Flutter calls Clawke Server over HTTP for task management, matching existing independent management pages such as Skills.
- Clawke Server does not execute tasks, run schedule ticks, or persist task truth.
- The agent/gateway side is the authoritative task store and execution owner.
- The first supported agents are Hermes and OpenClaw.
- Clawke Server translates HTTP requests into gateway task commands over the existing upstream WebSocket connection, matching existing gateway query patterns.

## Goals

- Provide a native Flutter task management page.
- Support Hermes and OpenClaw through one server-facing task API.
- Keep task execution and task storage inside each agent/gateway.
- Show task metadata, enabled state, schedule, prompt, selected skills, recent run status, run history, and run output.
- Let users trigger a task manually without Clawke executing the prompt itself.

## Non-Goals

- Clawke Server will not implement a cron scheduler.
- Clawke Server will not execute task prompts.
- Clawke Server will not keep an editable task mirror in SQLite.
- The initial version will not aggregate tasks from every disconnected account.
- The initial version will not clone Hermes WebUI visual styling.

## Architecture

### Flutter Client

Add a dedicated `TasksManagementScreen` following the shape of `SkillsManagementScreen`. This is an independent management page, so it should use a typed HTTP API service rather than chat messages or SDUI page messages.

- Header with task counts and refresh/create actions.
- Search and filters for status, enabled state, agent/account, and schedule type.
- Task list cards optimized for scanning.
- Create/edit dialog with name, schedule, prompt, delivery target, skills, and enabled state.
- Run history view for recent runs.
- Output viewer for a selected run.

Client state should live in a Riverpod controller, backed by a `TasksApiService` using Dio and the existing `MediaResolver` auth/base URL pattern.

Client-to-server transport choice:

- Independent management pages use HTTP: Skills already follows this pattern.
- Chat and live agent streams use WebSocket.
- Server-driven UI cards use CUP over WebSocket.
- Task management should therefore use HTTP from Flutter to Clawke Server.

### Clawke Server

Add `server/src/routes/tasks-routes.ts` and register it from `server/src/http-server.ts`.

The HTTP layer validates inputs, selects an account/gateway, forwards commands to the gateway over the existing upstream WebSocket, waits for a structured response, and normalizes errors. It does not store task records as truth.

Server-to-gateway transport choice:

- Gateways already maintain persistent upstream WebSocket connections to Clawke Server.
- Existing runtime queries such as models and skills already use Server-to-Gateway WS request/response.
- Task commands should reuse that upstream WS channel instead of creating per-gateway HTTP servers.

Proposed HTTP endpoints:

- `GET /api/tasks?account_id=:accountId`
- `GET /api/tasks/:taskId?account_id=:accountId`
- `POST /api/tasks`
- `PUT /api/tasks/:taskId`
- `DELETE /api/tasks/:taskId?account_id=:accountId`
- `PUT /api/tasks/:taskId/enabled`
- `POST /api/tasks/:taskId/run`
- `GET /api/tasks/:taskId/runs?account_id=:accountId`
- `GET /api/tasks/:taskId/runs/:runId/output?account_id=:accountId`

Requests that mutate or inspect a task must include `account_id` either in the query or body. If omitted, the server may use the current/default connected account only when exactly one gateway account is connected.

### Gateway Task Protocol

Server-to-gateway commands:

- `task_list`
- `task_get`
- `task_create`
- `task_update`
- `task_delete`
- `task_set_enabled`
- `task_run`
- `task_runs`
- `task_output`

Gateway-to-server responses:

- `task_list_response`
- `task_get_response`
- `task_mutation_response`
- `task_run_response`
- `task_runs_response`
- `task_output_response`

Gateway-to-server async events:

- `task_event` with `started`, `completed`, `failed`, or `cancelled`

The protocol should include a `request_id` so the server can correlate HTTP requests with gateway responses, mirroring the existing query pattern for models and skills but making correlation explicit.

## Data Model

### Task

```ts
interface ManagedTask {
  id: string;
  account_id: string;
  agent: 'hermes' | 'openclaw' | string;
  name: string;
  schedule: string;
  schedule_text?: string;
  prompt: string;
  enabled: boolean;
  status: 'active' | 'paused' | 'disabled' | 'error';
  skills?: string[];
  deliver?: 'local' | 'discord' | 'telegram' | string;
  next_run_at?: string;
  last_run?: TaskRunSummary;
  created_at?: string;
  updated_at?: string;
}
```

### Task Draft

```ts
interface TaskDraft {
  account_id: string;
  name?: string;
  schedule: string;
  prompt: string;
  enabled?: boolean;
  skills?: string[];
  deliver?: string;
}
```

### Task Run

```ts
interface TaskRun {
  id: string;
  task_id: string;
  started_at: string;
  finished_at?: string;
  status: 'running' | 'success' | 'failed' | 'cancelled';
  output_preview?: string;
  error?: string;
}
```

## Hermes Adapter

Hermes gateway should map the task protocol to Hermes cron capabilities:

- `task_list` maps to `cron.jobs.list_jobs`.
- `task_create` maps to `cron.jobs.create_job`.
- `task_update` maps to `cron.jobs.update_job`.
- `task_delete` maps to `cron.jobs.remove_job`.
- `task_set_enabled` maps to pause/resume behavior.
- `task_run` maps to Hermes manual run behavior and returns when the run has started.
- `task_runs` reads Hermes run/output metadata.
- `task_output` reads the selected run output.

Hermes remains responsible for scheduling and task execution.

## OpenClaw Adapter

OpenClaw gateway should implement the same task protocol. If OpenClaw already has a native task or scheduler mechanism, the adapter should wrap it. If it does not, the OpenClaw gateway side may provide a local agent-owned task adapter, but the task store still belongs to the OpenClaw/gateway side, not Clawke Server.

OpenClaw remains responsible for scheduling and task execution.

## UI Behavior

The task page should use Clawke's native management style:

- Compact, information-dense cards.
- Stable controls for create, edit, delete, enable, pause, resume, run now, view runs, and view output.
- Clear empty, loading, error, and disconnected states.
- Account selector when both Hermes and OpenClaw are connected.
- Skill picker sourced from the selected account's skills API.
- Schedule field accepts cron expressions and agent-supported natural shorthand such as `every 1h` when the selected gateway supports it.

The page should not rely on chat messages or SDUI message cards for its primary workflow. Its Flutter structure should align with the Skills management page: typed models, a Dio API service, a Riverpod controller, and a full-screen management view.

## Error Handling

- If no gateway account is connected, show a disconnected state and return HTTP `503`.
- If `account_id` is ambiguous, return HTTP `400` with `account_required`.
- If a gateway does not support tasks, return HTTP `501` with `tasks_unsupported`.
- If the gateway times out, return HTTP `504` with `gateway_timeout`.
- Validation errors return HTTP `400` with field-level details when possible.
- Gateway errors are normalized to `{ error, message, details? }`.

## Testing

Server tests:

- HTTP route validation and auth.
- Account selection behavior.
- Gateway timeout behavior.
- Mapping from HTTP endpoints to gateway commands.
- Normalized error responses.

Gateway tests:

- Hermes task command handling with mocked `cron.jobs`.
- OpenClaw task command handling with mocked adapter.
- `request_id` response correlation.

Flutter tests:

- Task API service serialization.
- Task controller loading, create/update/delete, enable/run, and error states.
- Task management screen loading, empty, populated, filter, edit dialog, delete confirmation, run history, and output viewer states.

## Open Questions

- Whether OpenClaw already has a native scheduled-task store to wrap.
- Whether Hermes run history exposes structured metadata or only output files.
- Whether task completion events should trigger native notifications in the first release or a later iteration.
