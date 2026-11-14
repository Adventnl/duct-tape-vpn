import 'dart:convert';

/// Personal builds know their server, so setup only asks for the one-use code.
const configuredActivationOrigin = String.fromEnvironment(
  'DUCT_ACTIVATION_ORIGIN',
);

/// The code grants one server-issued enrollment. The address selects its server;
/// HTTPS validates that address before native code pins the server signing key.
String activationInvitation(String address, String code) {
  final input = address.trim();
  final uri = Uri.tryParse(input.contains('://') ? input : 'https://$input');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
    throw const FormatException('Enter your server’s HTTPS address.');
  }
  final normalized = code.replaceAll(RegExp(r'[-\s]'), '').toUpperCase();
  if (!RegExp(r'^[0-9A-F]{20}$').hasMatch(normalized)) {
    throw const FormatException(
      'Enter all five groups of the activation code.',
    );
  }
  final payload = base64Url
      .encode(
        utf8.encode(jsonEncode({'origin': uri.origin, 'code': normalized})),
      )
      .replaceAll('=', '');
  return 'ducttape://activate#$payload';
}
