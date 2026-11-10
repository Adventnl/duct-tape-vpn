import 'dart:async';
import 'package:flutter/foundation.dart';
import '../domain/vpn_state.dart';
import '../infrastructure/native_vpn.dart';
class VpnController extends ChangeNotifier {
  VpnController(this.port);
  final VpnPort port;
  VpnState state = const VpnState();
  bool busy = false;
  String? error;
  Timer? _timer;
  bool _disposed = false, _reading = false;
  void start() { refresh(); _timer = Timer.periodic(const Duration(seconds:2), (_) => refresh()); }
  Future<void> refresh() async {
    if (_reading || _disposed) return;
    _reading = true;
    try { state = await port.snapshot(); }
    catch (_) { state = VpnState.unavailable(state); }
    finally { _reading = false; if (!_disposed) notifyListeners(); }
  }
  Future<void> toggle() async {
    if (busy || !state.paired || !state.nativeAvailable) return;
    busy = true; error = null; notifyListeners();
    try { await port.setDesired(state.desired != Desired.on); }
    catch (_) { error = 'The service could not change the connection. Check diagnostics.'; }
    finally { busy = false; await refresh(); }
  }
  @override void dispose() { _disposed = true; _timer?.cancel(); super.dispose(); }
}
