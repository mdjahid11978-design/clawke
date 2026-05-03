import 'package:client/core/notification_event.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationClickRouterProvider = Provider<NotificationClickRouter>((
  ref,
) {
  return NotificationClickRouter();
});

typedef NotificationPayloadOpener = bool Function(NotificationPayload payload);

class NotificationClickRouter {
  NotificationPayload? _pendingPayload;

  void handleTap(NotificationPayload payload, NotificationPayloadOpener open) {
    if (open(payload)) return;
    _pendingPayload = payload;
  }

  void savePending(NotificationPayload payload) {
    _pendingPayload = payload;
  }

  void flushPending(NotificationPayloadOpener open) {
    final payload = _pendingPayload;
    if (payload == null) return;
    if (open(payload)) {
      _pendingPayload = null;
    }
  }
}
