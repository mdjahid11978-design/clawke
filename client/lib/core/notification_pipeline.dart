import 'package:client/core/notification_event.dart';
import 'package:client/core/notification_policy.dart';
import 'package:client/core/notification_service.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/nav_page_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationPipelineProvider = Provider<NotificationPipeline>((ref) {
  return NotificationPipeline(ref);
});

class NotificationPipeline {
  final Ref _ref;
  final NotificationPolicy _policy;
  final Set<String> _shownMessageIds = <String>{};

  NotificationPipeline(this._ref, {NotificationPolicy? policy})
    : _policy = policy ?? const NotificationPolicy();

  Future<NotificationDecision> handleMessage(
    MessageNotificationEvent event, {
    bool isSyncReplay = false,
  }) async {
    final isDuplicate = _shownMessageIds.contains(event.messageId);
    final context = NotificationPolicyContext(
      isConversationVisible: _isConversationVisible(event.conversationId),
      isMuted: await _isMuted(event.conversationId),
      isSyncReplay: isSyncReplay,
      isDuplicate: isDuplicate,
      isLocalSender: event.senderId == 'local_user',
    );
    final decision = _policy.evaluate(event, context);

    if (!decision.shouldShowSystemNotification) {
      debugPrint(
        '[NotificationPipeline] system notification suppressed: '
        'reason=${decision.reason}, conv=${event.conversationId}, '
        'msg=${event.messageId}',
      );
      return decision;
    }

    debugPrint(
      '[NotificationPipeline] system notification allowed: '
      'conv=${event.conversationId}, msg=${event.messageId}',
    );
    _shownMessageIds.add(event.messageId);
    await NotificationService.showMessageNotification(
      title: event.title,
      body: event.preview,
      accountId: event.gatewayId,
      payload: event.toPayload(),
      playSound: decision.shouldPlaySound,
    );
    return decision;
  }

  bool _isConversationVisible(String conversationId) {
    return _ref.read(selectedConversationIdProvider) == conversationId &&
        _ref.read(activeChatConversationIdProvider) == conversationId &&
        _ref.read(activeNavPageProvider) == NavPage.chat;
  }

  Future<bool> _isMuted(String conversationId) async {
    final loadedConversations = _ref.read(conversationListProvider).valueOrNull;
    final loaded = loadedConversations
        ?.where((item) => item.conversationId == conversationId)
        .firstOrNull;
    if (loaded != null) return loaded.isMuted != 0;

    final conversation = await _ref
        .read(conversationDaoProvider)
        .getConversation(conversationId);
    return conversation?.isMuted != 0;
  }
}
