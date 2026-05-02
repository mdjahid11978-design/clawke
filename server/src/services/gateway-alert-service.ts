import type { ConversationStore } from '../store/conversation-store.js';

export type GatewayAlertSeverity = 'info' | 'warning' | 'error';

export interface GatewayAlertInput {
  gatewayId: string;
  severity: GatewayAlertSeverity;
  source: string;
  title: string;
  message: string;
  targetConversationId?: string;
  dedupeKey?: string;
  metadata?: Record<string, unknown>;
}

export function buildGatewayAlertMarkdown(alert: GatewayAlertInput): string {
  const title = alert.title || 'Gateway alert';
  const severity = alert.severity || 'error';
  const source = alert.source || 'gateway';
  const message = alert.message || '';
  return [
    `### Gateway Alert: ${title}`,
    '',
    `**Severity:** ${severity}`,
    `**Source:** ${source}`,
    '',
    message,
  ].join('\n');
}

export function resolveGatewayAlertConversation(
  conversationStore: ConversationStore,
  gatewayId: string,
  targetConversationId?: string,
): string {
  const target = targetConversationId?.trim();
  if (target) {
    const existing = conversationStore.get(target);
    if (existing?.accountId === gatewayId) {
      return existing.id;
    }
  }

  const sameGateway = conversationStore.listByAccount(gatewayId);
  if (sameGateway.length > 0) {
    return sameGateway[0].id;
  }

  return conversationStore.create(gatewayId, 'ai', gatewayId, gatewayId).id;
}
