import test from "node:test";
import assert from "node:assert/strict";
import { OpenClawModelAdapter, type OpenClawGatewayModel } from "./model-adapter.ts";
import { createOpenClawGatewayRpc } from "./task-adapter.ts";

const liveTestEnabled = process.env.OPENCLAW_MODEL_RPC_LIVE === "1";

test(
  "live OpenClaw Gateway models.list returns model catalog",
  {
    skip: liveTestEnabled ? false : "Set OPENCLAW_MODEL_RPC_LIVE=1 to query the local OpenClaw Gateway",
    timeout: 15_000,
  },
  async () => {
    const models = await queryLiveModelsList();

    assert.ok(models.length > 0, `Expected at least one model, got: ${JSON.stringify(models)}`);

    for (const model of models) {
      assert.equal(typeof model.model_id, "string", `Expected model.model_id string, got: ${JSON.stringify(model)}`);
      assert.equal(typeof model.id, "string", `Expected model.id string, got: ${JSON.stringify(model)}`);
      assert.equal(typeof model.provider, "string", `Expected model.provider string, got: ${JSON.stringify(model)}`);
      assert.equal(typeof model.display_name, "string", `Expected model.display_name string, got: ${JSON.stringify(model)}`);
      if (model.name !== undefined) {
        assert.equal(typeof model.name, "string", `Expected model.name string, got: ${JSON.stringify(model)}`);
      }
      if (model.alias !== undefined) {
        assert.equal(typeof model.alias, "string", `Expected model.alias string, got: ${JSON.stringify(model)}`);
      }
      if (model.context_window !== undefined) {
        assert.equal(
          typeof model.context_window,
          "number",
          `Expected model.context_window number, got: ${JSON.stringify(model)}`,
        );
      }
      if (model.reasoning !== undefined) {
        assert.equal(typeof model.reasoning, "boolean", `Expected model.reasoning boolean, got: ${JSON.stringify(model)}`);
      }
      if (model.input !== undefined) {
        assert.ok(Array.isArray(model.input), `Expected model.input array, got: ${JSON.stringify(model)}`);
        for (const input of model.input) {
          assert.equal(typeof input, "string", `Expected model.input item string, got: ${JSON.stringify(model)}`);
        }
      }
    }

    const sample = models
      .slice(0, 10)
      .map((model) => model.model_id)
      .join(", ");
    console.log(`[OpenClaw models.list] count=${models.length}; sample=${sample}`);
    console.log(`[OpenClaw models.list payload] ${JSON.stringify(models, null, 2)}`);
  },
);

async function queryLiveModelsList(): Promise<OpenClawGatewayModel[]> {
  const errors: string[] = [];
  const rpc = createOpenClawGatewayRpc();
  try {
    const models = await new OpenClawModelAdapter({ rpc }).listModels({
      log: { error: (message) => errors.push(message) },
    });
    assert.deepEqual(errors, []);
    return models;
  } finally {
    rpc.close?.();
  }
}
