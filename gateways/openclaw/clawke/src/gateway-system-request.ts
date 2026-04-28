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
  log?: {
    info?: (message: string) => void;
    warn?: (message: string) => void;
    error?: (message: string) => void;
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
        `[OpenClawGateway] model response invalid request=${requestId} purpose=${purpose} durationMs=${Date.now() - startedAt}`,
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

function parseStrictJson(json: unknown, text: string | undefined): Record<string, unknown> | null {
  if (json && typeof json === "object" && !Array.isArray(json)) {
    return json as Record<string, unknown>;
  }
  if (!text) return null;
  try {
    const parsed = JSON.parse(text) as unknown;
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}
