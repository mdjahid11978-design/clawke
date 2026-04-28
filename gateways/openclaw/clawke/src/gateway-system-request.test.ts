import test from "node:test";
import assert from "node:assert/strict";
import { handleGatewaySystemRequest, runOpenClawSystemPrompt } from "./gateway-system-request.ts";

const ctx = {
  accountId: "OpenClaw",
  log: {
    info: () => {},
    warn: () => {},
    error: () => {},
  },
} as any;

test("OpenClaw system request returns gateway_system_response without user message", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const response = await handleGatewaySystemRequest(
    ctx,
    {
      type: "gateway_system_request",
      request_id: "req_1",
      gateway_id: "OpenClaw",
      system_session_id: "__clawke_system__:OpenClaw",
      purpose: "translation",
      prompt: "Return strict JSON.",
      response_schema: {
        type: "object",
        required: ["description"],
        properties: { description: { type: "string" } },
      },
    },
    async (request) => {
      calls.push(request);
      return { text: '{"description":"设置并使用 1Password CLI。"}' };
    },
  );

  assert.equal(response.type, "gateway_system_response");
  assert.equal(response.request_id, "req_1");
  assert.equal(response.ok, true);
  assert.deepEqual(response.json, { description: "设置并使用 1Password CLI。" });
  assert.equal("conversation_id" in response, false);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].system_session_id, "__clawke_system__:OpenClaw");
  assert.equal(calls[0].prompt, "Return strict JSON.");
});

test("OpenClaw system request returns safe error for invalid JSON", async () => {
  const warnings: string[] = [];
  const invalidCtx = {
    ...ctx,
    log: {
      ...ctx.log,
      warn: (message: string) => warnings.push(message),
    },
  };
  const response = await handleGatewaySystemRequest(
    invalidCtx,
    {
      type: "gateway_system_request",
      request_id: "req_2",
      gateway_id: "OpenClaw",
      system_session_id: "__clawke_system__:OpenClaw",
      purpose: "translation",
      prompt: "Return strict JSON.",
    },
    async () => ({ text: "not json" }),
  );

  assert.equal(response.type, "gateway_system_response");
  assert.equal(response.request_id, "req_2");
  assert.equal(response.ok, false);
  assert.equal(response.error_code, "invalid_json");
  assert.match(warnings[0], /textLength=8/);
  assert.match(warnings[0], /textPreview="not json"/);
});

test("OpenClaw system request accepts a fenced JSON response", async () => {
  const response = await handleGatewaySystemRequest(
    ctx,
    {
      type: "gateway_system_request",
      request_id: "req_fenced",
      gateway_id: "OpenClaw",
      system_session_id: "__clawke_system__:OpenClaw",
      purpose: "translation",
      prompt: "Return strict JSON.",
    },
    async () => ({
      text: '```json\n{"items":[{"id":"job_1","description":"中文描述"}]}\n```',
    }),
  );

  assert.equal(response.type, "gateway_system_response");
  assert.equal(response.request_id, "req_fenced");
  assert.equal(response.ok, true);
  assert.deepEqual(response.json, {
    items: [{ id: "job_1", description: "中文描述" }],
  });
});

test("OpenClaw system prompt uses the SDK reply dispatcher contract", async () => {
  const calls: string[] = [];
  const innerDispatcher = {
    deliver: async (payload: { text?: string }) => {
      calls.push(`deliver:${payload.text}`);
    },
    markComplete: () => calls.push("markComplete"),
    waitForIdle: async () => calls.push("waitForIdle"),
  };
  const core = {
    channel: {
      routing: {
        resolveAgentRoute: () => ({
          sessionKey: "session_1",
          accountId: "OpenClaw",
        }),
      },
      reply: {
        finalizeInboundContext: (input: Record<string, unknown>) => input,
        createReplyDispatcherWithTyping: (options: any) => {
          calls.push(`create:${options.sessionKey}`);
          return {
            dispatcher: {
              markComplete: innerDispatcher.markComplete,
              waitForIdle: innerDispatcher.waitForIdle,
              deliver: async (payload: { text?: string }) => {
                calls.push(`deliver:${payload.text}`);
                await options.dispatcher.deliver(payload);
              },
            },
            replyOptions: {
              onReplyStart: () => calls.push("replyStart"),
            },
            markDispatchIdle: () => calls.push("markDispatchIdle"),
            markRunComplete: () => calls.push("markRunComplete"),
          };
        },
        withReplyDispatcher: async ({ dispatcher, run, onSettled }: any) => {
          assert.ok(dispatcher);
          assert.equal(dispatcher.markComplete, innerDispatcher.markComplete);
          try {
            return await run();
          } finally {
            dispatcher.markComplete();
            await dispatcher.waitForIdle();
            await onSettled?.();
          }
        },
        dispatchReplyFromConfig: async ({ dispatcher, replyOptions }: any) => {
          assert.equal(replyOptions.disableBlockStreaming, true);
          assert.equal(typeof replyOptions.onPartialReply, "function");
          replyOptions.onPartialReply({ text: '{"description":"partial"}' });
          await dispatcher.deliver({ text: '{"description":"final"}' });
        },
      },
    },
  };

  const result = await runOpenClawSystemPrompt(ctx, {
    type: "gateway_system_request",
    request_id: "req_sdk",
    gateway_id: "OpenClaw",
    system_session_id: "__clawke_system__:OpenClaw",
    purpose: "translation",
    prompt: "Return JSON.",
  }, core as any);

  assert.deepEqual(result, { text: '{"description":"final"}' });
  assert.deepEqual(calls, [
    "create:session_1",
    "deliver:{\"description\":\"final\"}",
    "markComplete",
    "waitForIdle",
    "markRunComplete",
    "markDispatchIdle",
  ]);
});
