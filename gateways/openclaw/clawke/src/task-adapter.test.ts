import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { OpenClawTaskAdapter, type OpenClawGatewayRpc } from "./task-adapter.ts";

type RpcCall = {
  method: string;
  params?: unknown;
};

function createAdapter(handler: OpenClawGatewayRpc) {
  const calls: RpcCall[] = [];
  const rpc: OpenClawGatewayRpc = async (method, params, options) => {
    calls.push({ method, params });
    return handler(method, params, options);
  };
  return { adapter: new OpenClawTaskAdapter({ rpc }), calls };
}

test("OpenClawTaskAdapter lists agent cron jobs through OpenClaw Gateway RPC", async () => {
  const { adapter, calls } = createAdapter(async (method, params) => {
    assert.equal(method, "cron.list");
    assert.deepEqual(params, { includeDisabled: true });
    return {
      jobs: [
        {
          id: "job_daily",
          name: "Daily report",
          enabled: true,
          createdAtMs: 1776395104970,
          updatedAtMs: 1777071981245,
          schedule: { kind: "cron", expr: "0 7 * * *", tz: "Asia/Shanghai" },
          payload: { kind: "agentTurn", message: "Create daily report" },
          delivery: { mode: "announce", channel: "clawke", to: "conv_1" },
          state: {
            nextRunAtMs: 1777158000000,
            lastRunAtMs: 1777071600006,
            lastRunStatus: "ok",
          },
        },
      ],
    };
  });

  const listed = await adapter.listTasks("OpenClaw");

  assert.equal(calls.length, 1);
  assert.equal(listed.length, 1);
  assert.equal(listed[0].id, "job_daily");
  assert.equal(listed[0].account_id, "OpenClaw");
  assert.equal(listed[0].name, "Daily report");
  assert.equal(listed[0].schedule, "0 7 * * *");
  assert.equal(listed[0].schedule_text, "每天 07:00 Asia/Shanghai");
  assert.equal(listed[0].prompt, "Create daily report");
  assert.equal(listed[0].enabled, true);
  assert.equal(listed[0].next_run_at, "2026-04-25T23:00:00.000Z");
  assert.equal(listed[0].last_run?.status, "success");
});

test("OpenClawTaskAdapter mutates tasks through OpenClaw cron RPC methods", async () => {
  let job = {
    id: "job_new",
    name: "Morning check",
    enabled: true,
    createdAtMs: 1776395104970,
    updatedAtMs: 1776395104970,
    schedule: { kind: "cron", expr: "0 9 * * *" },
    payload: { kind: "agentTurn", message: "Summarize overnight changes" },
    delivery: { mode: "none" },
    state: {},
  };

  const { adapter, calls } = createAdapter(async (method, params) => {
    if (method === "cron.add") {
      assert.deepEqual(params, {
        name: "Morning check",
        schedule: { kind: "cron", expr: "0 9 * * *" },
        payload: { kind: "agentTurn", message: "Summarize overnight changes" },
        enabled: true,
        wakeMode: "next-heartbeat",
        sessionTarget: "isolated",
        delivery: { mode: "none" },
      });
      return job;
    }
    if (method === "cron.list") {
      return { jobs: [job] };
    }
    if (method === "cron.update") {
      const patch = (params as { patch: Record<string, unknown> }).patch;
      job = {
        ...job,
        ...patch,
        payload: (patch.payload as typeof job.payload | undefined) ?? job.payload,
        schedule: (patch.schedule as typeof job.schedule | undefined) ?? job.schedule,
        updatedAtMs: 1776395200000,
      };
      return job;
    }
    if (method === "cron.remove") {
      assert.deepEqual(params, { id: "job_new" });
      return { removed: true };
    }
    if (method === "cron.run") {
      assert.deepEqual(params, { id: "job_new", mode: "force" });
      return { runId: "run_1", queued: true };
    }
    if (method === "cron.runs") {
      assert.deepEqual(params, { id: "job_new", limit: 50 });
      return {
        entries: [
          {
            runId: "run_1",
            jobId: "job_new",
            status: "ok",
            startedAtMs: 1776395300000,
            completedAtMs: 1776395310000,
            summary: "done",
          },
        ],
      };
    }
    throw new Error(`Unexpected method: ${method}`);
  });

  const created = await adapter.createTask("acct_1", {
    name: "Morning check",
    schedule: "0 9 * * *",
    prompt: "Summarize overnight changes",
    enabled: true,
  });
  assert.equal(created.id, "job_new");
  assert.equal(created.status, "active");

  const fetched = await adapter.getTask("acct_1", "job_new");
  assert.equal(fetched?.id, "job_new");

  const updated = await adapter.updateTask("acct_1", "job_new", {
    name: "Updated check",
    schedule: "30 8 * * *",
    prompt: "Updated prompt",
    enabled: false,
  });
  assert.equal(updated?.name, "Updated check");
  assert.equal(updated?.schedule, "30 8 * * *");
  assert.equal(updated?.prompt, "Updated prompt");
  assert.equal(updated?.status, "paused");

  const enabled = await adapter.setEnabled("acct_1", "job_new", true);
  assert.equal(enabled?.enabled, true);

  const run = await adapter.runTask("acct_1", "job_new");
  assert.equal(run.id, "run_1");
  assert.equal(run.task_id, "job_new");
  assert.equal(run.status, "running");

  const runs = await adapter.listRuns("acct_1", "job_new");
  assert.equal(runs.length, 1);
  assert.equal(runs[0].id, "run_1");
  assert.equal(runs[0].status, "success");

  const output = await adapter.getOutput("acct_1", "job_new", "run_1");
  assert.equal(output, "done");

  await assert.rejects(
    () => adapter.getTask("acct_1", "../escape"),
    /Invalid taskId/,
  );
  await assert.rejects(
    () => adapter.getOutput("acct_1", "job_new", "../escape"),
    /Invalid runId/,
  );

  assert.equal(await adapter.deleteTask("acct_1", "job_new"), true);
  assert.equal(calls.some((call) => call.method === "cron.add"), true);
  assert.equal(calls.some((call) => call.method === "cron.update"), true);
  assert.equal(calls.some((call) => call.method === "cron.remove"), true);
  assert.equal(calls.some((call) => call.method === "cron.run"), true);
});

test("OpenClawTaskAdapter maps cron run log timestamps without epoch fallback", async () => {
  const logTimestamp = 1777071981245;
  const { adapter } = createAdapter(async (method) => {
    assert.equal(method, "cron.runs");
    return {
      entries: [
        {
          ts: logTimestamp,
          jobId: "job_new",
          action: "finished",
          status: "ok",
          summary: "done",
        },
      ],
    };
  });

  const runs = await adapter.listRuns("acct_1", "job_new");

  assert.equal(runs.length, 1);
  assert.equal(runs[0].started_at, new Date(logTimestamp).toISOString());
  assert.notEqual(runs[0].started_at, "1970-01-01T00:00:00.000Z");
});

test("OpenClawTaskAdapter default RPC connects to the OpenClaw gateway origin endpoint", async () => {
  const originalWebSocket = globalThis.WebSocket;
  const originalPort = process.env.OPENCLAW_GATEWAY_PORT;
  const originalToken = process.env.OPENCLAW_GATEWAY_TOKEN;
  const originalPassword = process.env.OPENCLAW_GATEWAY_PASSWORD;
  const originalConfigPath = process.env.OPENCLAW_CONFIG_PATH;
  const tempDir = mkdtempSync(join(tmpdir(), "clawke-openclaw-config-"));
  const configPath = join(tempDir, "openclaw.json");
  let capturedUrl = "";
  let connectParams: Record<string, unknown> | undefined;

  class FakeWebSocket {
    readyState = 1;
    onmessage?: (event: { data: string }) => void;
    onerror?: (event: unknown) => void;
    onclose?: () => void;

    constructor(url: string) {
      capturedUrl = url;
      queueMicrotask(() => {
        this.onmessage?.({
          data: JSON.stringify({
            type: "event",
            event: "connect.challenge",
            payload: { nonce: "nonce_1" },
          }),
        });
      });
    }

    send(data: string) {
      const message = JSON.parse(data);
      if (message.method === "connect") {
        connectParams = message.params;
        queueMicrotask(() => {
          this.onmessage?.({
            data: JSON.stringify({
              type: "res",
              id: message.id,
              ok: true,
              payload: { type: "hello-ok" },
            }),
          });
        });
        return;
      }
      if (message.method === "cron.list") {
        queueMicrotask(() => {
          this.onmessage?.({
            data: JSON.stringify({
              type: "res",
              id: message.id,
              ok: true,
              payload: { jobs: [] },
            }),
          });
        });
      }
    }

    close() {
      this.onclose?.();
    }
  }

  try {
    delete process.env.OPENCLAW_GATEWAY_PORT;
    delete process.env.OPENCLAW_GATEWAY_TOKEN;
    delete process.env.OPENCLAW_GATEWAY_PASSWORD;
    process.env.OPENCLAW_CONFIG_PATH = configPath;
    writeFileSync(
      configPath,
      `{
        // 本地配置允许注释 — Local config allows comments.
        "gateway": {
          "port": 18789,
          "auth": {
            "mode": "token",
            "token": "test-token", // token 可带尾注释 — Token may have trailing comments.
          },
        },
      }`,
      "utf8",
    );
    Object.defineProperty(globalThis, "WebSocket", {
      configurable: true,
      value: FakeWebSocket,
    });

    const tasks = await new OpenClawTaskAdapter().listTasks("OpenClaw");

    assert.deepEqual(tasks, []);
    assert.equal(capturedUrl, "ws://127.0.0.1:18789");
    assert.equal(connectParams?.nonce, undefined);
    assert.deepEqual(connectParams?.client, {
      id: "gateway-client",
      displayName: "Clawke Plugin",
      version: "1.0.2",
      platform: "openclaw-plugin",
      mode: "backend",
    });
    assert.deepEqual(connectParams?.auth, { token: "test-token" });
  } finally {
    if (originalPort === undefined) {
      delete process.env.OPENCLAW_GATEWAY_PORT;
    } else {
      process.env.OPENCLAW_GATEWAY_PORT = originalPort;
    }
    if (originalToken === undefined) {
      delete process.env.OPENCLAW_GATEWAY_TOKEN;
    } else {
      process.env.OPENCLAW_GATEWAY_TOKEN = originalToken;
    }
    if (originalPassword === undefined) {
      delete process.env.OPENCLAW_GATEWAY_PASSWORD;
    } else {
      process.env.OPENCLAW_GATEWAY_PASSWORD = originalPassword;
    }
    if (originalConfigPath === undefined) {
      delete process.env.OPENCLAW_CONFIG_PATH;
    } else {
      process.env.OPENCLAW_CONFIG_PATH = originalConfigPath;
    }
    rmSync(tempDir, { recursive: true, force: true });
    Object.defineProperty(globalThis, "WebSocket", {
      configurable: true,
      value: originalWebSocket,
    });
  }
});
