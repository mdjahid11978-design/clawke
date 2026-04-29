import test from "node:test";
import assert from "node:assert/strict";
import { ensureOpenClawSessionModel, switchOpenClawSessionModel } from "./model-switch.ts";

function createCore(
  calls: string[],
  options: { fail?: boolean; expectedModel?: string } = {},
) {
  const expectedModel = options.expectedModel ?? "minimax-portal/MiniMax-M2.7";
  const dispatcher = {
    markComplete: () => calls.push("markComplete"),
    waitForIdle: async () => calls.push("waitForIdle"),
  };
  return {
    dispatcher,
    core: {
      channel: {
        routing: {
          resolveAgentRoute: (input: Record<string, unknown>) => {
            assert.equal(input.channel, "clawke");
            assert.deepEqual(input.peer, { kind: "direct", id: "clawke:conv_1" });
            return {
              sessionKey: "session_1",
              accountId: "OpenClaw",
            };
          },
        },
        reply: {
          finalizeInboundContext: (input: Record<string, unknown>) => input,
          createReplyDispatcherWithTyping: (input: Record<string, unknown>) => {
            assert.equal(input.sessionKey, "session_1");
            return {
              dispatcher,
              replyOptions: {
                onReplyStart: () => calls.push("replyStart"),
              },
              markDispatchIdle: () => calls.push("markDispatchIdle"),
              markRunComplete: () => calls.push("markRunComplete"),
            };
          },
          withReplyDispatcher: async ({ dispatcher: actualDispatcher, run }: any) => {
            assert.equal(actualDispatcher, dispatcher);
            try {
              if (options.fail) {
                throw new Error("model command failed");
              }
              return await run();
            } finally {
              actualDispatcher.markComplete();
              await actualDispatcher.waitForIdle();
            }
          },
          dispatchReplyFromConfig: async ({ ctx, dispatcher: actualDispatcher, replyOptions }: any) => {
            assert.equal(actualDispatcher, dispatcher);
            assert.equal(ctx.Body, `/model ${expectedModel}`);
            assert.equal(ctx.BodyForCommands, `/model ${expectedModel}`);
            assert.equal(ctx.CommandAuthorized, true);
            assert.equal(replyOptions.disableBlockStreaming, true);
            calls.push("dispatch");
          },
        },
      },
    },
  };
}

test("OpenClaw model switch uses current SDK dispatcher contract", async () => {
  const calls: string[] = [];
  const logs: string[] = [];
  const { core } = createCore(calls);

  const switched = await switchOpenClawSessionModel({
    ctx: {
      accountId: "OpenClaw",
      log: {
        info: (message) => logs.push(message),
        error: (message) => logs.push(message),
      },
    },
    core,
    cfg: {},
    senderId: "conv_1",
    modelOverride: "minimax-portal/MiniMax-M2.7",
  });

  assert.equal(switched, true);
  assert.deepEqual(calls, [
    "dispatch",
    "markComplete",
    "waitForIdle",
    "markRunComplete",
    "markDispatchIdle",
  ]);
  assert.match(logs.at(0) ?? "", /Switching model to: minimax-portal\/MiniMax-M2\.7/);
  assert.match(logs.at(-1) ?? "", /Model switched to: minimax-portal\/MiniMax-M2\.7/);
});

test("OpenClaw model switch keeps canonical provider/model id intact", async () => {
  const calls: string[] = [];
  const { core } = createCore(calls, {
    expectedModel: "anthropic/claude-sonnet-4",
  });

  const switched = await switchOpenClawSessionModel({
    ctx: {
      accountId: "OpenClaw",
      log: {
        info: () => {},
        error: () => {},
      },
    },
    core,
    cfg: {},
    senderId: "conv_1",
    modelOverride: "anthropic/claude-sonnet-4",
  });

  assert.equal(switched, true);
  assert.equal(calls[0], "dispatch");
});

test("OpenClaw model cache updates only after successful switch", async () => {
  const calls: string[] = [];
  const { core } = createCore(calls, { fail: true });
  const sessionModels = new Map<string, string>();
  const errors: string[] = [];

  const failed = await ensureOpenClawSessionModel({
    ctx: {
      accountId: "OpenClaw",
      log: {
        info: () => {},
        error: (message) => errors.push(message),
      },
    },
    core,
    cfg: {},
    senderId: "conv_1",
    modelOverride: "minimax-portal/MiniMax-M2.7",
    sessionModels,
  });

  assert.equal(failed, "failed");
  assert.equal(sessionModels.has("conv_1"), false);
  assert.match(errors[0], /model command failed/);

  const retryCalls: string[] = [];
  const retry = await ensureOpenClawSessionModel({
    ctx: {
      accountId: "OpenClaw",
      log: {
        info: () => {},
        error: () => {},
      },
    },
    core: createCore(retryCalls).core,
    cfg: {},
    senderId: "conv_1",
    modelOverride: "minimax-portal/MiniMax-M2.7",
    sessionModels,
  });

  assert.equal(retry, "switched");
  assert.equal(sessionModels.get("conv_1"), "minimax-portal/MiniMax-M2.7");
});
