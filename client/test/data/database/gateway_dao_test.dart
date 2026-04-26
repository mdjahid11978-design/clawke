import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/gateway_dao.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late GatewayDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = GatewayDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('upserts and watches online gateways only', () async {
    await dao.upsertGateway(
      GatewaysCompanion(
        gatewayId: const Value('hermes'),
        displayName: const Value('Hermes'),
        gatewayType: const Value('hermes'),
        status: const Value('online'),
        capabilitiesJson: const Value('["tasks","skills"]'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    await dao.upsertGateway(
      GatewaysCompanion(
        gatewayId: const Value('offline'),
        displayName: const Value('Offline'),
        gatewayType: const Value('hermes'),
        status: const Value('disconnected'),
        capabilitiesJson: const Value('["tasks"]'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );

    final online = await dao.getOnlineGateways();
    expect(online.map((item) => item.gatewayId), ['hermes']);
  });

  test('deleteMissing removes gateways not returned by server', () async {
    await dao.upsertGateway(
      GatewaysCompanion(
        gatewayId: const Value('old'),
        displayName: const Value('Old'),
        gatewayType: const Value('hermes'),
        status: const Value('online'),
        capabilitiesJson: const Value('["tasks"]'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );

    await dao.deleteMissing({'hermes'});
    expect(await dao.getGateway('old'), isNull);
  });
}
