import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/conversation_dao.dart';
import 'package:client/data/database/dao/message_dao.dart';
import 'package:client/data/repositories/conversation_repository.dart';
import 'package:client/data/repositories/message_repository.dart';
import 'package:client/providers/chat_provider.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/ws_state_provider.dart';

import '../helpers/provider_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerTestFallbackValues);

  late AppDatabase db;
  late ConversationDao conversationDao;
  late MessageDao messageDao;
  late StreamController<Map<String, dynamic>> messageStreamController;
  late MockWsService mockWs;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    conversationDao = ConversationDao(db);
    messageDao = MessageDao(db);
    await db.setMetadata('last_sync_seq', '175');

    messageStreamController =
        StreamController<Map<String, dynamic>>.broadcast();
    mockWs = MockWsService();
    when(() => mockWs.connect()).thenAnswer((_) async {});
    when(() => mockWs.state).thenReturn(WsState.connected);
    when(() => mockWs.send(any())).thenReturn(null);
    when(() => mockWs.sendJson(any())).thenReturn(null);
    when(() => mockWs.reconnect()).thenReturn(null);
    when(() => mockWs.dispose()).thenReturn(null);
    when(() => mockWs.stateStream).thenAnswer((_) => const Stream.empty());
    when(
      () => mockWs.messageStream,
    ).thenAnswer((_) => messageStreamController.stream);

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        conversationDaoProvider.overrideWithValue(conversationDao),
        messageDaoProvider.overrideWithValue(messageDao),
        wsServiceProvider.overrideWithValue(mockWs),
        conversationRepositoryProvider.overrideWithValue(
          ConversationRepository(
            dao: conversationDao,
            api: MockConfigApiService(),
          ),
        ),
        messageRepositoryProvider.overrideWithValue(
          MessageRepository(
            messageDao: messageDao,
            conversationDao: conversationDao,
            ws: mockWs,
          ),
        ),
        selectedConversationIdProvider.overrideWith((ref) => 'conv_test'),
      ],
    );
  });

  tearDown(() async {
    await messageStreamController.close();
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    await db.close();
  });

  test(
    'sync_response with final agent message clears stale thinking and tool state',
    () async {
      container.read(wsMessageHandlerProvider);

      messageStreamController.add({
        'payload_type': 'thinking_delta',
        'message_id': 'think_1777452430604',
        'conversation_id': 'conv_test',
        'account_id': 'OpenClaw',
        'content': '读取项目说明',
      });
      await Future<void>.delayed(Duration.zero);

      messageStreamController.add({
        'payload_type': 'thinking_done',
        'message_id': 'think_1777452430604',
        'conversation_id': 'conv_test',
        'account_id': 'OpenClaw',
      });
      await Future<void>.delayed(Duration.zero);

      messageStreamController.add({
        'payload_type': 'tool_call_start',
        'message_id': 'reply_1777452432361_1_tool_call',
        'conversation_id': 'conv_test',
        'account_id': 'OpenClaw',
        'tool_name': 'read',
        'tool_title': 'read from ~/MyProject/clawke/AGENTS.md',
      });
      await Future<void>.delayed(Duration.zero);

      expect(container.read(streamingThinkingProvider), isNotNull);
      expect(container.read(activeToolProvider), isNotNull);

      messageStreamController.add({
        'payload_type': 'sync_response',
        'id': 'sync_reconnect',
        'current_seq': 177,
        'messages': [
          {
            'seq': 176,
            'message_id': 'smsg_user',
            'client_msg_id': 'cmsg_2aec271e-daa7-49bf-9f2d-6f50e046a1b0',
            'account_id': 'OpenClaw',
            'conversation_id': 'conv_test',
            'sender_id': 'local_user',
            'type': 'text',
            'content': '你是这个项目的管家，读取Claude. Md',
            'ts': 1777452430310,
          },
          {
            'seq': 177,
            'message_id': 'smsg_2d7a4c71',
            'account_id': 'OpenClaw',
            'conversation_id': 'conv_test',
            'sender_id': 'agent',
            'type': 'text',
            'content': '已读取完毕。这是 Clawke 项目的核心开发指南。',
            'ts': 1777452452690,
          },
        ],
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final syncedAgentMessage = await messageDao.getMessage('smsg_2d7a4c71');
      expect(syncedAgentMessage, isNotNull);
      expect(syncedAgentMessage!.seq, 177);
      expect(syncedAgentMessage.content, contains('已读取完毕'));
      expect(await db.getMetadata('last_sync_seq'), '177');

      expect(container.read(waitingForReplyProvider), isNull);
      expect(container.read(activeToolProvider), isNull);
      expect(container.read(streamingMessageProvider), isNull);
      expect(container.read(streamingThinkingProvider), isNull);
    },
  );
}
