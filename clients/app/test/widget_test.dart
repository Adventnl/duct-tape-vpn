import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duct_tape_vpn/main.dart';
import 'package:duct_tape_vpn/application/vpn_controller.dart';
import 'package:duct_tape_vpn/domain/vpn_state.dart';
import 'package:duct_tape_vpn/infrastructure/native_vpn.dart';

class Port implements VpnPort {
  @override
  Future<Map<Object?, Object?>> ownerPublic() async => {};
  @override
  Future<void> importOwner(String bundle) async {}
  @override
  Future<VpnState> snapshot() async => const VpnState();
  @override
  Future<void> setDesired(bool on) async {}
  @override
  Future<Map<Object?, Object?>> pair(String i, String n) async => {};
  @override
  Future<Map<Object?, Object?>> refreshEnrollment() async => {};
  @override
  Future<Map<Object?, Object?>> administer(Map<String, Object?> o) async => {};
}

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(440, 640),
    const Size(390, 844),
  ]) {
    testWidgets('restrained home fits $size with large text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(DuctTapeApp(controller: VpnController(Port())));
      await tester.pump();
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Set up connection'), findsOneWidget);
      expect(find.text('Protected'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
