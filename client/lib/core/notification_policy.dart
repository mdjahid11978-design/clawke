import 'package:client/core/notification_event.dart';

class NotificationPolicyContext {
  final bool isConversationVisible;
  final bool isMuted;
  final bool isSyncReplay;
  final bool isDuplicate;
  final bool isLocalSender;

  const NotificationPolicyContext({
    required this.isConversationVisible,
    required this.isMuted,
    required this.isSyncReplay,
    required this.isDuplicate,
    required this.isLocalSender,
  });
}

class NotificationDecision {
  final bool shouldShowSystemNotification;
  final bool shouldPlaySound;
  final String reason;

  const NotificationDecision._({
    required this.shouldShowSystemNotification,
    required this.shouldPlaySound,
    required this.reason,
  });

  const NotificationDecision.show({bool playSound = true})
    : this._(
        shouldShowSystemNotification: true,
        shouldPlaySound: playSound,
        reason: 'show',
      );

  const NotificationDecision.suppress(String reason)
    : this._(
        shouldShowSystemNotification: false,
        shouldPlaySound: false,
        reason: reason,
      );
}

class NotificationPolicy {
  const NotificationPolicy();

  NotificationDecision evaluate(
    MessageNotificationEvent event,
    NotificationPolicyContext context,
  ) {
    if (context.isLocalSender || event.senderId == 'local_user') {
      return const NotificationDecision.suppress('local_sender');
    }
    if (context.isDuplicate) {
      return const NotificationDecision.suppress('duplicate');
    }
    if (context.isSyncReplay) {
      return const NotificationDecision.suppress('sync_replay');
    }
    if (context.isConversationVisible) {
      return const NotificationDecision.suppress('visible_conversation');
    }
    if (context.isMuted) {
      return const NotificationDecision.suppress('muted_conversation');
    }
    return const NotificationDecision.show();
  }
}
