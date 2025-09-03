import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkType {
  wifi,
  mobile,
  offline,
}

class NetworkProvider extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  
  NetworkType _currentNetworkType = NetworkType.wifi;
  bool _isOffline = false;
  bool _isFlatpak = false;
  
  NetworkType get currentNetworkType => _currentNetworkType;
  bool get isOffline => _isOffline;
  bool get isOnWifi => _currentNetworkType == NetworkType.wifi;
  bool get isOnMobile => _currentNetworkType == NetworkType.mobile;
  
  NetworkProvider() {
    _initialize();
  }
  
  Future<void> _initialize() async {
    // Check if running in Flatpak
    _isFlatpak = Platform.isLinux && 
                  (Platform.environment['FLATPAK_ID'] != null || 
                   File('/.flatpak-info').existsSync());
    
    // Check initial connectivity
    await _checkConnectivity();
    
    // Listen for connectivity changes (may fail in Flatpak without system bus)
    try {
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _handleConnectivityChange,
        onError: (error) {
          debugPrint('[NetworkProvider] Connectivity monitoring error: $error');
          // Assume online in Flatpak if monitoring fails
          if (_isFlatpak) {
            _handleConnectivityChange([ConnectivityResult.wifi]);
          }
        },
      );
    } catch (e) {
      debugPrint('[NetworkProvider] Failed to setup connectivity monitoring: $e');
      // Assume online in Flatpak
      if (_isFlatpak) {
        _currentNetworkType = NetworkType.wifi;
        _isOffline = false;
        notifyListeners();
      }
    }
  }
  
  Future<void> _checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _handleConnectivityChange(results);
    } catch (e) {
      debugPrint('[NetworkProvider] Error checking connectivity: $e');
      // In Flatpak without system bus access, assume we're online
      if (_isFlatpak) {
        debugPrint('[NetworkProvider] Assuming online connectivity in Flatpak');
        _handleConnectivityChange([ConnectivityResult.wifi]);
      }
    }
  }
  
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    NetworkType newType;
    bool offline = false;
    
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      newType = NetworkType.offline;
      offline = true;
    } else if (results.contains(ConnectivityResult.wifi) || 
               results.contains(ConnectivityResult.ethernet)) {
      newType = NetworkType.wifi;
      offline = false;
    } else if (results.contains(ConnectivityResult.mobile)) {
      newType = NetworkType.mobile;
      offline = false;
    } else {
      // Other connection types (bluetooth, vpn, etc.) - treat as mobile for now
      newType = NetworkType.mobile;
      offline = false;
    }
    
    if (newType != _currentNetworkType || offline != _isOffline) {
      _currentNetworkType = newType;
      _isOffline = offline;
      
      debugPrint('[NetworkProvider] Network changed: $newType (offline: $offline)');
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}