import 'dart:async';

import 'package:client/core/ws_service.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/conversation_dao.dart';
import 'package:client/data/database/dao/gateway_dao.dart';
import 'package:client/data/database/dao/message_dao.dart';
import 'package:client/data/repositories/conversation_repository.dart';
import 'package:client/data/repositories/gateway_repository.dart';
import 'package:client/data/repositories/message_repository.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/providers/chat_provider.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/ws_state_provider.dart';
import 'package:client/services/config_api_service.dart';
import 'package:client/services/gateways_api_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/provider_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerTestFallbackValues);

  late AppDatabase db;
  late ConversationDao conversationDao;
  late MessageDao messageDao;
  late GatewayDao gatewayDao;
  late StreamController<Map<String, dynamic>> messageStreamController;
  late MockWsService mockWs;
  late MockConfigApiService mockConfigApi;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    conversationDao = ConversationDao(db);
    messageDao = MessageDao(db);
    gatewayDao = GatewayDao(db);
    messageStreamController =
        StreamController<Map<String, dynamic>>.broadcast();
    mockWs = MockWsService();
    mockConfigApi = MockConfigApiService();

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

    when(() => mockConfigApi.getConversations()).thenAnswer(
      (_) async => const [
        ServerConv(
          id: 'conv_hermes',
          type: 'dm',
          name: 'New Chat (hermes)',
          accountId: 'hermes',
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
    );

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        conversationDaoProvider.overrideWithValue(conversationDao),
        messageDaoProvider.overrideWithValue(messageDao),
        gatewayDaoProvider.overrideWithValue(gatewayDao),
        wsServiceProvider.overrideWithValue(mockWs),
        gatewaysApiServiceProvider.overrideWithValue(_FakeGatewaysApiService()),
        conversationRepositoryProvider.overrideWithValue(
          ConversationRepository(dao: conversationDao, api: mockConfigApi),
        ),
        messageRepositoryProvider.overrideWithValue(
          MessageRepository(
            messageDao: messageDao,
            conversationDao: conversationDao,
            ws: mockWs,
          ),
        ),
        gatewayRepositoryProvider.overrideWithValue(
          GatewayRepository(dao: gatewayDao, api: _FakeGatewaysApiService()),
        ),
      ],
    );
  });

  tearDown(() async {
    await messageStreamController.close();
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    await db.close();
  });

  test('ai_connected does not auto-select a conversation', () async {
    container.read(wsMessageHandlerProvider);

    expect(container.read(selectedConversationIdProvider), isNull);

    messageStreamController.add({
      'payload_type': 'system_status',
      'status': 'ai_connected',
      'account_id': 'hermes',
      'agent_name': 'Hermes',
      'gateway_type': 'hermes',
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final conversations = await conversationDao.getConversationsByAccount(
      'hermes',
    );
    expect(conversations, hasLength(1));
    expect(container.read(selectedConversationIdProvider), isNull);
  });
}

class _FakeGatewaysApiService extends GatewaysApiService {
  @override
  Future<List<GatewayInfo>> listGateways() async => const [];

  @override
  Future<void> renameGateway(String gatewayId, String displayName) async {}
}
