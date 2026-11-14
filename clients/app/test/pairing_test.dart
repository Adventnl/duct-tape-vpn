import 'dart:convert';

import 'package:duct_tape_vpn/application/vpn_controller.dart';
import 'package:duct_tape_vpn/presentation/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'widget_test.dart' show Port;

class PairingPort extends Port {
  String? invitation;
  bool reject = false;

  @override
  Future<Map<Object?, Object?>> pair(String input, String name) async {
    if (reject) throw StateError('Activation rejected');
    invitation = input;
    return {};
  }
}

void main() {
  Future<PairingPort> open(
    WidgetTester tester, {
    String origin = 'https://vpn.example.org',
  }) async {
    final port = PairingPort();
    final controller = VpnController(port);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Settings(controller: controller, activationOrigin: origin),
      ),
    );
    return port;
  }

  testWidgets('personal pairing accepts a code through one field', (
    tester,
  ) async {
    final port = await open(tester);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Server address'), findsNothing);
    expect(find.text('Use an invitation link'), findsNothing);
    await tester.enterText(find.byType(TextField), 'abcd-ef01-2345-6789-abcd');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final payload = jsonDecode(
      utf8.decode(
        base64Url.decode(
          base64Url.normalize(Uri.parse(port.invitation!).fragment),
        ),
      ),
    ) as Map;
    expect(payload['origin'], 'https://vpn.example.org');
    expect(payload['code'], 'ABCDEF0123456789ABCD');
    expect(
      find.text('Activation accepted. Saving your connection…'),
      findsOneWidget,
    );
  });

  testWidgets('invalid and rejected codes leave setup recoverable', (
    tester,
  ) async {
    final port = await open(tester);
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('Activate device'));
    await tester.pumpAndSettle();
    expect(port.invitation, isNull);
    expect(
      find.text('Enter all five groups of the activation code.'),
      findsOneWidget,
    );
    port.reject = true;
    await tester.enterText(find.byType(TextField), 'abcd-ef01-2345-6789-abcd');
    await tester.tap(find.text('Activate device'));
    await tester.pumpAndSettle();
    expect(find.textContaining('try a fresh activation code'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isNotEmpty,
    );
  });

  testWidgets('generic builds retain server and invitation setup', (
    tester,
  ) async {
    await open(tester, origin: '');
    expect(find.text('Server address'), findsOneWidget);
    await tester.tap(find.text('Use an invitation link'));
    await tester.pumpAndSettle();
    expect(find.text('Invitation link'), findsOneWidget);
    expect(find.text('Server address'), findsNothing);
  });
}
