import 'package:client/models/task_delivery_validation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/provider_overrides.dart';

void main() {
  const openClawConversationId = 'be0b0ced-0036-4192-a62a-b313ac772f9a';
  const hermesConversationId = '992ca166-26fb-4a1d-bcfb-4b7fb35559d4';

  test('conversation uuid in each current gateway account is valid', () {
    final conversations = [
      makeConversation(
        conversationId: openClawConversationId,
        accountId: 'OpenClaw',
        name: 'OpenClaw',
      ),
      makeConversation(
        conversationId: hermesConversationId,
        accountId: 'hermes',
        name: 'Hermes',
      ),
    ];

    final openClaw = validateTaskDeliveryTarget(
      deliver: 'conversation:$openClawConversationId',
      accountId: 'OpenClaw',
      conversations: conversations,
    );
    final hermes = validateTaskDeliveryTarget(
      deliver: 'conversation:$hermesConversationId',
      accountId: 'hermes',
      conversations: conversations,
    );

    expect(openClaw.isValid, isTrue);
    expect(openClaw.conversationId, openClawConversationId);
    expect(hermes.isValid, isTrue);
    expect(hermes.conversationId, hermesConversationId);
  });

  test('blank delivery is invalid because scheduled output needs a target', () {
    final result = validateTaskDeliveryTarget(
      deliver: '',
      accountId: 'OpenClaw',
      conversations: const [],
    );

    expect(result.isValid, isFalse);
    expect(result.reason, TaskDeliveryInvalidReason.empty);
  });

  test('user target is invalid even when it contains a uuid', () {
    final result = validateTaskDeliveryTarget(
      deliver: 'user:$openClawConversationId',
      accountId: 'OpenClaw',
      conversations: [
        makeConversation(
          conversationId: openClawConversationId,
          accountId: 'OpenClaw',
        ),
      ],
    );

    expect(result.isValid, isFalse);
    expect(result.reason, TaskDeliveryInvalidReason.userTarget);
  });

  test('conversation uuid from another account is invalid', () {
    final result = validateTaskDeliveryTarget(
      deliver: 'conversation:$openClawConversationId',
      accountId: 'OpenClaw',
      conversations: [
        makeConversation(
          conversationId: openClawConversationId,
          accountId: 'hermes',
        ),
      ],
    );

    expect(result.isValid, isFalse);
    expect(result.reason, TaskDeliveryInvalidReason.missingConversation);
  });
}
