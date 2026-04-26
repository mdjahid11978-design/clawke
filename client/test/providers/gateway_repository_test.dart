import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/gateway_dao.dart';
import 'package:client/data/repositories/gateway_repository.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/services/gateways_api_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGatewayApi implements GatewaysApi {
  List<GatewayInfo> items = const [];
  String? renamedId;
  String? renamedName;

  @override
  Future<List<GatewayInfo>> listGateways() async => items;

  @override
  Future<void> renameGateway(String gatewayId, String displayName) async {
    renamedId = gatewayId;
    renamedName = displayName;
  }
}

void main() {
  test('sync upserts server gateways and deletes missing local rows', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final api = FakeGatewayApi()
      ..items = const [
        GatewayInfo(
          gatewayId: 'hermes',
          displayName: 'Hermes',
          gatewayType: 'hermes',
          status: GatewayConnectionStatus.online,
          capabilities: ['tasks', 'skills'],
        ),
      ];
    final repo = GatewayRepository(dao: GatewayDao(db), api: api);

    await repo.markOnline(
      const GatewayInfo(
        gatewayId: 'old',
        displayName: 'Old',
        gatewayType: 'hermes',
        status: GatewayConnectionStatus.online,
        capabilities: ['tasks'],
      ),
    );

    await repo.syncFromServer();
    final online = await repo.getOnlineGateways();
    expect(online.map((item) => item.gatewayId), ['hermes']);
    await db.close();
  });

  test('rename is server first then syncs', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final api = FakeGatewayApi()
      ..items = const [
        GatewayInfo(
          gatewayId: 'hermes',
          displayName: 'Personal Hermes',
          gatewayType: 'hermes',
          status: GatewayConnectionStatus.online,
          capabilities: ['tasks'],
        ),
      ];
    final repo = GatewayRepository(dao: GatewayDao(db), api: api);

    await repo.renameGateway('hermes', 'Personal Hermes');
    expect(api.renamedId, 'hermes');
    expect(api.renamedName, 'Personal Hermes');
    await db.close();
  });
}
