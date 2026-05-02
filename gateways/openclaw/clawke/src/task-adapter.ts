import { randomUUID } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export type OpenClawTaskStatus = "active" | "paused";
export type OpenClawRunStatus = "running" | "success" | "failed" | "cancelled";

export type OpenClawGatewayRpc = {
  (method: string, params?: unknown, options?: { timeoutMs?: number }): Promise<unknown>;
  close?: () => void;
};

export interface OpenClawGatewayRpcOptions {
  gatewayUrl?: string;
  token?: string;
  password?: string;
}

export interface OpenClawTaskAdapterOptions extends OpenClawGatewayRpcOptions {
  rpc?: OpenClawGatewayRpc;
}

export interface OpenClawManagedTask {
  id: string;
  account_id: string;
  agent: string;
  name: string;
  schedule: string;
  schedule_text?: string;
  prompt: string;
  enabled: boolean;
  status: OpenClawTaskStatus;
  skills?: string[];
  deliver?: string;
  created_at: string;
  updated_at: string;
  next_run_at?: string;
  last_run?: OpenClawTaskRun;
}

export interface OpenClawTaskRun {
  id: string;
  task_id: string;
  status: OpenClawRunStatus;
  started_at: string;
  finished_at?: string;
  output_preview?: string;
  error?: string;
}

export interface OpenClawTaskDraft {
  name?: string;
  schedule: string;
  prompt: string;
  enabled?: boolean;
  skills?: string[];
  deliver?: string;
}

export type OpenClawTaskPatch = Partial<OpenClawTaskDraft>;

type CronSchedule =
  | { kind: "cron"; expr: string; tz?: string }
  | { kind: "every"; everyMs: number; tz?: string }
  | { kind: "at"; at: string; tz?: string };

type CronPayload = {
  kind?: string;
  message?: string;
  text?: string;
  model?: string;
  thinking?: string;
  timeoutSeconds?: number;
};

type CronDelivery = {
  mode?: string;
  channel?: string;
  to?: string;
};

type CronJobState = {
  nextRunAtMs?: number;
  lastRunAtMs?: number;
  lastCompletedAtMs?: number;
  lastRunStatus?: string;
  lastStatus?: string;
  lastError?: string;
  lastDurationMs?: number;
};

type CronJob = {
  id: string;
  name?: string;
  message?: string;
  enabled?: boolean;
  status?: "active" | "paused";
  createdAt?: string;
  updatedAt?: string;
  createdAtMs?: number;
  updatedAtMs?: number;
  schedule?: string | CronSchedule;
  scheduleRaw?: CronSchedule;
  payload?: CronPayload;
  delivery?: CronDelivery;
  state?: CronJobState;
  nextRun?: string;
  lastRun?: {
    time?: string;
    success?: boolean;
    error?: string;
    duration?: number;
  };
};

type CronRunEntry = {
  id?: string;
  runId?: string;
  taskId?: string;
  jobId?: string;
  ts?: number;
  action?: string;
  status?: string;
  startedAt?: string;
  finishedAt?: string;
  startedAtMs?: number;
  runAtMs?: number;
  finishedAtMs?: number;
  completedAtMs?: number;
  durationMs?: number;
  nextRunAtMs?: number;
  output?: string;
  summary?: string;
  error?: string;
};

type GatewayConnectOptions = {
  gatewayUrl: string;
  token?: string;
  password?: string;
};

type RpcWebSocket = {
  readyState: number;
  send: (data: string) => void;
  close: () => void;
  on?: (event: string, handler: (...args: any[]) => void) => void;
  onmessage?: ((event: { data: unknown }) => void) | null;
  onerror?: ((event: unknown) => void) | null;
  onclose?: (() => void) | null;
};

type RpcWebSocketCtor = new (url: string) => RpcWebSocket;

const SAFE_SEGMENT = /^[A-Za-z0-9_.:-]+$/;
const DEFAULT_GATEWAY_PORT = 18789;
const DEFAULT_SCHEDULE = "0 9 * * *";
const WS_OPEN = 1;

export class OpenClawTaskAdapter {
  private readonly rpc: OpenClawGatewayRpc;

  constructor(options: OpenClawTaskAdapterOptions = {}) {
    this.rpc = options.rpc ?? createOpenClawGatewayRpc(options);
  }

  async listTasks(accountId: string): Promise<OpenClawManagedTask[]> {
    this.requireSafeSegment(accountId, "accountId");
    const result = await this.rpc("cron.list", { includeDisabled: true });
    return this.extractJobs(result)
      .map((job) => this.toManagedTask(accountId, job))
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  async getTask(accountId: string, taskId: string): Promise<OpenClawManagedTask | null> {
    this.requireSafeSegment(accountId, "accountId");
    this.requireSafeSegment(taskId, "taskId");
    const tasks = await this.listTasks(accountId);
    return tasks.find((task) => task.id === taskId) ?? null;
  }

  async createTask(accountId: string, draft: OpenClawTaskDraft): Promise<OpenClawManagedTask> {
    this.requireSafeSegment(accountId, "accountId");
    const result = await this.rpc("cron.add", this.toCronCreate(draft));
    return this.toManagedTask(accountId, this.requireJob(result));
  }

  async updateTask(
    accountId: string,
    taskId: string,
    patch: OpenClawTaskPatch,
  ): Promise<OpenClawManagedTask | null> {
    this.requireSafeSegment(accountId, "accountId");
    this.requireSafeSegment(taskId, "taskId");
    const result = await this.rpc("cron.update", {
      id: taskId,
      patch: this.toCronPatch(patch),
    });
    return result ? this.toManagedTask(accountId, this.requireJob(result)) : null;
  }

  async deleteTask(accountId: string, taskId: string): Promise<boolean> {
    this.requireSafeSegment(accountId, "accountId");
    this.requireSafeSegment(taskId, "taskId");
    const result = await this.rpc("cron.remove", { id: taskId });
    if (this.isRecord(result) && typeof result.removed === "boolean") {
      return result.removed;
    }
    return true;
  }

  async setEnabled(
    accountId: string,
    taskId: string,
    enabled: boolean,
  ): Promise<OpenClawManagedTask | null> {
    return this.updateTask(accountId, taskId, { enabled });
  }

  async runTask(accountId: string, taskId: string): Promise<OpenClawTaskRun> {
    this.requireSafeSegment(accountId, "accountId");
    this.requireSafeSegment(taskId, "taskId");
    const result = await this.rpc("cron.run", { id: taskId, mode: "force" });
    const runId = this.isRecord(result) && typeof result.runId === "string"
      ? result.runId
      : `manual_${taskId}_${randomUUID()}`;
    return {
      id: runId,
      task_id: taskId,
      status: "running",
      started_at: new Date().toISOString(),
      output_preview: "Manual run queued",
    };
  }

  async listRuns(accountId: string, taskId: string): Promise<OpenClawTaskRun[]> {
    this.requireSafeSegment(accountId, "accountId");
    this.requireSafeSegment(taskId, "taskId");
    const result = await this.rpc("cron.runs", { id: taskId, limit: 50 });
    return this.extractRuns(result)
      .map((entry, index) => this.toRun(taskId, entry, index))
      .sort((a, b) => b.started_at.localeCompare(a.started_at));
  }

  async getOutput(accountId: string, taskId: string, runId: string): Promise<string | null> {
    this.requireSafeSegment(accountId, "accountId");
    this.requireSafeSegment(taskId, "taskId");
    this.requireSafeSegment(runId, "runId");
    const result = await this.rpc("cron.runs", { id: taskId, limit: 50 });
    const entry = this.extractRuns(result).find(
      (item, index) => this.runId(taskId, item, index) === runId,
    );
    if (!entry) return null;
    return entry.output ?? entry.summary ?? entry.error ?? JSON.stringify(entry, null, 2);
  }

  private toCronCreate(draft: OpenClawTaskDraft): Record<string, unknown> {
    return {
      name: this.normalizeText(draft.name, "Untitled task"),
      schedule: this.scheduleFromString(draft.schedule),
      payload: { kind: "agentTurn", message: draft.prompt ?? "" },
      enabled: draft.enabled ?? true,
      wakeMode: "next-heartbeat",
      sessionTarget: "isolated",
      delivery: this.deliveryFromText(draft.deliver),
    };
  }

  private toCronPatch(patch: OpenClawTaskPatch): Record<string, unknown> {
    const next: Record<string, unknown> = {};
    if (patch.name !== undefined) next.name = this.normalizeText(patch.name, "Untitled task");
    if (patch.schedule !== undefined) next.schedule = this.scheduleFromString(patch.schedule);
    if (patch.prompt !== undefined) next.payload = { kind: "agentTurn", message: patch.prompt };
    if (patch.enabled !== undefined) next.enabled = patch.enabled;
    if (patch.deliver !== undefined) next.delivery = this.deliveryFromText(patch.deliver);
    return next;
  }

  private toManagedTask(accountId: string, job: CronJob): OpenClawManagedTask {
    const schedule = job.scheduleRaw ?? job.schedule;
    const createdAt = this.toIso(job.createdAtMs ?? job.createdAt) ?? new Date(0).toISOString();
    const updatedAt = this.toIso(job.updatedAtMs ?? job.updatedAt) ?? createdAt;
    const enabled = typeof job.enabled === "boolean" ? job.enabled : job.status !== "paused";
    const lastRun = this.lastRunFromJob(job);
    return {
      id: job.id,
      account_id: accountId,
      agent: "openclaw",
      name: job.name?.trim() || job.id,
      schedule: this.scheduleValue(schedule),
      schedule_text: this.scheduleText(schedule),
      prompt: this.promptValue(job),
      enabled,
      status: enabled ? "active" : "paused",
      deliver: this.deliveryText(job.delivery),
      created_at: createdAt,
      updated_at: updatedAt,
      next_run_at: this.toIso(job.state?.nextRunAtMs ?? job.nextRun),
      last_run: lastRun,
    };
  }

  private lastRunFromJob(job: CronJob): OpenClawTaskRun | undefined {
    if (job.lastRun?.time) {
      return {
        id: `last_${job.id}_${job.lastRun.time}`,
        task_id: job.id,
        status: job.lastRun.success ? "success" : "failed",
        started_at: this.toIso(job.lastRun.time) ?? job.lastRun.time,
        output_preview: job.lastRun.error,
        error: job.lastRun.error,
      };
    }

    const state = job.state;
    if (!state?.lastRunAtMs) return undefined;
    const startedAt = this.toIso(state.lastRunAtMs);
    if (!startedAt) return undefined;
    const finishedAt = this.toIso(state.lastCompletedAtMs) ?? startedAt;
    return {
      id: `last_${job.id}_${state.lastRunAtMs ?? "unknown"}`,
      task_id: job.id,
      status: this.runStatus(state.lastRunStatus ?? state.lastStatus),
      started_at: startedAt,
      finished_at: finishedAt,
      output_preview: state.lastError,
      error: state.lastError,
    };
  }

  private toRun(taskId: string, entry: CronRunEntry, index: number): OpenClawTaskRun {
    const startedAtMs = entry.startedAtMs ?? entry.runAtMs ?? entry.ts;
    const finishedAtMs =
      entry.finishedAtMs ??
      entry.completedAtMs ??
      (typeof startedAtMs === "number" && typeof entry.durationMs === "number"
        ? startedAtMs + entry.durationMs
        : undefined);
    const startedAt =
      this.toIso(startedAtMs ?? entry.startedAt) ??
      this.toIso(entry.finishedAtMs ?? entry.completedAtMs ?? entry.finishedAt) ??
      "";
    return {
      id: this.runId(taskId, entry, index),
      task_id: taskId,
      status: this.runStatus(entry.status),
      started_at: startedAt,
      finished_at: this.toIso(finishedAtMs ?? entry.finishedAt),
      output_preview: entry.output ?? entry.summary ?? entry.error,
      error: entry.error,
    };
  }

  private runId(taskId: string, entry: CronRunEntry, index: number): string {
    return entry.id ?? entry.runId ?? `${taskId}_${entry.startedAtMs ?? entry.runAtMs ?? entry.ts ?? entry.startedAt ?? index}`;
  }

  private scheduleFromString(value?: string): CronSchedule {
    const text = this.normalizeText(value, DEFAULT_SCHEDULE);
    if (text.startsWith("every:")) {
      const everyMs = Number(text.slice("every:".length));
      return { kind: "every", everyMs: Number.isFinite(everyMs) ? everyMs : 0 };
    }
    if (text.startsWith("at:")) {
      return { kind: "at", at: text.slice("at:".length).trim() };
    }
    return { kind: "cron", expr: text };
  }

  private scheduleValue(schedule?: string | CronSchedule): string {
    if (!schedule) return "";
    if (typeof schedule === "string") return schedule;
    if (schedule.kind === "cron") return schedule.expr;
    if (schedule.kind === "every") return `every:${schedule.everyMs}`;
    return schedule.at;
  }

  private scheduleText(schedule?: string | CronSchedule): string | undefined {
    if (!schedule) return undefined;
    if (typeof schedule === "string") return this.scheduleText({ kind: "cron", expr: schedule });
    if (schedule.kind === "cron") {
      const daily = schedule.expr.match(/^(\d{1,2})\s+(\d{1,2})\s+\*\s+\*\s+\*$/);
      if (daily) {
        const minute = daily[1].padStart(2, "0");
        const hour = daily[2].padStart(2, "0");
        return [`每天 ${hour}:${minute}`, schedule.tz].filter(Boolean).join(" ");
      }
      return [schedule.expr, schedule.tz].filter(Boolean).join(" ");
    }
    if (schedule.kind === "every") {
      return `每 ${Math.round(schedule.everyMs / 1000)} 秒`;
    }
    return [schedule.at, schedule.tz].filter(Boolean).join(" ");
  }

  private promptValue(job: CronJob): string {
    return job.payload?.message ?? job.payload?.text ?? job.message ?? "";
  }

  private deliveryFromText(value?: string): CronDelivery {
    const to = value?.trim();
    return to ? { mode: "announce", channel: "clawke", to } : { mode: "none" };
  }

  private deliveryText(delivery?: CronDelivery): string | undefined {
    return delivery?.to ?? delivery?.channel ?? delivery?.mode;
  }

  private runStatus(value?: string): OpenClawRunStatus {
    if (value === "ok" || value === "success") return "success";
    if (value === "error" || value === "failed") return "failed";
    if (value === "skipped" || value === "cancelled") return "cancelled";
    return "running";
  }

  private extractJobs(value: unknown): CronJob[] {
    if (Array.isArray(value)) return value.filter((item): item is CronJob => this.isCronJob(item));
    if (!this.isRecord(value)) return [];
    const candidates = [value.jobs, value.cronJobs, value.cron, value.items, value.list];
    for (const candidate of candidates) {
      if (Array.isArray(candidate)) {
        return candidate.filter((item): item is CronJob => this.isCronJob(item));
      }
    }
    return [];
  }

  private extractRuns(value: unknown): CronRunEntry[] {
    if (Array.isArray(value)) return value.filter((item): item is CronRunEntry => this.isRecord(item));
    if (!this.isRecord(value)) return [];
    const candidates = [value.entries, value.runs, value.items, value.list];
    for (const candidate of candidates) {
      if (Array.isArray(candidate)) {
        return candidate.filter((item): item is CronRunEntry => this.isRecord(item));
      }
    }
    return [];
  }

  private requireJob(value: unknown): CronJob {
    if (this.isCronJob(value)) return value;
    if (this.isRecord(value) && this.isCronJob(value.job)) return value.job;
    throw new Error("Invalid cron job response");
  }

  private isCronJob(value: unknown): value is CronJob {
    return this.isRecord(value) && typeof value.id === "string";
  }

  private isRecord(value: unknown): value is Record<string, unknown> {
    return Boolean(value && typeof value === "object");
  }

  private normalizeText(value: string | undefined, fallback: string): string {
    const text = value?.trim();
    return text ? text : fallback;
  }

  private toIso(value: number | string | undefined): string | undefined {
    if (typeof value === "number" && Number.isFinite(value)) {
      return new Date(value).toISOString();
    }
    if (typeof value === "string" && value.trim()) {
      const timestamp = Date.parse(value);
      return Number.isFinite(timestamp) ? new Date(timestamp).toISOString() : value;
    }
    return undefined;
  }

  private requireSafeSegment(value: string, label: string): void {
    if (!SAFE_SEGMENT.test(value)) {
      throw new Error(`Invalid ${label}`);
    }
  }
}

export function createOpenClawGatewayRpc(options: OpenClawGatewayRpcOptions = {}): OpenClawGatewayRpc {
  const client = new OpenClawGatewayRpcClient(resolveGatewayConnectOptions(options));
  const rpc: OpenClawGatewayRpc = (method, params, rpcOptions) => client.call(method, params, rpcOptions);
  rpc.close = () => client.close();
  return rpc;
}

function resolveGatewayConnectOptions(options: OpenClawGatewayRpcOptions): GatewayConnectOptions {
  const cfg = safeLoadConfig();
  const gateway = isRecord(cfg.gateway) ? cfg.gateway : {};
  const auth = isRecord(gateway.auth) ? gateway.auth : {};
  const port = Number(process.env.OPENCLAW_GATEWAY_PORT ?? gateway.port ?? DEFAULT_GATEWAY_PORT);
  const tls = isRecord(gateway.tls) && gateway.tls.enabled === true;
  const token = options.token ?? stringSecret(auth.token) ?? process.env.OPENCLAW_GATEWAY_TOKEN;
  const password = options.password ?? stringSecret(auth.password) ?? process.env.OPENCLAW_GATEWAY_PASSWORD;
  const mode = typeof auth.mode === "string" ? auth.mode : (password ? "password" : token ? "token" : "none");
  return {
    gatewayUrl: options.gatewayUrl ?? `${tls ? "wss" : "ws"}://127.0.0.1:${port}`,
    token: mode === "token" ? token : undefined,
    password: mode === "password" ? password : undefined,
  };
}

class OpenClawGatewayRpcClient {
  private ws: RpcWebSocket | null = null;
  private connectPromise: Promise<void> | null = null;
  private authenticated = false;
  private requestId = 0;
  private readonly options: GatewayConnectOptions;
  private readonly pending = new Map<
    string,
    {
      resolve: (value: unknown) => void;
      reject: (error: Error) => void;
      timer: NodeJS.Timeout;
    }
  >();

  constructor(options: GatewayConnectOptions) {
    this.options = options;
  }

  async call(method: string, params?: unknown, options?: { timeoutMs?: number }): Promise<unknown> {
    await this.ensureConnected();
    const ws = this.ws;
    if (!ws || ws.readyState !== WS_OPEN) {
      throw new Error("OpenClaw Gateway RPC is not connected");
    }
    const id = String(++this.requestId);
    const timeoutMs = options?.timeoutMs ?? 30_000;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Request timeout: ${method}`));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      ws.send(JSON.stringify({ type: "req", id, method, params }));
    });
  }

  close(): void {
    this.rejectPending(new Error("OpenClaw Gateway RPC client closed"));
    this.authenticated = false;
    this.connectPromise = null;
    try {
      this.ws?.close();
    } catch {
      // WebSocket 关闭是尽力而为 — WebSocket shutdown is best-effort.
    }
    this.ws = null;
  }

  private ensureConnected(): Promise<void> {
    if (this.ws?.readyState === WS_OPEN && this.authenticated) {
      return Promise.resolve();
    }
    if (this.connectPromise) return this.connectPromise;

    this.connectPromise = this.openConnection().catch((error) => {
      this.connectPromise = null;
      throw error;
    });
    return this.connectPromise;
  }

  private async openConnection(): Promise<void> {
    const WebSocketCtor = await loadWebSocketCtor();
    return new Promise((resolve, reject) => {
      const ws = new WebSocketCtor(this.options.gatewayUrl);
      this.ws = ws;

      const timer = setTimeout(() => {
        ws.close();
        reject(new Error("OpenClaw Gateway RPC connect timeout"));
      }, 15_000);

      const finish = () => {
        clearTimeout(timer);
        this.authenticated = true;
        resolve();
      };

      const onMessage = (data: unknown) => {
        this.handleMessage(messageDataToString(data), finish, reject);
      };
      const onError = (error: unknown) => {
        clearTimeout(timer);
        reject(error instanceof Error ? error : new Error(String(error)));
      };
      const onClose = () => {
        clearTimeout(timer);
        this.authenticated = false;
        this.ws = null;
        this.connectPromise = null;
        this.rejectPending(new Error("OpenClaw Gateway RPC connection closed"));
      };

      if (typeof ws.on === "function") {
        ws.on("message", onMessage);
        ws.on("error", onError);
        ws.on("close", onClose);
      } else {
        ws.onmessage = (event) => onMessage(event.data);
        ws.onerror = onError;
        ws.onclose = onClose;
      }
    });
  }

  private handleMessage(data: string, onHelloOk: () => void, onConnectError: (error: Error) => void): void {
    let message: unknown;
    try {
      message = JSON.parse(data);
    } catch {
      return;
    }
    if (!isRecord(message)) return;

    if (message.type === "event" && message.event === "connect.challenge") {
      this.sendConnect();
      return;
    }

    if (message.type !== "res") return;
    const id = typeof message.id === "string" ? message.id : String(message.id ?? "");

    if (!this.authenticated && message.ok === true && isRecord(message.payload) && message.payload.type === "hello-ok") {
      onHelloOk();
      return;
    }

    const pending = this.pending.get(id);
    if (pending) {
      clearTimeout(pending.timer);
      this.pending.delete(id);
      if (message.ok === true) {
        pending.resolve(message.payload);
      } else {
        pending.reject(new Error(this.errorMessage(message.error)));
      }
      return;
    }

    if (!this.authenticated && message.ok === false) {
      onConnectError(new Error(this.errorMessage(message.error)));
    }
  }

  private sendConnect(): void {
    const id = String(++this.requestId);
    const auth = this.options.token
      ? { token: this.options.token }
      : this.options.password
        ? { password: this.options.password }
        : undefined;
    this.ws?.send(
      JSON.stringify({
        type: "req",
        id,
        method: "connect",
        params: {
          minProtocol: 3,
          maxProtocol: 3,
          role: "operator",
          scopes: ["operator.read", "operator.write", "operator.admin", "operator.approvals"],
          client: {
            id: "gateway-client",
            displayName: "Clawke Plugin",
            version: "1.0.2",
            platform: "openclaw-plugin",
            mode: "backend",
          },
          caps: ["tool-events", "thinking-events"],
          auth,
        },
      }),
    );
  }

  private rejectPending(error: Error): void {
    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timer);
      pending.reject(error);
      this.pending.delete(id);
    }
  }

  private errorMessage(value: unknown): string {
    if (isRecord(value) && typeof value.message === "string") return value.message;
    return "OpenClaw Gateway RPC request failed";
  }
}

function safeLoadConfig(): Record<string, unknown> {
  try {
    const stateDir = process.env.OPENCLAW_STATE_DIR || join(homedir(), ".openclaw");
    const configPath = process.env.OPENCLAW_CONFIG_PATH || join(stateDir, "openclaw.json");
    if (!existsSync(configPath)) return {};
    const loaded = JSON.parse(stripJsonc(readFileSync(configPath, "utf8")));
    return isRecord(loaded) ? loaded : {};
  } catch {
    return {};
  }
}

function stripJsonc(input: string): string {
  let output = "";
  let inString = false;
  let escaped = false;
  let inLineComment = false;
  let inBlockComment = false;

  for (let i = 0; i < input.length; i += 1) {
    const ch = input[i];
    const next = input[i + 1];

    if (inLineComment) {
      if (ch === "\n" || ch === "\r") {
        inLineComment = false;
        output += ch;
      }
      continue;
    }

    if (inBlockComment) {
      if (ch === "*" && next === "/") {
        inBlockComment = false;
        i += 1;
      } else if (ch === "\n" || ch === "\r") {
        output += ch;
      }
      continue;
    }

    if (inString) {
      output += ch;
      if (escaped) {
        escaped = false;
      } else if (ch === "\\") {
        escaped = true;
      } else if (ch === "\"") {
        inString = false;
      }
      continue;
    }

    if (ch === "\"") {
      inString = true;
      output += ch;
      continue;
    }

    if (ch === "/" && next === "/") {
      inLineComment = true;
      i += 1;
      continue;
    }

    if (ch === "/" && next === "*") {
      inBlockComment = true;
      i += 1;
      continue;
    }

    output += ch;
  }

  return stripTrailingCommas(output);
}

function stripTrailingCommas(input: string): string {
  let output = "";
  let inString = false;
  let escaped = false;

  for (let i = 0; i < input.length; i += 1) {
    const ch = input[i];

    if (inString) {
      output += ch;
      if (escaped) {
        escaped = false;
      } else if (ch === "\\") {
        escaped = true;
      } else if (ch === "\"") {
        inString = false;
      }
      continue;
    }

    if (ch === "\"") {
      inString = true;
      output += ch;
      continue;
    }

    if (ch === ",") {
      let j = i + 1;
      while (j < input.length && /\s/.test(input[j])) j += 1;
      if (input[j] === "}" || input[j] === "]") continue;
    }

    output += ch;
  }

  return output;
}

function stringSecret(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object");
}

async function loadWebSocketCtor(): Promise<RpcWebSocketCtor> {
  try {
    const module = await import("ws");
    return module.default as unknown as RpcWebSocketCtor;
  } catch {
    // 插件依赖不可用时回退到运行时 WebSocket — Fall back to the runtime WebSocket when the plugin dependency is unavailable.
  }
  if (typeof globalThis.WebSocket === "function") {
    return globalThis.WebSocket as unknown as RpcWebSocketCtor;
  }
  throw new Error("WebSocket implementation is unavailable");
}

function messageDataToString(data: unknown): string {
  if (typeof data === "string") return data;
  if (data instanceof ArrayBuffer) return new TextDecoder().decode(data);
  if (ArrayBuffer.isView(data)) {
    return new TextDecoder().decode(data);
  }
  return String(data);
}
