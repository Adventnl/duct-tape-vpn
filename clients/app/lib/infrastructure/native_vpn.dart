import 'package:flutter/services.dart';
import '../domain/vpn_state.dart';
abstract class VpnPort {
  Future<VpnState> snapshot();
  Future<Map<Object?,Object?>> ownerPublic();
  Future<void> importOwner(String bundle);
  Future<void> setDesired(bool on);
  Future<Map<Object?,Object?>> pair(String invitation, String name);
  Future<Map<Object?,Object?>> refreshEnrollment();
  Future<Map<Object?,Object?>> administer(Map<String,Object?> operation);
}
class NativeVpn implements VpnPort {
  static const _channel = MethodChannel('dev.ducttape/vpn');
  @override Future<Map<Object?,Object?>> ownerPublic() async => await _channel.invokeMapMethod<Object?,Object?>('ownerPublic') ?? {};
  @override Future<void> importOwner(String bundle) => _channel.invokeMethod<void>('importOwner',{'bundle':bundle});
  @override Future<VpnState> snapshot() async => VpnState.fromMap(await _channel.invokeMapMethod<Object?,Object?>('snapshot') ?? {});
  @override Future<void> setDesired(bool on) => _channel.invokeMethod<void>('setDesired',{'on':on});
  @override Future<Map<Object?,Object?>> pair(String invitation,String name) async => await _channel.invokeMapMethod<Object?,Object?>('pair',{'invitation':invitation,'name':name}) ?? {};
  @override Future<Map<Object?,Object?>> refreshEnrollment() async => await _channel.invokeMapMethod<Object?,Object?>('refreshEnrollment') ?? {};
  @override Future<Map<Object?,Object?>> administer(Map<String,Object?> operation) async => await _channel.invokeMapMethod<Object?,Object?>('admin',operation) ?? {};
}
