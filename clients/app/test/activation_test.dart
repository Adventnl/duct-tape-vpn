import 'dart:convert';

import 'package:duct_tape_vpn/infrastructure/activation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'activation keeps secrets in the fragment and normalizes human input',
    () {
      final link = activationInvitation(
        ' vpn.example.org:9443/ ',
        'abcd-ef01-2345-6789-abcd',
      );
      final uri = Uri.parse(link);
      expect(uri.query, isEmpty);
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(uri.fragment))),
      ) as Map;
      expect(payload['origin'], 'https://vpn.example.org:9443');
      expect(payload['code'], 'ABCDEF0123456789ABCD');
    },
  );
  test('activation refuses insecure or ambiguous server addresses', () {
    for (final address in [
      'http://vpn.example.org',
      'https://user@vpn.example.org',
      'https://vpn.example.org/path',
      'https://vpn.example.org?x=1',
      'https://vpn.example.org#x',
    ]) {
      expect(
        () => activationInvitation(address, 'ABCD-EF01-2345-6789-ABCD'),
        throwsFormatException,
      );
    }
    expect(
      () => activationInvitation('vpn.example.org', '123456'),
      throwsFormatException,
    );
  });
}
