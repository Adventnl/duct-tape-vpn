import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:duct_tape_vpn/main.dart';
import 'package:duct_tape_vpn/application/vpn_controller.dart';
import 'package:duct_tape_vpn/domain/vpn_state.dart';
import 'package:duct_tape_vpn/infrastructure/native_vpn.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows app connects, carries traffic and restores OFF', (
    tester,
  ) async {
    final port = NativeVpn();
    final initial = await port.snapshot();
    addTearDown(() => port.setDesired(false));
    expect(
      initial.nativeAvailable && initial.paired,
      true,
      reason: 'Run the authorized personal setup before this real-device test.',
    );
    await port.setDesired(false);
    final controller = VpnController(port);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: DuctTapeApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pump();
    for (
      var i = 0;
      i < 100 &&
          controller.state.connectionAt(DateTime.now()) !=
              ConnectionStatus.connected;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await controller.refresh();
      await tester.pump();
    }
    expect(controller.state.tunnel, Tunnel.up);
    expect(
      controller.state.connectionAt(DateTime.now()),
      ConnectionStatus.connected,
      reason: controller.state.connectionMessage(DateTime.now()),
    );
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Protected'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final capture = File('../../artifacts/ui/windows-live-connected.png');
    await capture.parent.create(recursive: true);
    await capture.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    final ping = await Process.run('ping.exe', [
      '-n',
      '2',
      '-w',
      '1000',
      '10.77.0.1',
    ]);
    expect(
      ping.exitCode,
      0,
      reason: 'The home server must answer through WireGuard.',
    );
    final route = await Process.run('powershell.exe', [
      '-NoProfile',
      '-Command',
      '(Find-NetRoute -RemoteIPAddress 1.1.1.1 | Select-Object -First 1).InterfaceAlias',
    ]);
    expect(route.stdout.toString().trim(), 'DuctTape');
    final internet = await Process.run('curl.exe', [
      '-4',
      '--fail',
      '--silent',
      '--max-time',
      '15',
      'https://example.com',
    ]);
    expect(
      internet.exitCode,
      0,
      reason: 'IPv4 HTTPS must work through the home exit.',
    );
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 20 && controller.state.tunnel != Tunnel.down; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await controller.refresh();
      await tester.pump();
    }
    expect(controller.state.tunnel, Tunnel.down);
    expect(find.text('Not connected'), findsOneWidget);
    final restored = await Process.run('powershell.exe', [
      '-NoProfile',
      '-Command',
      '(Find-NetRoute -RemoteIPAddress 1.1.1.1 | Select-Object -First 1).InterfaceAlias',
    ]);
    expect(restored.stdout.toString().trim(), isNot('DuctTape'));
    await tester.pumpWidget(const SizedBox());
  });
}
