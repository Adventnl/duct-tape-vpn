import 'package:flutter_test/flutter_test.dart';
import 'package:duct_tape_vpn/domain/vpn_state.dart';
void main(){
  test('service failure preserves requested ON',(){final previous=VpnState(desired:Desired.on,tunnel:Tunnel.up,paired:true);final failed=VpnState.unavailable(previous);expect(failed.desired,Desired.on);expect(failed.nativeAvailable,false);expect(failed.protectedAt(DateTime.now()),false);});
  test('protection needs fresh OS and connectivity evidence',(){final now=DateTime(2026,11,11);final state=VpnState(desired:Desired.on,tunnel:Tunnel.up,protection:Protection.enforced,permission:PermissionState.granted,verifiedAt:now,paired:true);expect(state.protectedAt(now.add(const Duration(seconds:29))),true);expect(state.protectedAt(now.add(const Duration(seconds:31))),false);expect(state.protectedAt(now.subtract(const Duration(seconds:1))),false);});
  test('limited platforms never claim Protected',(){expect(const VpnState(desired:Desired.on,tunnel:Tunnel.up,protection:Protection.limited,permission:PermissionState.granted,paired:true).label(DateTime.now()),'Tunnel active · verifying connection');});
  test('unknown native evidence fails closed in presentation',(){final state=VpnState.fromMap({'desired':'on','tunnel':'up','protection':'invented'});expect(state.protectedAt(DateTime.now()),false);expect(state.protection,Protection.unknown);});
}
