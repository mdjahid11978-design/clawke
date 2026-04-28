import test from "node:test";
import assert from "node:assert/strict";
import {
  OpenClawModelAdapter,
  modelCatalogEntryToKey,
  modelCatalogPayloadToKeys,
  modelCatalogPayloadToModels,
} from "./model-adapter.ts";
import type { OpenClawGatewayRpc } from "./task-adapter.ts";

test("OpenClawModelAdapter lists models through OpenClaw Gateway RPC", async () => {
  const calls: Array<{ method: string; params?: unknown }> = [];
  const rpc: OpenClawGatewayRpc = async (method, params) => {
    calls.push({ method, params });
    return {
      models: [
        { provider: "anthropic", id: "claude-sonnet-4-6", name: "Claude Sonnet" },
        { provider: "openrouter", id: "openrouter/hunter-alpha", name: "Hunter" },
        { provider: "nvidia", id: "moonshotai/kimi-k2.5", name: "Kimi" },
        { provider: "anthropic", id: "claude-sonnet-4-6", name: "Duplicate" },
        { provider: "", id: "ignored" },
        { provider: "openai", id: "" },
      ],
    };
  };
  const adapter = new OpenClawModelAdapter({ rpc });

  const models = await adapter.listModels();

  assert.deepEqual(calls, [{ method: "models.list", params: {} }]);
  assert.deepEqual(models, [
    {
      model_id: "anthropic/claude-sonnet-4-6",
      id: "claude-sonnet-4-6",
      provider: "anthropic",
      display_name: "Claude Sonnet",
      name: "Claude Sonnet",
      raw_json: { provider: "anthropic", id: "claude-sonnet-4-6", name: "Claude Sonnet" },
    },
    {
      model_id: "openrouter/hunter-alpha",
      id: "openrouter/hunter-alpha",
      provider: "openrouter",
      display_name: "Hunter",
      name: "Hunter",
      raw_json: { provider: "openrouter", id: "openrouter/hunter-alpha", name: "Hunter" },
    },
    {
      model_id: "nvidia/moonshotai/kimi-k2.5",
      id: "moonshotai/kimi-k2.5",
      provider: "nvidia",
      display_name: "Kimi",
      name: "Kimi",
      raw_json: { provider: "nvidia", id: "moonshotai/kimi-k2.5", name: "Kimi" },
    },
  ]);
});

test("OpenClawModelAdapter returns empty list and logs when models.list fails", async () => {
  const logs: string[] = [];
  const adapter = new OpenClawModelAdapter({
    rpc: async () => {
      throw new Error("gateway unavailable");
    },
  });

  const models = await adapter.listModels({
    log: { error: (message: string) => logs.push(message) },
  });

  assert.deepEqual(models, []);
  assert.equal(logs.length, 1);
  assert.match(logs[0], /models\.list failed: gateway unavailable/);
});

test("modelCatalogEntryToKey mirrors OpenClaw provider/model key semantics", () => {
  assert.equal(
    modelCatalogEntryToKey({ provider: "anthropic", id: "claude-opus-4-6" }),
    "anthropic/claude-opus-4-6",
  );
  assert.equal(
    modelCatalogEntryToKey({ provider: "openrouter", id: "openrouter/hunter-alpha" }),
    "openrouter/hunter-alpha",
  );
  assert.equal(modelCatalogEntryToKey({ provider: "nvidia", id: "moonshotai/kimi-k2.5" }), "nvidia/moonshotai/kimi-k2.5");
  assert.equal(modelCatalogEntryToKey({ provider: "", id: "gpt-5.4" }), undefined);
  assert.equal(modelCatalogEntryToKey({ provider: "openai", id: "" }), undefined);
});

test("modelCatalogPayloadToModels preserves OpenClaw model metadata", () => {
  assert.deepEqual(
    modelCatalogPayloadToModels({
      models: [
        {
          provider: "deepseek",
          id: "deepseek-v4-pro",
          name: "DeepSeek V4 Pro",
          contextWindow: 1_000_000,
          reasoning: true,
          input: ["text"],
        },
        {
          provider: "minimax",
          id: "MiniMax-M2.7",
          name: "MiniMax M2.7",
          alias: "Minimax",
          contextWindow: 204_800,
          reasoning: true,
          input: ["text", "image"],
        },
      ],
    }),
    [
      {
        model_id: "deepseek/deepseek-v4-pro",
        id: "deepseek-v4-pro",
        provider: "deepseek",
        display_name: "DeepSeek V4 Pro",
        name: "DeepSeek V4 Pro",
        context_window: 1_000_000,
        reasoning: true,
        input: ["text"],
        raw_json: {
          provider: "deepseek",
          id: "deepseek-v4-pro",
          name: "DeepSeek V4 Pro",
          contextWindow: 1_000_000,
          reasoning: true,
          input: ["text"],
        },
      },
      {
        model_id: "minimax/MiniMax-M2.7",
        id: "MiniMax-M2.7",
        provider: "minimax",
        display_name: "Minimax",
        name: "MiniMax M2.7",
        alias: "Minimax",
        context_window: 204_800,
        reasoning: true,
        input: ["text", "image"],
        raw_json: {
          provider: "minimax",
          id: "MiniMax-M2.7",
          name: "MiniMax M2.7",
          alias: "Minimax",
          contextWindow: 204_800,
          reasoning: true,
          input: ["text", "image"],
        },
      },
    ],
  );
});

test("modelCatalogPayloadToKeys keeps legacy string response compatibility", () => {
  assert.deepEqual(
    modelCatalogPayloadToKeys({
      models: [
        { provider: "deepseek", id: "deepseek-v4-pro", name: "DeepSeek V4 Pro" },
        { provider: "deepseek", id: "deepseek-v4-pro", name: "Duplicate" },
        { provider: "minimax", id: "MiniMax-M2.7", name: "MiniMax M2.7" },
      ],
    }),
    ["deepseek/deepseek-v4-pro", "minimax/MiniMax-M2.7"],
  );
});
