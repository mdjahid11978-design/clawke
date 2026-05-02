import 'package:client/data/database/app_database.dart';

enum TaskDeliveryInvalidReason {
  none,
  empty,
  userTarget,
  unsupportedTarget,
  invalidConversationId,
  missingConversation,
}

class TaskDeliveryValidation {
  final bool isValid;
  final TaskDeliveryInvalidReason reason;
  final String? rawTarget;
  final String? conversationId;
  final Conversation? conversation;

  const TaskDeliveryValidation({
    required this.isValid,
    required this.reason,
    this.rawTarget,
    this.conversationId,
    this.conversation,
  });
}

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String taskConversationDeliveryValue(String conversationId) {
  return 'conversation:$conversationId';
}

TaskDeliveryValidation validateTaskDeliveryTarget({
  required String? deliver,
  required String accountId,
  required List<Conversation> conversations,
}) {
  final raw = deliver?.trim();
  if (raw == null || raw.isEmpty) {
    return const TaskDeliveryValidation(
      isValid: false,
      reason: TaskDeliveryInvalidReason.empty,
    );
  }

  final lower = raw.toLowerCase();
  if (lower.startsWith('user:')) {
    return TaskDeliveryValidation(
      isValid: false,
      reason: TaskDeliveryInvalidReason.userTarget,
      rawTarget: raw,
    );
  }

  if (!lower.startsWith('conversation:')) {
    return TaskDeliveryValidation(
      isValid: false,
      reason: TaskDeliveryInvalidReason.unsupportedTarget,
      rawTarget: raw,
    );
  }

  final conversationId = raw.substring('conversation:'.length).trim();
  if (!_uuidPattern.hasMatch(conversationId)) {
    return TaskDeliveryValidation(
      isValid: false,
      reason: TaskDeliveryInvalidReason.invalidConversationId,
      rawTarget: raw,
      conversationId: conversationId,
    );
  }

  for (final conversation in conversations) {
    if (conversation.conversationId == conversationId &&
        conversation.accountId == accountId) {
      return TaskDeliveryValidation(
        isValid: true,
        reason: TaskDeliveryInvalidReason.none,
        rawTarget: raw,
        conversationId: conversationId,
        conversation: conversation,
      );
    }
  }

  return TaskDeliveryValidation(
    isValid: false,
    reason: TaskDeliveryInvalidReason.missingConversation,
    rawTarget: raw,
    conversationId: conversationId,
  );
}

List<Conversation> taskDeliveryConversationsForAccount({
  required String accountId,
  required List<Conversation> conversations,
}) {
  return conversations
      .where((conversation) => conversation.accountId == accountId)
      .toList(growable: false);
}
