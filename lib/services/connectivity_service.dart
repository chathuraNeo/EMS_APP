import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/app_config.dart';

class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  final ValueNotifier<bool> isOnline = ValueNotifier(true);
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    refresh();
    _sub = _connectivity.onConnectivityChanged.listen((_) => refresh());
  }

  Future<bool> hasConnection() => refresh();

  Future<bool> refresh() async {
    final results = await _connectivity.checkConnectivity();
    final adapterUp = results.any((result) => result != ConnectivityResult.none);
    final ok = adapterUp && await _canReachSite();
    isOnline.value = ok;
    return ok;
  }

  void markOffline() {
    isOnline.value = false;
  }

  Future<bool> _canReachSite() async {
    try {
      final host = Uri.parse(AppConfig.websiteBaseUrl).host;
      final result = await InternetAddress.lookup(host).timeout(
        const Duration(seconds: 4),
      );
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }
}