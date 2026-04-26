import 'package:client/models/gateway_info.dart';
import 'package:client/providers/database_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final gatewayListProvider = StreamProvider<List<GatewayInfo>>((ref) {
  return ref.watch(gatewayRepositoryProvider).watchAll();
});

final onlineGatewayListProvider = StreamProvider<List<GatewayInfo>>((ref) {
  return ref.watch(gatewayRepositoryProvider).watchOnline();
});

final selectedGatewayIdProvider = StateProvider<String?>((ref) => null);

final selectedGatewayProvider = Provider<GatewayInfo?>((ref) {
  final selectedId = ref.watch(selectedGatewayIdProvider);
  final gateways = ref.watch(onlineGatewayListProvider).valueOrNull ?? const [];
  if (selectedId == null) return gateways.firstOrNull;
  return gateways.where((item) => item.gatewayId == selectedId).firstOrNull;
});
