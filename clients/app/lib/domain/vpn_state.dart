enum Desired { off, on }
enum Tunnel { down, connecting, up, reconnecting, failed }
enum Protection { none, blocked, enforced, limited, unknown }
enum PermissionState { unknown, granted, denied, restricted }

class VpnState {
  const VpnState({this.desired = Desired.off, this.tunnel = Tunnel.down,
    this.protection = Protection.unknown, this.permission = PermissionState.unknown,
    this.verifiedAt, this.paired = false, this.owner = false, this.detail,
    this.enrollment = 'none', this.fingerprint, this.nativeAvailable = true});
  final Desired desired;
  final Tunnel tunnel;
  final Protection protection;
  final PermissionState permission;
  final DateTime? verifiedAt;
  final bool paired, owner, nativeAvailable;
  final String? detail;
  final String enrollment;
  final String? fingerprint;
  bool protectedAt(DateTime now) => desired == Desired.on && tunnel == Tunnel.up &&
    protection == Protection.enforced && permission == PermissionState.granted &&
    verifiedAt != null && now.difference(verifiedAt!).inSeconds >= 0 &&
    now.difference(verifiedAt!).inSeconds <= 30;
  String label(DateTime now) {
    if (!nativeAvailable) return 'Native service unavailable';
    if (!paired) return enrollment == 'pending' ? 'Waiting for Owner approval' : 'Pair with home to begin';
    if (desired == Desired.off) return tunnel == Tunnel.down && protection == Protection.none ? 'Off · ordinary connection' : 'Off requested · restoring connectivity';
    if (permission == PermissionState.denied || permission == PermissionState.restricted) return 'VPN permission required';
    if (protectedAt(now)) return 'Protected';
    if (protection == Protection.blocked) return 'Connectivity blocked';
    if (tunnel == Tunnel.reconnecting) return 'Reconnecting…';
    if (tunnel == Tunnel.connecting) return 'Connecting…';
    if (tunnel == Tunnel.failed) return 'Connection failed · ON requested';
    if (tunnel == Tunnel.up && (verifiedAt == null || now.difference(verifiedAt!).inSeconds < 0 || now.difference(verifiedAt!).inSeconds > 30)) return 'Tunnel active · verifying connection';
    if (tunnel == Tunnel.up && protection == Protection.limited) return 'Connected · protection limited';
    if (tunnel == Tunnel.up) return 'Connected · verifying protection';
    return 'Waiting for tunnel';
  }
  factory VpnState.unavailable(VpnState previous) => VpnState(
    desired: previous.desired, tunnel: Tunnel.failed, protection: Protection.unknown,
    permission: PermissionState.unknown, paired: previous.paired, owner: previous.owner,
    enrollment: previous.enrollment, fingerprint: previous.fingerprint, nativeAvailable: false);
  factory VpnState.fromMap(Map<Object?, Object?> m) {
    T parse<T extends Enum>(List<T> values, Object? value, T fallback) => values.firstWhere((x) => x.name == value, orElse: () => fallback);
    return VpnState(desired: parse(Desired.values,m['desired'],Desired.off),
      tunnel: parse(Tunnel.values,m['tunnel'],Tunnel.down),
      protection: parse(Protection.values,m['protection'],Protection.unknown),
      permission: parse(PermissionState.values,m['permission'],PermissionState.unknown),
      verifiedAt: m['verifiedAt'] is int ? DateTime.fromMillisecondsSinceEpoch((m['verifiedAt'] as int)*1000) : null,
      enrollment: m['enrollment'] as String? ?? 'none', fingerprint: m['fingerprint'] as String?, paired: m['paired'] == true, owner: m['owner'] == true, detail: m['detail'] as String?);
  }
}
