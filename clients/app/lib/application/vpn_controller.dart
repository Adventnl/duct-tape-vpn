import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/vpn_state.dart';
import '../infrastructure/native_vpn.dart';

class VpnController extends ChangeNotifier {
  VpnController(this.port, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final VpnPort port;
  final DateTime Function() _now;
  VpnState state = const VpnState();
  bool busy = false;
  String? error;
  Timer? _timer;
  bool _disposed = false, _reading = false;
  DateTime? _connectingSince;
  int _requestGeneration = 0;
  void start() {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_reading || _disposed || busy) return;
    _reading = true;
    final generation = _requestGeneration;
    try {
      var snapshot = await port.snapshot();
      if (!snapshot.paired && snapshot.enrollment == 'pending') {
        try {
          await port.refreshEnrollment();
          snapshot = await port.snapshot();
        } catch (_) {
          // A temporarily unreachable server must not discard a saved claim.
        }
      }
      if (_disposed || generation != _requestGeneration) return;
      state = snapshot;
      final now = _now();
      if (state.connectionAt(now) == ConnectionStatus.connecting) {
        _connectingSince ??= now;
        if (now.difference(_connectingSince!) >= const Duration(seconds: 20)) {
          state = state.connectionFailed(
            'The connection timed out. Disconnect and try again.',
          );
        }
      } else {
        _connectingSince = null;
      }
    } catch (_) {
      if (!_disposed && generation == _requestGeneration) {
        state = VpnState.unavailable(state);
      }
    } finally {
      _reading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (busy || !state.paired || !state.nativeAvailable) return;
    busy = true;
    error = null;
    final on = state.desired != Desired.on;
    ++_requestGeneration;
    state = state.requesting(on);
    _connectingSince = on ? _now() : null;
    notifyListeners();
    try {
      await port.setDesired(on);
    } catch (_) {
      error =
          'Could not ${on ? 'connect' : 'disconnect'}. Check setup and try again.';
    } finally {
      busy = false;
      await refresh();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
