enum GatewayConnectionStatus { online, disconnected, error }

class GatewayInfo {
  final String gatewayId;
  final String displayName;
  final String gatewayType;
  final GatewayConnectionStatus status;
  final List<String> capabilities;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final int? lastConnectedAt;
  final int? lastSeenAt;

  const GatewayInfo({
    required this.gatewayId,
    required this.displayName,
    required this.gatewayType,
    required this.status,
    this.capabilities = const [],
    this.lastErrorCode,
    this.lastErrorMessage,
    this.lastConnectedAt,
    this.lastSeenAt,
  });

  factory GatewayInfo.fromJson(Map<String, dynamic> json) {
    final gatewayId = json['gateway_id'] as String? ?? '';
    return GatewayInfo(
      gatewayId: gatewayId,
      displayName: json['display_name'] as String? ?? gatewayId,
      gatewayType: json['gateway_type'] as String? ?? 'unknown',
      status: gatewayStatusFromString(json['status'] as String?),
      capabilities: (json['capabilities'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      lastErrorCode: json['last_error_code'] as String?,
      lastErrorMessage: json['last_error_message'] as String?,
      lastConnectedAt: _asInt(json['last_connected_at']),
      lastSeenAt: _asInt(json['last_seen_at']),
    );
  }

  bool supports(String capability) => capabilities.contains(capability);
}

GatewayConnectionStatus gatewayStatusFromString(String? value) {
  return switch (value) {
    'online' => GatewayConnectionStatus.online,
    'error' => GatewayConnectionStatus.error,
    _ => GatewayConnectionStatus.disconnected,
  };
}

String gatewayStatusToString(GatewayConnectionStatus status) {
  return switch (status) {
    GatewayConnectionStatus.online => 'online',
    GatewayConnectionStatus.error => 'error',
    GatewayConnectionStatus.disconnected => 'disconnected',
  };
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}
