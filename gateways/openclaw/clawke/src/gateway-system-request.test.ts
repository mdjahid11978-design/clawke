import test from "node:test";
import assert from "node:assert/strict";
import { handleGatewaySystemRequest } from "./gateway-system-request.ts";

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
  const response = await handleGatewaySystemRequest(
    ctx,
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
});
