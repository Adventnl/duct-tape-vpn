import 'package:flutter_test/flutter_test.dart';
import 'package:duct_tape_vpn/domain/vpn_state.dart';

void main() {
  test('service failure preserves requested ON', () {
    final previous = VpnState(
      desired: Desired.on,
      tunnel: Tunnel.up,
      paired: true,
    );
    final failed = VpnState.unavailable(previous);
    expect(failed.desired, Desired.on);
    expect(failed.nativeAvailable, false);
    expect(failed.protectedAt(DateTime.now()), false);
  });
  test('protection needs fresh OS and connectivity evidence', () {
    final now = DateTime(2026, 11, 11);
    final state = VpnState(
      desired: Desired.on,
      tunnel: Tunnel.up,
      protection: Protection.enforced,
      permission: PermissionState.granted,
      verifiedAt: now,
      paired: true,
    );
    expect(state.protectedAt(now.add(const Duration(seconds: 29))), true);
    expect(state.protectedAt(now.add(const Duration(seconds: 31))), false);
    expect(state.protectedAt(now.subtract(const Duration(seconds: 1))), false);
  });
  test('a running service without traffic evidence is not connected', () {
    expect(
      const VpnState(
        desired: Desired.on,
        tunnel: Tunnel.up,
        protection: Protection.limited,
        permission: PermissionState.granted,
        paired: true,
      ).label(DateTime.now()),
      'Not connected',
    );
  });
  test('unknown native evidence fails closed in presentation', () {
    final state = VpnState.fromMap({
      'desired': 'on',
      'tunnel': 'up',
      'protection': 'invented',
    });
    expect(state.protectedAt(DateTime.now()), false);
    expect(state.protection, Protection.unknown);
  });
  test('an unavailable native service remains unavailable after decoding', () {
    final state = VpnState.fromMap({'nativeAvailable': false, 'paired': true});
    expect(state.nativeAvailable, false);
    expect(state.label(DateTime.now()), 'Not connected');
    expect(state.protectedAt(DateTime.now()), false);
  });
  final now = DateTime(2026, 11, 12);
  VpnState connection({
    ConnectionCheck check = ConnectionCheck.passed,
    DateTime? checkedAt,
    Desired desired = Desired.on,
    Tunnel tunnel = Tunnel.up,
    bool available = true,
    bool paired = true,
    PermissionState permission = PermissionState.granted,
  }) => VpnState(
    desired: desired,
    tunnel: tunnel,
    nativeAvailable: available,
    paired: paired,
    permission: permission,
    connectionCheck: check,
    connectedAt: checkedAt ?? now,
    protection: Protection.limited,
  );

  test('connected requires a recent successful traffic check', () {
    expect(connection().label(now), 'Connected');
    expect(
      connection().label(now.add(const Duration(seconds: 29))),
      'Connected',
    );
    expect(
      connection().label(now.add(const Duration(seconds: 30))),
      'Not connected',
    );
    expect(
      connection().label(now.subtract(const Duration(milliseconds: 1))),
      'Not connected',
    );
    expect(connection(check: ConnectionCheck.pending).label(now), 'Connecting');
    expect(
      connection(check: ConnectionCheck.failed).label(now),
      'Not connected',
    );
    expect(connection().protectedAt(now), false);
  });

  test(
    'old evidence cannot override disconnection, service failure or permission',
    () {
      for (final state in [
        connection(desired: Desired.off),
        connection(tunnel: Tunnel.down),
        connection(tunnel: Tunnel.failed),
        connection(available: false),
        connection(paired: false),
        connection(permission: PermissionState.denied),
        connection(permission: PermissionState.unknown),
      ]) {
        expect(state.label(now), 'Not connected');
      }
      expect(connection(tunnel: Tunnel.reconnecting).label(now), 'Connecting');
    },
  );

  test(
    'connection evidence is decoded separately from protection evidence',
    () {
      final state = VpnState.fromMap({
        'paired': true,
        'nativeAvailable': true,
        'permission': 'granted',
        'desired': 'on',
        'tunnel': 'up',
        'protection': 'limited',
        'connectionCheck': 'passed',
        'connectedAt': now.millisecondsSinceEpoch ~/ 1000,
      });
      expect(state.label(now), 'Connected');
      expect(state.verifiedAt, isNull);
      expect(state.protectedAt(now), false);
      expect(
        VpnState.fromMap({'connectionCheck': 'invented', 'connectedAt': 0})
            .connectedAt,
        isNull,
      );
    },
  );
}
