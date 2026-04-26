import 'dart:convert';

import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/gateway_dao.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/services/gateways_api_service.dart';
import 'package:drift/drift.dart';

class GatewayRepository {
  final GatewayDao _dao;
  final GatewaysApi _api;

  GatewayRepository({required GatewayDao dao, required GatewaysApi api})
      : _dao = dao,
        _api = api;

  Stream<List<GatewayInfo>> watchAll() => _dao.watchAll().map(_fromRows);

  Stream<List<GatewayInfo>> watchOnline() => _dao.watchOnline().map(_fromRows);

  Future<List<GatewayInfo>> getOnlineGateways() async =>
      _fromRows(await _dao.getOnlineGateways());

  Future<void> syncFromServer() async {
    final gateways = await _api.listGateways();
    final ids = <String>{};
    for (final gateway in gateways) {
      ids.add(gateway.gatewayId);
      await _dao.upsertGateway(_toCompanion(gateway));
    }
    await _dao.deleteMissing(ids);
  }

  Future<void> markOnline(GatewayInfo gateway) {
    return _dao.upsertGateway(_toCompanion(gateway));
  }

  Future<void> markOffline(String gatewayId) async {
    final existing = await _dao.getGateway(gatewayId);
    if (existing == null) return;
    await _dao.upsertGateway(
      GatewaysCompanion(
        gatewayId: Value(existing.gatewayId),
        displayName: Value(existing.displayName),
        gatewayType: Value(existing.gatewayType),
        status: const Value('disconnected'),
        capabilitiesJson: Value(existing.capabilitiesJson),
        lastErrorCode: Value(existing.lastErrorCode),
        lastErrorMessage: Value(existing.lastErrorMessage),
        lastConnectedAt: Value(existing.lastConnectedAt),
        lastSeenAt: Value(DateTime.now().millisecondsSinceEpoch),
        createdAt: Value(existing.createdAt),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> renameGateway(String gatewayId, String displayName) async {
    await _api.renameGateway(gatewayId, displayName);
    await syncFromServer();
  }

  List<GatewayInfo> _fromRows(List<Gateway> rows) {
    return rows.map((row) {
      return GatewayInfo(
        gatewayId: row.gatewayId,
        displayName: row.displayName,
        gatewayType: row.gatewayType,
        status: gatewayStatusFromString(row.status),
        capabilities: _decodeCapabilities(row.capabilitiesJson),
        lastErrorCode: row.lastErrorCode,
        lastErrorMessage: row.lastErrorMessage,
        lastConnectedAt: row.lastConnectedAt,
        lastSeenAt: row.lastSeenAt,
      );
    }).toList();
  }

  GatewaysCompanion _toCompanion(GatewayInfo gateway) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return GatewaysCompanion(
      gatewayId: Value(gateway.gatewayId),
      displayName: Value(gateway.displayName),
      gatewayType: Value(gateway.gatewayType),
      status: Value(gatewayStatusToString(gateway.status)),
      capabilitiesJson: Value(jsonEncode(gateway.capabilities)),
      lastErrorCode: Value(gateway.lastErrorCode),
      lastErrorMessage: Value(gateway.lastErrorMessage),
      lastConnectedAt: Value(gateway.lastConnectedAt),
      lastSeenAt: Value(gateway.lastSeenAt),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
  }
}

List<String> _decodeCapabilities(String raw) {
  try {
    final parsed = jsonDecode(raw);
    if (parsed is! List) return const [];
    return parsed.map((item) => item.toString()).toList();
  } catch (_) {
    return const [];
  }
}
