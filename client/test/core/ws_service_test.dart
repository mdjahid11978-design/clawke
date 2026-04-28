import 'package:client/core/ws_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sendJson logs outbound payload with model-relevant fields', () {
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };

    try {
      WsService().sendJson({
        'id': 'req_1',
        'protocol': 'cup_v2',
        'event_type': 'user_message',
        'context': {
          'account_id': 'hermes',
          'conversation_id': 'conv_1',
          'client_msg_id': 'cmsg_1',
        },
        'data': {'content': 'hello', 'type': 'text'},
      });
    } finally {
      debugPrint = originalDebugPrint;
    }

    expect(
      logs,
      contains(
        contains(
          '[WS] 📤 send: user_message payload={"id":"req_1","protocol":"cup_v2","event_type":"user_message","context":{"account_id":"hermes","conversation_id":"conv_1","client_msg_id":"cmsg_1"},"data":{"content":"hello","type":"text"}}',
        ),
      ),
    );
  });
}
