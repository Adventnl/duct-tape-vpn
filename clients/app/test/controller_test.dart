import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:duct_tape_vpn/application/vpn_controller.dart';
import 'package:duct_tape_vpn/domain/vpn_state.dart';
import 'package:duct_tape_vpn/infrastructure/native_vpn.dart';

class ControlledPort implements VpnPort {
  VpnState state = const VpnState(
    paired: true,
    permission: PermissionState.granted,
    protection: Protection.none,
  );
  Future<VpnState> Function()? read;
  Future<void> Function(bool)? change;
  @override
  Future<VpnState> snapshot() async => read != null ? read!() : state;
  @override
  Future<void> setDesired(bool on) async {
    if (change != null) return change!(on);
    state = state.requesting(on);
  }

  @override
  Future<Map<Object?, Object?>> ownerPublic() async => {};
  @override
  Future<void> importOwner(String bundle) async {}
  @override
  Future<Map<Object?, Object?>> pair(String invitation, String name) async =>
      {};
  @override
  Future<Map<Object?, Object?>> refreshEnrollment() async => {};
  @override
  Future<Map<Object?, Object?>> administer(
    Map<String, Object?> operation,
  ) async => {};
}

void main() {
  test(
    'connect shows progress immediately and a stalled check times out',
    () async {
      var now = DateTime(2026, 11, 12);
      final port = ControlledPort();
      final controller = VpnController(port, now: () => now);
      addTearDown(controller.dispose);
      await controller.refresh();
      final request = Completer<void>();
      port.change = (on) async {
        await request.future;
        port.state = port.state.requesting(on);
      };
      final toggle = controller.toggle();
      expect(controller.state.label(now), 'Connecting');
      request.complete();
      await toggle;
      now = now.add(const Duration(seconds: 20));
      await controller.refresh();
      expect(controller.state.label(now), 'Not connected');
      expect(controller.state.connectionMessage(now), contains('timed out'));
      await controller.refresh();
      expect(controller.state.label(now), 'Not connected');
      port.state = VpnState(
        paired: true,
        desired: Desired.on,
        tunnel: Tunnel.up,
        permission: PermissionState.granted,
        connectionCheck: ConnectionCheck.passed,
        connectedAt: now,
      );
      await controller.refresh();
      expect(controller.state.label(now), 'Connected');
    },
  );

  test(
    'a snapshot started before disconnect cannot restore Connected',
    () async {
      final now = DateTime(2026, 11, 12);
      final connected = VpnState(
        paired: true,
        desired: Desired.on,
        tunnel: Tunnel.up,
        permission: PermissionState.granted,
        connectionCheck: ConnectionCheck.passed,
        connectedAt: now,
      );
      final port = ControlledPort()..state = connected;
      final controller = VpnController(port, now: () => now);
      addTearDown(controller.dispose);
      await controller.refresh();
      final stale = Completer<VpnState>();
      port.read = () => stale.future;
      final refresh = controller.refresh();
      final stopping = Completer<void>();
      port.change = (_) => stopping.future;
      final disconnect = controller.toggle();
      expect(controller.state.label(now), 'Not connected');
      stale.complete(connected);
      await refresh;
      expect(controller.state.label(now), 'Not connected');
      port.read = null;
      port.state = const VpnState(
        paired: true,
        permission: PermissionState.granted,
      );
      stopping.complete();
      await disconnect;
      expect(controller.state.label(now), 'Not connected');
    },
  );

  test('native errors discard successful connection evidence', () async {
    final now = DateTime(2026, 11, 12);
    final port = ControlledPort()
      ..state = VpnState(
        paired: true,
        desired: Desired.on,
        tunnel: Tunnel.up,
        permission: PermissionState.granted,
        connectionCheck: ConnectionCheck.passed,
        connectedAt: now,
      );
    final controller = VpnController(port, now: () => now);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.state.label(now), 'Connected');
    port.read = () async => throw StateError('Service unavailable');
    await controller.refresh();
    expect(controller.state.label(now), 'Not connected');
    expect(controller.state.connectedAt, isNull);
  });
}
