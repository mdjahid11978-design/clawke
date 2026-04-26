import 'package:client/models/gateway_info.dart';
import 'package:client/services/media_resolver.dart';
import 'package:dio/dio.dart';

abstract class GatewaysApi {
  Future<List<GatewayInfo>> listGateways();
  Future<void> renameGateway(String gatewayId, String displayName);
}

class GatewaysApiService implements GatewaysApi {
  late final Dio _dio;

  GatewaysApiService({Dio? dio}) {
    _dio = dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
          ),
        );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.baseUrl = MediaResolver.baseUrl;
          options.headers.addAll(MediaResolver.authHeaders);
          handler.next(options);
        },
      ),
    );
  }

  @override
  Future<List<GatewayInfo>> listGateways() async {
    final response = await _dio.get('/api/gateways');
    final data = Map<String, dynamic>.from(response.data as Map);
    final list = data['gateways'] as List? ?? const [];
    return list
        .map((item) => GatewayInfo.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  @override
  Future<void> renameGateway(String gatewayId, String displayName) async {
    await _dio.patch(
      '/api/gateways/${Uri.encodeComponent(gatewayId)}',
      data: {'display_name': displayName},
    );
  }
}
