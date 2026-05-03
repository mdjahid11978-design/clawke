import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/providers/database_providers.dart';

/// 会话列表 — Drift .watch() 驱动
final conversationListProvider = StreamProvider<List<Conversation>>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return repo.watchAll();
});

/// 当前选中的会话 ID
final selectedConversationIdProvider = StateProvider<String?>((ref) => null);

final activeChatConversationIdProvider = StateProvider<String?>((ref) => null);

final totalUnseenCountProvider = Provider<int>((ref) {
  final conversations = ref.watch(conversationListProvider).valueOrNull;
  if (conversations == null) return 0;
  return conversations.fold<int>(
    0,
    (total, conversation) => total + conversation.unseenCount,
  );
});

final systemBadgeCountProvider = Provider<int>((ref) {
  final conversations = ref.watch(conversationListProvider).valueOrNull;
  if (conversations == null) return 0;
  return conversations.fold<int>(
    0,
    (total, conversation) =>
        conversation.isMuted == 0 ? total + conversation.unseenCount : total,
  );
});

/// 当前选中的会话对象（从 conversationList + selectedId 派生）
final selectedConversationProvider = Provider<Conversation?>((ref) {
  final convId = ref.watch(selectedConversationIdProvider);
  if (convId == null) return null;
  final conversations = ref.watch(conversationListProvider).valueOrNull;
  return conversations?.where((c) => c.conversationId == convId).firstOrNull;
});

class ConversationGatewayIssue {
  final String key;
  final String gatewayId;
  final String message;
  final String tooltip;
  final GatewayConnectionStatus status;

  const ConversationGatewayIssue({
    required this.key,
    required this.gatewayId,
    required this.message,
    required this.tooltip,
    required this.status,
  });
}

ConversationGatewayIssue? conversationGatewayIssue(
  Conversation conversation,
  List<GatewayInfo> gateways,
) {
  final gatewayId = conversation.accountId.trim();
  if (gatewayId.isEmpty) return null;

  final gateway = gateways
      .where((item) => item.gatewayId == gatewayId)
      .firstOrNull;
  if (gateway == null || gateway.status == GatewayConnectionStatus.online) {
    return null;
  }

  final displayName = gateway.displayName.trim().isEmpty
      ? gateway.gatewayId
      : gateway.displayName.trim();

  if (gateway.status == GatewayConnectionStatus.error) {
    final detail = gateway.lastErrorMessage?.trim();
    final message = detail == null || detail.isEmpty
        ? '网关异常：$displayName'
        : detail;
    return ConversationGatewayIssue(
      key: '${conversation.conversationId}:${gateway.gatewayId}:error:$message',
      gatewayId: gateway.gatewayId,
      message: message,
      tooltip: message,
      status: gateway.status,
    );
  }

  final message = '当前网关未连接：$displayName';
  return ConversationGatewayIssue(
    key: '${conversation.conversationId}:${gateway.gatewayId}:disconnected',
    gatewayId: gateway.gatewayId,
    message: message,
    tooltip: message,
    status: gateway.status,
  );
}
