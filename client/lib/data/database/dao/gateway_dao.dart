import 'package:client/data/database/app_database.dart';

class GatewayDao {
  final AppDatabase _db;
  GatewayDao(this._db);

  Stream<List<Gateway>> watchAll() => _db.watchAllGateways().watch();

  Stream<List<Gateway>> watchOnline() => _db.watchOnlineGateways().watch();

  Future<List<Gateway>> getOnlineGateways() => _db.watchOnlineGateways().get();

  Future<Gateway?> getGateway(String gatewayId) =>
      _db.getGateway(gatewayId).getSingleOrNull();

  Future<void> upsertGateway(GatewaysCompanion entry) {
    return _db.into(_db.gateways).insertOnConflictUpdate(entry);
  }

  Future<void> deleteMissing(Set<String> serverIds) async {
    final existing = await _db.watchAllGateways().get();
    for (final gateway in existing) {
      if (!serverIds.contains(gateway.gatewayId)) {
        await (_db.delete(_db.gateways)
              ..where((t) => t.gatewayId.equals(gateway.gatewayId)))
            .go();
      }
    }
  }
}
