import { randomUUID } from 'node:crypto';
import type { WebSocket } from 'ws';
import type {
  GatewaySystemSessionRequest,
  GatewaySystemSessionResponse,
  GatewaySystemWireRequest,
  GatewaySystemWireResponse,
} from '../types/gateway-session.js';
import { getUpstreamConnection } from './gateway-listener.js';

type GatewaySystemWebSocket = Pick<WebSocket, 'send' | 'on' | 'removeListener' | 'readyState'>;

export class GatewaySystemError extends Error {
  constructor(
    public code: string,
    message: string,
    public status = 500,
    public details?: unknown,
  ) {
    super(message);
    this.name = 'GatewaySystemError';
  }
}

export async function sendGatewaySystemRequest(
  gatewayId: string,
  systemSessionId: string,
  input: GatewaySystemSessionRequest,
  timeoutMs = input.timeoutMs ?? 30000,
): Promise<GatewaySystemSessionResponse> {
  const ws = getUpstreamConnection(gatewayId);
  if (!ws) {
    throw new GatewaySystemError(
      'gateway_unavailable',
      `No gateway connected for gateway_id=${gatewayId}`,
      503,
    );
  }

  return sendGatewaySystemRequestForTest(ws, gatewayId, systemSessionId, input, timeoutMs);
}

export function sendGatewaySystemRequestForTest(
  ws: GatewaySystemWebSocket,
  gatewayId: string,
  systemSessionId: string,
  input: GatewaySystemSessionRequest,
  timeoutMs = input.timeoutMs ?? 30000,
): Promise<GatewaySystemSessionResponse> {
  const requestId = randomUUID();
  const outbound: GatewaySystemWireRequest = {
    type: 'gateway_system_request',
    request_id: requestId,
    gateway_id: gatewayId,
    system_session_id: systemSessionId,
    purpose: input.purpose,
    prompt: input.prompt,
    response_schema: input.responseSchema,
    metadata: input.metadata,
  };
  const startedAt = Date.now();

  console.log(
    `[GatewaySystem] request sent request=${requestId} purpose=${input.purpose} gateway=${gatewayId} timeoutMs=${timeoutMs}`,
  );

  return new Promise((resolve, reject) => {
    const cleanup = () => {
      clearTimeout(timeout);
      ws.removeListener('message', onMessage);
    };

    const timeout = setTimeout(() => {
      cleanup();
      console.warn(
        `[GatewaySystem] response failed request=${requestId} purpose=${input.purpose} gateway=${gatewayId} code=timeout durationMs=${Date.now() - startedAt}`,
      );
      reject(new GatewaySystemError(
        'gateway_timeout',
        `Gateway system request timeout for ${input.purpose}`,
        504,
      ));
    }, timeoutMs);

    const onMessage = (raw: Buffer) => {
      let response: GatewaySystemWireResponse;
      try {
        response = JSON.parse(raw.toString());
      } catch {
        return;
      }

      if (response.type !== 'gateway_system_response' || response.request_id !== requestId) {
        return;
      }

      cleanup();
      const durationMs = Date.now() - startedAt;
      if (response.error || response.ok === false) {
        const code = response.error_code || response.error || 'gateway_error';
        const message = response.error_message || response.message || 'Gateway system request failed';
        console.warn(
          `[GatewaySystem] response failed request=${requestId} purpose=${input.purpose} gateway=${gatewayId} code=${code} durationMs=${durationMs}`,
        );
        reject(new GatewaySystemError(code, message, 502, response.details));
        return;
      }

      console.log(
        `[GatewaySystem] response ok request=${requestId} purpose=${input.purpose} gateway=${gatewayId} durationMs=${durationMs}`,
      );
      resolve({
        ok: true,
        text: response.text,
        json: response.json,
      });
    };

    ws.on('message', onMessage);
    try {
      ws.send(JSON.stringify(outbound));
    } catch (err) {
      cleanup();
      reject(err);
    }
  });
}
