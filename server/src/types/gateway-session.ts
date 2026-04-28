export type GatewaySessionKind = 'system' | 'user';

export interface GatewaySessionRequest {
  purpose: string;
  prompt: string;
  responseSchema?: Record<string, unknown>;
  timeoutMs?: number;
  metadata?: Record<string, unknown>;
}

export interface GatewaySystemSessionRequest extends GatewaySessionRequest {
  internal: true;
}

export interface GatewayUserSessionRequest extends GatewaySessionRequest {
  conversationId: string;
}

export interface GatewaySessionResponse {
  ok: boolean;
  text?: string;
  json?: unknown;
  errorCode?: string;
  errorMessage?: string;
}

export interface GatewaySystemSessionResponse extends GatewaySessionResponse {}

export interface GatewayUserSessionResponse extends GatewaySessionResponse {}

export interface GatewaySession {
  gatewayId: string;
  sessionId: string;
  kind: GatewaySessionKind;
  request(input: GatewaySessionRequest): Promise<GatewaySessionResponse>;
}

export interface GatewaySystemSession extends GatewaySession {
  kind: 'system';
  request(input: GatewaySystemSessionRequest): Promise<GatewaySystemSessionResponse>;
}

export interface GatewayUserSession extends GatewaySession {
  kind: 'user';
  conversationId: string;
  request(input: GatewayUserSessionRequest): Promise<GatewayUserSessionResponse>;
}

export interface GatewaySystemWireRequest {
  type: 'gateway_system_request';
  request_id?: string;
  gateway_id: string;
  system_session_id: string;
  purpose: string;
  prompt: string;
  response_schema?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}

export interface GatewaySystemWireResponse {
  type: 'gateway_system_response';
  request_id: string;
  ok?: boolean;
  text?: string;
  json?: unknown;
  error_code?: string;
  error_message?: string;
  error?: string;
  message?: string;
  details?: unknown;
}
