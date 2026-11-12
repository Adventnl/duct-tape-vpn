enum Desired { off, on }

enum Tunnel { down, connecting, up, reconnecting, failed }

enum Protection { none, blocked, enforced, limited, unknown }

enum PermissionState { unknown, granted, denied, restricted }

enum ConnectionCheck { unavailable, pending, passed, failed }

enum ConnectionStatus { notConnected, connecting, connected }

class VpnState {
  const VpnState({
    this.desired = Desired.off,
    this.tunnel = Tunnel.down,
    this.protection = Protection.unknown,
    this.permission = PermissionState.unknown,
    this.verifiedAt,
    this.connectionCheck = ConnectionCheck.unavailable,
    this.connectedAt,
    this.connectionDetail,
    this.paired = false,
    this.owner = false,
    this.detail,
    this.enrollment = 'none',
    this.fingerprint,
    this.nativeAvailable = true,
  });
  final Desired desired;
  final Tunnel tunnel;
  final Protection protection;
  final PermissionState permission;
  final DateTime? verifiedAt;
  final ConnectionCheck connectionCheck;
  final DateTime? connectedAt;
  final String? connectionDetail;
  final bool paired, owner, nativeAvailable;
  final String? detail;
  final String enrollment;
  final String? fingerprint;
  bool protectedAt(DateTime now) =>
      desired == Desired.on &&
      tunnel == Tunnel.up &&
      protection == Protection.enforced &&
      permission == PermissionState.granted &&
      verifiedAt != null &&
      now.difference(verifiedAt!).inSeconds >= 0 &&
      now.difference(verifiedAt!).inSeconds <= 30;
  ConnectionStatus connectionAt(DateTime now) {
    if (!nativeAvailable ||
        !paired ||
        desired == Desired.off ||
        permission == PermissionState.denied ||
        permission == PermissionState.restricted ||
        protection == Protection.blocked ||
        tunnel == Tunnel.failed ||
        connectionCheck == ConnectionCheck.failed) {
      return ConnectionStatus.notConnected;
    }
    if (tunnel == Tunnel.connecting || tunnel == Tunnel.reconnecting) {
      return ConnectionStatus.connecting;
    }
    if (tunnel != Tunnel.up) return ConnectionStatus.notConnected;
    if (connectionCheck == ConnectionCheck.passed &&
        connectedAt != null &&
        now.difference(connectedAt!).inMilliseconds >= 0 &&
        now.difference(connectedAt!).inSeconds < 30 &&
        permission == PermissionState.granted) {
      return ConnectionStatus.connected;
    }
    return connectionCheck == ConnectionCheck.pending
        ? ConnectionStatus.connecting
        : ConnectionStatus.notConnected;
  }

  String label(DateTime now) => switch (connectionAt(now)) {
    ConnectionStatus.notConnected => 'Not connected',
    ConnectionStatus.connecting => 'Connecting',
    ConnectionStatus.connected => 'Connected',
  };

  String connectionMessage(DateTime now) {
    if (!nativeAvailable) {
      return 'VPN service unavailable. Check setup and try again.';
    }
    if (!paired) {
      return enrollment == 'pending'
          ? 'Waiting for your server owner to approve this device.'
          : 'Set up your home server to connect.';
    }
    if (permission == PermissionState.denied ||
        permission == PermissionState.restricted) {
      return 'Allow VPN access in settings to connect.';
    }
    if (desired == Desired.off) {
      return tunnel == Tunnel.down
          ? 'Connect to use your home server.'
          : 'Disconnecting from your home server.';
    }
    if (protection == Protection.blocked) {
      return 'Internet access is blocked while the VPN reconnects.';
    }
    if (connectionAt(now) == ConnectionStatus.connected) {
      return 'Your internet connection is using your home server.';
    }
    if (connectionAt(now) == ConnectionStatus.connecting) {
      return 'Connecting to your home server.';
    }
    if (connectionCheck == ConnectionCheck.failed &&
        connectionDetail != null &&
        connectionDetail!.isNotEmpty) {
      return connectionDetail!;
    }
    if (tunnel == Tunnel.up && connectionCheck == ConnectionCheck.unavailable) {
      return 'Connection checks are unavailable on this device.';
    }
    return 'The VPN connection could not be confirmed. Disconnect and try again.';
  }

  VpnState requesting(bool on) => VpnState(
    desired: on ? Desired.on : Desired.off,
    tunnel: on ? Tunnel.connecting : tunnel,
    protection: protection,
    permission: permission,
    paired: paired,
    owner: owner,
    detail: detail,
    enrollment: enrollment,
    fingerprint: fingerprint,
    nativeAvailable: nativeAvailable,
    connectionCheck: ConnectionCheck.pending,
  );

  VpnState connectionFailed(String reason) => VpnState(
    desired: desired,
    tunnel: tunnel,
    protection: protection,
    permission: permission,
    paired: paired,
    owner: owner,
    detail: detail,
    enrollment: enrollment,
    fingerprint: fingerprint,
    nativeAvailable: nativeAvailable,
    connectionCheck: ConnectionCheck.failed,
    connectionDetail: reason,
  );

  factory VpnState.unavailable(VpnState previous) => VpnState(
    desired: previous.desired,
    tunnel: Tunnel.failed,
    protection: Protection.unknown,
    permission: PermissionState.unknown,
    paired: previous.paired,
    owner: previous.owner,
    enrollment: previous.enrollment,
    fingerprint: previous.fingerprint,
    nativeAvailable: false,
  );
  factory VpnState.fromMap(Map<Object?, Object?> m) {
    T parse<T extends Enum>(List<T> values, Object? value, T fallback) =>
        values.firstWhere((x) => x.name == value, orElse: () => fallback);
    return VpnState(
      desired: parse(Desired.values, m['desired'], Desired.off),
      tunnel: parse(Tunnel.values, m['tunnel'], Tunnel.down),
      protection: parse(Protection.values, m['protection'], Protection.unknown),
      permission: parse(
        PermissionState.values,
        m['permission'],
        PermissionState.unknown,
      ),
      verifiedAt: m['verifiedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch((m['verifiedAt'] as int) * 1000)
          : null,
      connectionCheck: parse(
        ConnectionCheck.values,
        m['connectionCheck'],
        ConnectionCheck.unavailable,
      ),
      connectedAt: m['connectedAt'] is int && (m['connectedAt'] as int) > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              (m['connectedAt'] as int) * 1000,
            )
          : null,
      connectionDetail: m['connectionDetail'] as String?,
      enrollment: m['enrollment'] as String? ?? 'none',
      fingerprint: m['fingerprint'] as String?,
      paired: m['paired'] == true,
      owner: m['owner'] == true,
      nativeAvailable: m['nativeAvailable'] != false,
      detail: m['detail'] as String?,
    );
  }
}
