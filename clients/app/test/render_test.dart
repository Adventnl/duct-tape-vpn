// Captures real Flutter widgets with explicitly simulated VPN states.
// These images verify UI rendering, not platform VPN operation.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:duct_tape_vpn/main.dart';
import 'package:duct_tape_vpn/application/vpn_controller.dart';
import 'package:duct_tape_vpn/domain/vpn_state.dart';
import 'package:duct_tape_vpn/infrastructure/native_vpn.dart';

class RenderPort implements VpnPort {
  RenderPort(this.state);
  VpnState state;
  int toggles = 0;
  @override
  Future<VpnState> snapshot() async => state;
  @override
  Future<void> setDesired(bool on) async {
    toggles++;
    state = VpnState(
      paired: true,
      desired: on ? Desired.on : Desired.off,
      tunnel: on ? Tunnel.connecting : Tunnel.down,
      permission: PermissionState.granted,
      protection: Protection.none,
      connectionCheck: ConnectionCheck.pending,
    );
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
  const off = VpnState(
    paired: true,
    permission: PermissionState.granted,
    protection: Protection.none,
  );
  final connected = VpnState(
    paired: true,
    desired: Desired.on,
    tunnel: Tunnel.up,
    permission: PermissionState.granted,
    protection: Protection.limited,
    connectionCheck: ConnectionCheck.passed,
    connectedAt: DateTime.now(),
  );
  const unavailable = VpnState(nativeAvailable: false);
  setUpAll(() async {
    final loader = FontLoader('Segoe UI');
    for (final path in [
      'C:/Windows/Fonts/segoeui.ttf',
      'C:/Windows/Fonts/seguisb.ttf',
    ]) {
      if (File(path).existsSync()) {
        loader.addFont(
          Future.value(ByteData.sublistView(await File(path).readAsBytes())),
        );
      }
    }
    await loader.load();
    final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
      ..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      );
    await icons.load();
  });

  for (final scenario in [
    ('mobile', const Size(390, 844), 1.0, Brightness.light, off, false),
    ('desktop', const Size(460, 780), 1.0, Brightness.light, off, false),
    (
      'dark-connected',
      const Size(390, 844),
      1.0,
      Brightness.dark,
      connected,
      false,
    ),
    (
      'connecting',
      const Size(460, 780),
      1.0,
      Brightness.dark,
      const VpnState(
        paired: true,
        desired: Desired.on,
        tunnel: Tunnel.up,
        permission: PermissionState.granted,
        connectionCheck: ConnectionCheck.pending,
      ),
      false,
    ),
    (
      'connection-failed',
      const Size(390, 844),
      1.0,
      Brightness.light,
      const VpnState(
        paired: true,
        desired: Desired.on,
        tunnel: Tunnel.up,
        permission: PermissionState.granted,
        connectionCheck: ConnectionCheck.failed,
        connectionDetail:
            'Your home server did not respond. Check the server and try again.',
      ),
      false,
    ),
    (
      'large-text',
      const Size(320, 720),
      2.0,
      Brightness.light,
      unavailable,
      false,
    ),
    (
      'settings',
      const Size(390, 844),
      1.0,
      Brightness.light,
      unavailable,
      true,
    ),
  ]) {
    testWidgets('Flutter capture ${scenario.$1}', (tester) async {
      tester.view.physicalSize = scenario.$2;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$3;
      tester.platformDispatcher.platformBrightnessTestValue = scenario.$4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: DuctTapeApp(
            controller: VpnController(RenderPort(scenario.$5)),
          ),
        ),
      );
      // The real connecting indicator intentionally keeps animating.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (scenario.$6) {
        await tester.tap(find.byTooltip('Setup and settings'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(find.text('Protected'), findsNothing);
      expect(find.textContaining('verifying'), findsNothing);
      expect(find.text('On requested'), findsNothing);
      if (scenario.$1 == 'dark-connected') {
        expect(find.text('Connected'), findsOneWidget);
      }
      if (scenario.$1 == 'connecting') {
        expect(find.text('Connecting'), findsOneWidget);
      }
      if (scenario.$1 == 'connection-failed') {
        expect(find.text('Not connected'), findsOneWidget);
      }
      if (scenario.$1 == 'mobile') {
        final buttonLabel = find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(RichText),
        );
        final spans = tester
            .widgetList<RichText>(buttonLabel)
            .map((x) => x.text.toStringDeep())
            .join('\n');
        await tester.runAsync(
          () async =>
              File('../../artifacts/ui/button-style.txt').writeAsString(spans),
        );
      }
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final target = File('../../artifacts/ui/${scenario.$1}.png');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('connect requests a tunnel without claiming protection', (
    tester,
  ) async {
    final port = RenderPort(off);
    await tester.pumpWidget(DuctTapeApp(controller: VpnController(port)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(port.toggles, 1);
    expect(find.text('Connecting'), findsOneWidget);
    expect(find.text('Protected'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
