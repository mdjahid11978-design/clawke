import type {
  GatewaySystemSession,
  GatewaySystemSessionRequest,
  GatewaySystemSessionResponse,
} from '../types/gateway-session.js';
import { sendGatewaySystemRequest } from '../upstream/gateway-system-client.js';

export type GatewaySystemRequester = (
  gatewayId: string,
  systemSessionId: string,
  input: GatewaySystemSessionRequest,
) => Promise<GatewaySystemSessionResponse>;

export class GatewayManageService {
  private readonly requestSystem: GatewaySystemRequester;

  constructor(options: { requestSystem?: GatewaySystemRequester } = {}) {
    this.requestSystem = options.requestSystem ?? sendGatewaySystemRequest;
  }

  getSystemSession(gatewayId: string): GatewaySystemSession {
    const normalizedGatewayId = gatewayId.trim();
    const sessionId = `__clawke_system__:${normalizedGatewayId}`;

    console.log(`[GatewayManage] system session resolved gateway=${normalizedGatewayId} session=${sessionId}`);

    return {
      gatewayId: normalizedGatewayId,
      sessionId,
      kind: 'system',
      request: (input: GatewaySystemSessionRequest) => this.requestSystem(
        normalizedGatewayId,
        sessionId,
        input,
      ),
    };
  }
}
