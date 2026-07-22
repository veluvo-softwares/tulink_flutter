import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Network-interface awareness used as a retry hint.
///
/// A non-empty interface does not prove that TuLink's backend is reachable;
/// callers must still trust the result of the real HTTP/WebSocket operation.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  final StreamController<bool> _transitions =
      StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  Stream<bool> get transitions => _transitions.stream;

  Future<void> init() async {
    _setResults(await _connectivity.checkConnectivity());
    _subscription = _connectivity.onConnectivityChanged.listen(_setResults);
  }

  void _setResults(List<ConnectivityResult> results) {
    final online = results.any((result) => result != ConnectivityResult.none);
    if (isOnline.value == online) return;
    isOnline.value = online;
    _transitions.add(online);
    print(
      online ? '🌐 Network interface available' : '📴 No network interface',
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _transitions.close();
    isOnline.dispose();
  }
}
