import { GatewayMessageType } from "./protocol.ts";

export type GatewaySystemRequest = {
  type: "gateway_system_request";
  request_id?: string;
  gateway_id?: string;
  system_session_id?: string;
  purpose?: string;
  prompt?: string;
  response_schema?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
};

export type GatewaySystemRunnerResult = {
  text?: string;
  json?: unknown;
};

export type GatewaySystemRunner = (
  request: GatewaySystemRequest,
) => Promise<GatewaySystemRunnerResult>;

type LogContext = {
  accountId?: string;
  cfg?: unknown;
  log?: {
    info?: (message: string) => void;
    warn?: (message: string) => void;
    error?: (message: string) => void;
  };
};

type ReplyPayloadLike = {
  text?: string;
};

type OpenClawRuntimeLike = {
  channel: {
    routing: {
      resolveAgentRoute: (input: Record<string, unknown>) => {
        sessionKey: string;
        accountId: string;
      };
    };
    reply: {
      finalizeInboundContext: (input: Record<string, unknown>) => Record<string, unknown>;
      createReplyDispatcherWithTyping: (input: Record<string, unknown>) => {
        dispatcher: {
          deliver?: (payload: ReplyPayloadLike) => Promise<void> | void;
          markComplete: () => void;
          waitForIdle: () => Promise<void> | void;
        };
        replyOptions?: Record<string, unknown>;
        markDispatchIdle: () => void;
        markRunComplete: () => void;
      };
      withReplyDispatcher: <T>(input: {
        dispatcher: {
          markComplete: () => void;
          waitForIdle: () => Promise<void> | void;
        };
        run: () => Promise<T>;
      }) => Promise<T>;
      dispatchReplyFromConfig: (input: Record<string, unknown>) => Promise<unknown> | unknown;
    };
  };
};

export async function handleGatewaySystemRequest(
  ctx: LogContext,
  msg: GatewaySystemRequest,
  runner: GatewaySystemRunner,
): Promise<Record<string, unknown>> {
  const requestId = msg.request_id || "";
  const gatewayId = msg.gateway_id || ctx.accountId || "";
  const systemSessionId = msg.system_session_id || `__clawke_system__:${gatewayId}`;
  const purpose = msg.purpose || "system";

  ctx.log?.info?.(
    `[OpenClawGateway] system request received request=${requestId} gateway=${gatewayId} session=${systemSessionId} purpose=${purpose}`,
  );

  try {
    const startedAt = Date.now();
    const result = await runner({
      ...msg,
      gateway_id: gatewayId,
      system_session_id: systemSessionId,
      purpose,
    });
    const json = parseStrictJson(result.json, result.text);
    if (!json) {
      ctx.log?.warn?.(
        `[OpenClawGateway] model response invalid request=${requestId} purpose=${purpose} durationMs=${Date.now() - startedAt} textLength=${result.text?.length ?? 0} textPreview=${formatLogPreview(result.text)}`,
      );
      return {
        type: GatewayMessageType.GatewaySystemResponse,
        request_id: requestId,
        ok: false,
        error_code: "invalid_json",
        error_message: "Gateway system response was not strict JSON.",
      };
    }

    ctx.log?.info?.(
      `[OpenClawGateway] model response received request=${requestId} durationMs=${Date.now() - startedAt} jsonKeys=${Object.keys(json).join(",")}`,
    );
    return {
      type: GatewayMessageType.GatewaySystemResponse,
      request_id: requestId,
      ok: true,
      json,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    ctx.log?.error?.(
      `[OpenClawGateway] system request failed request=${requestId} purpose=${purpose} error=${message}`,
    );
    return {
      type: GatewayMessageType.GatewaySystemResponse,
      request_id: requestId,
      ok: false,
      error_code: "model_error",
      error_message: message,
    };
  }
}

export async function runOpenClawSystemPrompt(
  ctx: LogContext,
  msg: GatewaySystemRequest,
  core: OpenClawRuntimeLike,
): Promise<GatewaySystemRunnerResult> {
  const cfg = ctx.cfg;
  const systemSessionId = msg.system_session_id || `__clawke_system__:${ctx.accountId || msg.gateway_id || ""}`;
  const prompt = msg.prompt || "";
  const messageId = msg.request_id || `system_${Date.now()}`;
  const startedAt = Date.now();

  ctx.log?.info?.(
    `[OpenClawGateway] model request started request=${messageId} provider=openclaw model=primary timeoutMs=default`,
  );

  const route = core.channel.routing.resolveAgentRoute({
    cfg,
    channel: "clawke",
    accountId: ctx.accountId,
    peer: { kind: "direct", id: `clawke:${systemSessionId}` },
  });
  const systemCtx = core.channel.reply.finalizeInboundContext({
    Body: prompt,
    BodyForAgent: prompt,
    RawBody: prompt,
    CommandBody: prompt,
    BodyForCommands: prompt,
    From: `clawke:${systemSessionId}`,
    To: `user:${systemSessionId}`,
    SessionKey: route.sessionKey,
    AccountId: route.accountId,
    ChatType: "direct",
    SenderName: systemSessionId,
    SenderId: systemSessionId,
    Provider: "clawke",
    Surface: "clawke",
    MessageSid: messageId,
    Timestamp: Date.now(),
    OriginatingChannel: "clawke",
    OriginatingTo: `user:${systemSessionId}`,
    CommandAuthorized: true,
  });

  let latestText = "";
  let finalText = "";
  const { dispatcher, replyOptions, markDispatchIdle, markRunComplete } =
    core.channel.reply.createReplyDispatcherWithTyping({
      ctx: systemCtx,
      cfg,
      sessionKey: route.sessionKey,
      dispatcher: {
        deliver: async (payload: ReplyPayloadLike) => {
          if (payload.text) finalText = payload.text;
        },
      },
      replyOptions: {},
    });

  try {
    await core.channel.reply.withReplyDispatcher({
      dispatcher,
      run: async () => {
        await core.channel.reply.dispatchReplyFromConfig({
          ctx: systemCtx,
          cfg,
          dispatcher,
          replyOptions: {
            ...replyOptions,
            disableBlockStreaming: true,
            onPartialReply: (payload: ReplyPayloadLike) => {
              if (payload.text) latestText = payload.text;
            },
          },
        });
      },
    });
  } finally {
    markRunComplete();
    markDispatchIdle();
  }

  const text = finalText || latestText;
  ctx.log?.info?.(
    `[OpenClawGateway] model request completed request=${messageId} durationMs=${Date.now() - startedAt} textLength=${text.length}`,
  );
  return { text };
}

function parseStrictJson(json: unknown, text: string | undefined): Record<string, unknown> | null {
  if (json && typeof json === "object" && !Array.isArray(json)) {
    return json as Record<string, unknown>;
  }
  if (!text) return null;
  const trimmed = unwrapJsonFence(text.trim());
  try {
    const parsed = JSON.parse(trimmed) as unknown;
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

function unwrapJsonFence(text: string): string {
  const fenced = text.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return fenced ? fenced[1].trim() : text;
}

function formatLogPreview(text: string | undefined): string {
  if (!text) return '""';
  const normalized = text.replace(/\s+/g, " ").trim();
  return JSON.stringify(
    normalized.length > 500 ? `${normalized.slice(0, 500)}...` : normalized,
  );
}
