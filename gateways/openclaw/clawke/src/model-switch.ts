type LogContext = {
  accountId?: string;
  cfg?: unknown;
  log?: {
    info?: (message: string) => void;
    error?: (message: string) => void;
  };
};

type ReplyDispatcherLike = {
  markComplete: () => void;
  waitForIdle: () => Promise<void> | void;
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
        dispatcher: ReplyDispatcherLike;
        replyOptions?: Record<string, unknown>;
        markDispatchIdle?: () => void;
        markRunComplete?: () => void;
      };
      withReplyDispatcher: <T>(input: {
        dispatcher: ReplyDispatcherLike;
        run: () => Promise<T>;
      }) => Promise<T>;
      dispatchReplyFromConfig: (input: Record<string, unknown>) => Promise<unknown> | unknown;
    };
  };
};

export async function switchOpenClawSessionModel(params: {
  ctx: LogContext;
  core: OpenClawRuntimeLike;
  cfg: unknown;
  senderId: string;
  modelOverride: string;
}): Promise<boolean> {
  const { ctx, core, cfg, senderId, modelOverride } = params;
  ctx.log?.info?.(`[ConvConfig] Switching model to: ${modelOverride} for session=${senderId}`);

  try {
    const modelRoute = core.channel.routing.resolveAgentRoute({
      cfg,
      channel: "clawke",
      accountId: ctx.accountId,
      peer: { kind: "direct", id: `clawke:${senderId}` },
    });
    const modelBody = `/model ${modelOverride}`;
    const modelCtx = core.channel.reply.finalizeInboundContext({
      Body: modelBody,
      BodyForAgent: modelBody,
      RawBody: modelBody,
      CommandBody: modelBody,
      BodyForCommands: modelBody,
      From: `clawke:${senderId}`,
      To: `user:${senderId}`,
      SessionKey: modelRoute.sessionKey,
      AccountId: modelRoute.accountId,
      ChatType: "direct",
      SenderName: senderId,
      SenderId: senderId,
      Provider: "clawke",
      Surface: "clawke",
      MessageSid: `model_switch_${Date.now()}`,
      Timestamp: Date.now(),
      OriginatingChannel: "clawke",
      OriginatingTo: `user:${senderId}`,
      CommandAuthorized: true,
    });

    const { dispatcher, replyOptions, markDispatchIdle, markRunComplete } =
      core.channel.reply.createReplyDispatcherWithTyping({
        ctx: modelCtx,
        cfg,
        sessionKey: modelRoute.sessionKey,
        dispatcher: { deliver: async () => {} },
        replyOptions: {},
      });

    try {
      await core.channel.reply.withReplyDispatcher({
        dispatcher,
        run: async () => {
          await core.channel.reply.dispatchReplyFromConfig({
            ctx: modelCtx,
            cfg,
            dispatcher,
            replyOptions: {
              ...replyOptions,
              disableBlockStreaming: true,
            },
          });
        },
      });
    } finally {
      markRunComplete?.();
      markDispatchIdle?.();
    }

    ctx.log?.info?.(`[ConvConfig] ✅ Model switched to: ${modelOverride}`);
    return true;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    ctx.log?.error?.(`[ConvConfig] ❌ Model switch failed: ${message}`);
    return false;
  }
}

export async function ensureOpenClawSessionModel(params: {
  ctx: LogContext;
  core: OpenClawRuntimeLike;
  cfg: unknown;
  senderId: string;
  modelOverride?: string;
  sessionModels: Map<string, string>;
}): Promise<"skipped" | "switched" | "failed"> {
  const { modelOverride, senderId, sessionModels } = params;
  if (!modelOverride || sessionModels.get(senderId) === modelOverride) {
    return "skipped";
  }
  const switched = await switchOpenClawSessionModel({
    ctx: params.ctx,
    core: params.core,
    cfg: params.cfg,
    senderId,
    modelOverride,
  });
  // 模型缓存只在切换成功后更新 — Update model cache only after switch succeeds.
  if (!switched) {
    return "failed";
  }
  sessionModels.set(senderId, modelOverride);
  return "switched";
}
