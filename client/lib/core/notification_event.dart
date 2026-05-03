import 'dart:convert';

enum NotificationEventSource { localWs, remotePush }

enum NotificationPriority { normal, high }

enum NotificationCategory { message, action, system }

class MessageNotificationEvent {
  final NotificationEventSource source;
  final String conversationId;
  final String messageId;
  final String gatewayId;
  final int seq;
  final String title;
  final String preview;
  final NotificationPriority priority;
  final NotificationCategory category;
  final int createdAt;
  final String senderId;

  const MessageNotificationEvent({
    required this.source,
    required this.conversationId,
    required this.messageId,
    required this.gatewayId,
    required this.seq,
    required this.title,
    required this.preview,
    required this.priority,
    required this.category,
    required this.createdAt,
    required this.senderId,
  });

  NotificationPayload toPayload() {
    return NotificationPayload(
      conversationId: conversationId,
      messageId: messageId,
      gatewayId: gatewayId,
      seq: seq,
      source: source,
    );
  }
}

class NotificationPayload {
  final String conversationId;
  final String messageId;
  final String gatewayId;
  final int seq;
  final NotificationEventSource source;

  const NotificationPayload({
    required this.conversationId,
    required this.messageId,
    required this.gatewayId,
    required this.seq,
    required this.source,
  });

  String encode() {
    return jsonEncode({
      'conversation_id': conversationId,
      'message_id': messageId,
      'gateway_id': gatewayId,
      'seq': seq,
      'source': source.name,
    });
  }

  static NotificationPayload? decode(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final conversationId = decoded['conversation_id'] as String?;
    final messageId = decoded['message_id'] as String?;
    final gatewayId = decoded['gateway_id'] as String?;
    if (conversationId == null || messageId == null || gatewayId == null) {
      return null;
    }

    final sourceName = decoded['source'] as String?;
    final source = NotificationEventSource.values
        .where((item) => item.name == sourceName)
        .firstOrNull;

    return NotificationPayload(
      conversationId: conversationId,
      messageId: messageId,
      gatewayId: gatewayId,
      seq: decoded['seq'] as int? ?? 0,
      source: source ?? NotificationEventSource.localWs,
    );
  }
}
