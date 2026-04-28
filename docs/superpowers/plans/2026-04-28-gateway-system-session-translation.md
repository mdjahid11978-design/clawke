# Gateway System Session Translation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace Server-side OpenAI skill translation with Gateway system-session translation across OpenClaw, Hermes, and nanobot.

**Architecture:** Server keeps the existing skill translation queue/cache, but delegates translation to `GatewayManageService.getSystemSession(gatewayId)`. Gateway system requests are request-response protocol messages that never enter user conversations or client sync. Gateway implementations return strict JSON for translation, and Server validates it before writing cache.

**Tech Stack:** Node.js TypeScript server, native `node:test`, OpenClaw TypeScript gateway, Hermes/nanobot Python gateways, pytest-compatible Python tests.

---

## File Structure

- Create `server/src/types/gateway-session.ts`: shared Server-side session request/response interfaces.
- Create `server/src/upstream/gateway-system-client.ts`: WebSocket request-response helper for `gateway_system_request`.
- Create `server/src/services/gateway-manage-service.ts`: `getSystemSession(gatewayId)` implementation.
- Create `server/src/services/gateway-system-translator.ts`: skill description translator backed by Gateway system session.
- Modify `server/src/services/skill-translation-service.ts`: pass job context into translator and add required logs.
- Modify `server/src/upstream/openclaw-listener.ts`: treat `gateway_system_response` as transient per-request response.
- Modify `server/src/index.ts`: wire `GatewayManageService` and remove OpenAI translator.
- Modify `server/src/services/index.ts`: export new services.
- Delete `server/src/services/skill-translator.ts`: remove production OpenAI translator.
- Delete `server/test/skill-translator.test.js` and `server/test/skill-translator-live.test.js`: remove OpenAI translator tests.
- Create `server/test/gateway-manage-service.test.js`: system session behavior.
- Create `server/test/gateway-system-translator.test.js`: gateway-backed translation behavior.
- Modify `server/test/skill-translation-service.test.js`: assert translator receives gateway/job context and failure marks job failed.
- Modify `gateways/openclaw/clawke/src/protocol.ts`: add system request/response protocol constants.
- Modify `gateways/openclaw/clawke/src/gateway.ts`: handle `gateway_system_request` with isolated system session.
- Create `gateways/openclaw/clawke/src/gateway-system-request.test.ts`: OpenClaw system request isolation tests.
- Modify `gateways/hermes/clawke/clawke_channel.py`: handle `gateway_system_request` with isolated system session.
- Modify `gateways/hermes/clawke/test_clawke_channel.py`: Hermes system request isolation tests.
- Modify `gateways/nanobot/clawke/clawke.py`: handle `gateway_system_request` with isolated system execution.
- Create `gateways/nanobot/clawke/test_clawke_channel.py`: nanobot system request isolation tests.

## Task 1: Server System Session Core

**Files:**
- Create: `server/src/types/gateway-session.ts`
- Create: `server/src/upstream/gateway-system-client.ts`
- Create: `server/src/services/gateway-manage-service.ts`
- Modify: `server/src/upstream/openclaw-listener.ts`
- Test: `server/test/gateway-manage-service.test.js`

- [x] **Step 1: Write failing tests**

Add tests that verify:

- `getSystemSession("OpenClaw")` returns `__clawke_system__:OpenClaw`.
- repeated calls use the same deterministic session ID.
- requests serialize `gateway_id`, `system_session_id`, `purpose`, `prompt`, `response_schema`, and `metadata`.
- `gateway_system_response` resolves only when `request_id` matches.
- timeout rejects with `gateway_timeout`.

- [x] **Step 2: Run test to verify RED**

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/gateway-manage-service.test.js
```

Expected: build or test fails because the new modules do not exist.

- [x] **Step 3: Implement minimal Server system-session core**

Implement the new types, request helper, and `GatewayManageService`. Add `gateway_system_response` to transient gateway responses so main routing does not broadcast it to clients.

- [x] **Step 4: Run test to verify GREEN**

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/gateway-manage-service.test.js
```

Expected: PASS.

## Task 2: Gateway-Backed Skill Translation

**Files:**
- Create: `server/src/services/gateway-system-translator.ts`
- Modify: `server/src/services/skill-translation-service.ts`
- Modify: `server/src/index.ts`
- Modify: `server/src/services/index.ts`
- Delete: `server/src/services/skill-translator.ts`
- Delete: `server/test/skill-translator.test.js`
- Delete: `server/test/skill-translator-live.test.js`
- Test: `server/test/gateway-system-translator.test.js`
- Test: `server/test/skill-translation-service.test.js`

- [x] **Step 1: Write failing translator tests**

Add tests that verify:

- translator calls `GatewayManageService.getSystemSession(gatewayId)`.
- system request uses `purpose: "translation"` and response schema requiring `description`.
- metadata uses generic `source`, `entity_type`, `entity_id`, `locale`, `source_hash`, `job_id`; no fixed `skill_id` protocol field.
- JSON response `{ "description": "..." }` becomes the translated description.
- invalid/missing `description` throws and marks the translation job failed.
- no `OPENAI_API_KEY` or `CLAWKE_TRANSLATION_API_KEY` is required.

- [x] **Step 2: Run tests to verify RED**

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/gateway-system-translator.test.js test/skill-translation-service.test.js
```

Expected: fails because gateway translator and job context are not implemented.

- [x] **Step 3: Implement gateway translator and remove OpenAI translator**

Update `SkillTranslator` to accept job context, pass job fields from `runNextJob()`, implement gateway-backed translator, wire it in `index.ts`, and delete the OpenAI translator production implementation/tests.

- [x] **Step 4: Run tests to verify GREEN**

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/gateway-manage-service.test.js test/gateway-system-translator.test.js test/skill-translation-service.test.js test/skills-routes.test.js
```

Expected: PASS.

## Task 3: OpenClaw Gateway System Request

**Files:**
- Modify: `gateways/openclaw/clawke/src/protocol.ts`
- Modify: `gateways/openclaw/clawke/src/gateway.ts`
- Test: `gateways/openclaw/clawke/src/gateway-system-request.test.ts`

- [x] **Step 1: Write failing OpenClaw tests**

Add tests that verify:

- `gateway_system_request` returns `gateway_system_response` with matching `request_id`.
- request uses `system_session_id`, not user `conversation_id`.
- system response is not sent as `agent_text` to the user stream.
- invalid JSON from the model returns `ok: false` or a schema-safe error.

- [x] **Step 2: Run test to verify RED**

Run:

```bash
node --test gateways/openclaw/clawke/src/gateway-system-request.test.ts
```

Expected: fails because the handler is missing.

- [x] **Step 3: Implement OpenClaw system request handler**

Add protocol constants and route system requests to an isolated model call. The handler must log request boundaries and return only `gateway_system_response`.

- [x] **Step 4: Run test to verify GREEN**

Run:

```bash
node --test gateways/openclaw/clawke/src/gateway-system-request.test.ts
```

Expected: PASS.

## Task 4: Hermes Gateway System Request

**Files:**
- Modify: `gateways/hermes/clawke/clawke_channel.py`
- Modify: `gateways/hermes/clawke/test_clawke_channel.py`

- [x] **Step 1: Write failing Hermes tests**

Add tests that verify:

- `gateway_system_request` returns `gateway_system_response`.
- `system_session_id` is used as the internal sender/session.
- no user-facing `agent_text` message is emitted for system requests.
- invalid JSON or execution error returns `ok: false`.

- [x] **Step 2: Run test to verify RED**

Run:

```bash
python3 -m pytest gateways/hermes/clawke/test_clawke_channel.py -q
```

Expected: fails because the handler is missing.

- [x] **Step 3: Implement Hermes system request handler**

Add a system request branch in the WebSocket receive loop and isolate model execution from normal user message dispatch.

- [x] **Step 4: Run test to verify GREEN**

Run:

```bash
python3 -m pytest gateways/hermes/clawke/test_clawke_channel.py -q
```

Expected: PASS.

## Task 5: nanobot Gateway System Request

**Files:**
- Modify: `gateways/nanobot/clawke/clawke.py`
- Create: `gateways/nanobot/clawke/test_clawke_channel.py`

- [x] **Step 1: Write failing nanobot tests**

Add tests that verify:

- `gateway_system_request` returns `gateway_system_response`.
- the system session does not reuse `clawke_user` chat routing.
- the handler does not emit normal outbound `agent_text` user messages.
- execution errors return `ok: false`.

- [x] **Step 2: Run test to verify RED**

Run:

```bash
python3 -m pytest gateways/nanobot/clawke/test_clawke_channel.py -q
```

Expected: fails because the handler is missing.

- [x] **Step 3: Implement nanobot system request handler**

Add a system request branch in the receive loop and isolate execution behind an overridable method so tests can validate protocol behavior without real model calls.

- [x] **Step 4: Run test to verify GREEN**

Run:

```bash
python3 -m pytest gateways/nanobot/clawke/test_clawke_channel.py -q
```

Expected: PASS.

## Task 6: Full Verification

**Files:**
- All files above

- [x] **Step 1: Run focused Server tests**

Run:

```bash
cd server && npm run build && node --test --test-concurrency=1 --test-force-exit test/gateway-manage-service.test.js test/gateway-system-translator.test.js test/skill-translation-service.test.js test/skills-routes.test.js
```

Expected: PASS.

- [x] **Step 2: Run Gateway tests**

Run:

```bash
node --test gateways/openclaw/clawke/src/gateway-system-request.test.ts
python3 -m pytest gateways/hermes/clawke/test_clawke_channel.py gateways/nanobot/clawke/test_clawke_channel.py -q
```

Expected: PASS.

- [x] **Step 3: Run repo status check**

Run:

```bash
git status --short
```

Expected: only intentional files changed.

- [x] **Step 4: Commit**

Run:

```bash
git add -A
git commit -m "Use gateway system sessions for skill translation"
```

Expected: commit created on `skills-management`.

