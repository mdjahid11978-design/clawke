import 'package:client/core/notification_event.dart';
import 'package:client/core/notification_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = NotificationPolicy();

  MessageNotificationEvent event({
    NotificationEventSource source = NotificationEventSource.remotePush,
    String senderId = 'agent',
  }) {
    return MessageNotificationEvent(
      source: source,
      conversationId: 'conv_1',
      messageId: 'msg_1',
      gatewayId: 'gateway_1',
      seq: 7,
      title: '新消息',
      preview: 'hello',
      priority: NotificationPriority.normal,
      category: NotificationCategory.message,
      createdAt: 1,
      senderId: senderId,
    );
  }

  NotificationPolicyContext context({
    bool isConversationVisible = false,
    bool isMuted = false,
    bool isSyncReplay = false,
    bool isDuplicate = false,
    bool isLocalSender = false,
  }) {
    return NotificationPolicyContext(
      isConversationVisible: isConversationVisible,
      isMuted: isMuted,
      isSyncReplay: isSyncReplay,
      isDuplicate: isDuplicate,
      isLocalSender: isLocalSender,
    );
  }

  test('suppresses local websocket message notification', () {
    final decision = policy.evaluate(
      event(source: NotificationEventSource.localWs),
      context(),
    );

    expect(decision.shouldShowSystemNotification, false);
    expect(decision.reason, 'local_ws');
  });

  test('shows remote push notification for non-visible agent message', () {
    final decision = policy.evaluate(
      const MessageNotificationEvent(
        source: NotificationEventSource.remotePush,
        conversationId: 'conv_1',
        messageId: 'msg_1',
        gatewayId: 'gateway_1',
        seq: 7,
        title: 'hermes',
        preview: 'hello',
        priority: NotificationPriority.normal,
        category: NotificationCategory.message,
        createdAt: 1,
        senderId: 'agent',
      ),
      context(),
    );

    expect(decision.shouldShowSystemNotification, true);
    expect(decision.shouldPlaySound, true);
    expect(decision.reason, 'show');
  });

  test('suppresses current visible conversation', () {
    final decision = policy.evaluate(
      event(),
      context(isConversationVisible: true),
    );

    expect(decision.shouldShowSystemNotification, false);
    expect(decision.reason, 'visible_conversation');
  });

  test('suppresses muted conversation', () {
    final decision = policy.evaluate(event(), context(isMuted: true));

    expect(decision.shouldShowSystemNotification, false);
    expect(decision.reason, 'muted_conversation');
  });

  test('suppresses sync replay', () {
    final decision = policy.evaluate(event(), context(isSyncReplay: true));

    expect(decision.shouldShowSystemNotification, false);
    expect(decision.reason, 'sync_replay');
  });

  test('suppresses duplicate message', () {
    final decision = policy.evaluate(event(), context(isDuplicate: true));

    expect(decision.shouldShowSystemNotification, false);
    expect(decision.reason, 'duplicate');
  });

  test('suppresses local sender', () {
    final decision = policy.evaluate(event(senderId: 'local_user'), context());

    expect(decision.shouldShowSystemNotification, false);
    expect(decision.reason, 'local_sender');
  });
}
