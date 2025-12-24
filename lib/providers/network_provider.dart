import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../services/navidrome_api.dart';

enum NetworkType {
  wifi,
  mobile,
  offline,
}

/// Connection state for the app
enum ConnectionState {
  connected, // Fully connected and server verified
  connecting, // Initial connection attempt
  reconnecting, // Was connected, attempting to restore
  disconnected, // No network connectivity
  degraded, // Network present but server unreachable
}

/// Events emitted when connection state changes
enum ConnectionEvent {
  connected, // First successful connection
  disconnected, // Lost network connectivity
  reconnected, // Successfully restored connection
  serverUnreachable, // Network OK but server down
  serverRestored, // Server became reachable again
}

class NetworkProvider extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  NetworkType _currentNetworkType = NetworkType.wifi;
  bool _isOffline = false;
  bool _isFlatpak = false;

  // Connection event stream for components to listen to
  final _connectionEventController = StreamController<ConnectionEvent>.broadcast();
  Stream<ConnectionEvent> get connectionEvents => _connectionEventController.stream;

  // Connection state management
  ConnectionState _connectionState = ConnectionState.connecting;
  ConnectionState get connectionState => _connectionState;

  // Server health monitoring
  NavidromeApi? _api;
  Timer? _serverHealthTimer;
  bool _serverReachable = false;
  bool get isServerReachable => _serverReachable;

  // Reconnection state
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectBaseDelay = Duration(seconds: 2);
  static const Duration _healthCheckInterval = Duration(seconds: 30);

  // Circuit breaker for DNS/network failures
  int _consecutiveFailures = 0;
  static const int _failureThresholdForOffline = 3;

  NetworkType get currentNetworkType => _currentNetworkType;
  bool get isOffline => _isOffline;
  bool get isOnWifi => _currentNetworkType == NetworkType.wifi;
  bool get isOnMobile => _currentNetworkType == NetworkType.mobile;
  
  NetworkProvider() {
    _initialize();
  }
  
  Future<void> _initialize() async {
    debugPrint('[NetworkProvider] Initializing...');

    // Check if running in Flatpak or other container without D-Bus access
    _isFlatpak = Platform.isLinux &&
                  (Platform.environment['FLATPAK_ID'] != null ||
                   File('/.flatpak-info').existsSync() ||
                   Platform.environment['container'] != null || // Toolbx/Podman
                   !File('/var/run/dbus/system_bus_socket').existsSync());
    debugPrint('[NetworkProvider] Running in container/no D-Bus: $_isFlatpak');

    // Check initial connectivity
    await _checkConnectivity();

    // Skip connectivity_plus stream in containers - it requires D-Bus
    if (_isFlatpak) {
      debugPrint('[NetworkProvider] Container detected - skipping connectivity_plus stream');
      // Set up periodic internet check instead
      _startPeriodicConnectivityCheck();
      return;
    }

    // Listen for connectivity changes (may fail without system bus)
    try {
      debugPrint('[NetworkProvider] Setting up connectivity monitoring...');
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _handleConnectivityChange,
        onError: (error) {
          debugPrint('[NetworkProvider] Connectivity monitoring error: $error');
        },
      );
      debugPrint('[NetworkProvider] Connectivity monitoring setup successfully');
    } catch (e) {
      debugPrint('[NetworkProvider] Failed to setup connectivity monitoring: $e');
      _startPeriodicConnectivityCheck();
    }
  }

  void _startPeriodicConnectivityCheck() {
    // Poll for connectivity every 30 seconds as fallback
    Timer.periodic(const Duration(seconds: 30), (_) async {
      final hasInternet = await _checkInternetAccess();
      if (hasInternet && _isOffline) {
        _handleConnectivityChange([ConnectivityResult.wifi]);
      } else if (!hasInternet && !_isOffline) {
        _handleConnectivityChange([ConnectivityResult.none]);
      }
    });
  }
  
  Future<void> _checkConnectivity() async {
    // In containers without D-Bus, skip connectivity_plus and check directly
    if (_isFlatpak) {
      debugPrint('[NetworkProvider] Container detected - checking internet directly');
      final hasInternet = await _checkInternetAccess();
      if (hasInternet) {
        _handleConnectivityChange([ConnectivityResult.wifi]);
      } else {
        _handleConnectivityChange([ConnectivityResult.none]);
      }
      return;
    }

    try {
      debugPrint('[NetworkProvider] Checking connectivity...');
      final results = await _connectivity.checkConnectivity();
      debugPrint('[NetworkProvider] Connectivity results: $results');

      // Check if we actually have internet access
      if (results.isNotEmpty && !results.contains(ConnectivityResult.none)) {
        final hasInternet = await _checkInternetAccess();
        debugPrint('[NetworkProvider] Internet access: $hasInternet');
        if (!hasInternet) {
          // No internet access despite having connectivity
          _handleConnectivityChange([ConnectivityResult.none]);
          return;
        }
      }

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

  Future<bool> _checkInternetAccess() async {
    try {
      // Try to connect to dns0.eu with a short timeout
      final response = await http.get(
        Uri.parse('https://www.dns0.eu/'),
        headers: {'Cache-Control': 'no-cache'},
      ).timeout(const Duration(seconds: 3));

      // Any successful response means we have internet
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[NetworkProvider] Internet check failed: $e');
      return false;
    }
  }

  /// Set the API instance for server health monitoring
  void setApi(NavidromeApi api) {
    _api = api;
    // If we're online, assume server is reachable until proven otherwise
    if (!_isOffline) {
      _serverReachable = true;
      _connectionState = ConnectionState.connected;
      // Defer notifyListeners to avoid calling during build
      Future.microtask(() => notifyListeners());
    }
    // Run immediate health check, then start periodic monitoring
    _checkServerHealth().then((_) => _startServerHealthMonitoring());
  }

  void _startServerHealthMonitoring() {
    _serverHealthTimer?.cancel();
    _serverHealthTimer = Timer.periodic(
      _healthCheckInterval,
      (_) => _checkServerHealth(),
    );
    // Immediate check
    _checkServerHealth();
  }

  void _stopServerHealthMonitoring() {
    _serverHealthTimer?.cancel();
    _serverHealthTimer = null;
  }

  /// Suspend health check timer (for battery optimization when idle)
  void suspendHealthChecks() {
    _stopServerHealthMonitoring();
    debugPrint('[NetworkProvider] Health checks suspended');
  }

  /// Resume health check timer
  void resumeHealthChecks() {
    if (_api != null && !_isOffline) {
      _startServerHealthMonitoring();
      debugPrint('[NetworkProvider] Health checks resumed');
    }
  }

  Future<void> _checkServerHealth() async {
    if (_api == null || _isOffline) return;

    try {
      final reachable = await _api!.ping();

      if (reachable && !_serverReachable) {
        _serverReachable = true;
        _connectionState = ConnectionState.connected;
        _connectionEventController.add(ConnectionEvent.serverRestored);
        _consecutiveFailures = 0;
        debugPrint('[NetworkProvider] Server restored');
        notifyListeners();
      } else if (!reachable && _serverReachable) {
        // Require 2 consecutive failures before marking unreachable
        _consecutiveFailures++;
        if (_consecutiveFailures >= 2) {
          _serverReachable = false;
          _connectionState = ConnectionState.degraded;
          _connectionEventController.add(ConnectionEvent.serverUnreachable);
          debugPrint('[NetworkProvider] Server unreachable');
          notifyListeners();
        }
      } else if (reachable) {
        _consecutiveFailures = 0;
        if (!_serverReachable) {
          _serverReachable = true;
          _connectionState = ConnectionState.connected;
        }
      }
    } catch (e) {
      _consecutiveFailures++;
      if (_serverReachable && _consecutiveFailures >= 2) {
        _serverReachable = false;
        _connectionState = ConnectionState.degraded;
        _connectionEventController.add(ConnectionEvent.serverUnreachable);
        debugPrint('[NetworkProvider] Server health check failed: $e');
        notifyListeners();
      }
    }
  }

  Future<void> _startReconnectionSequence() async {
    _connectionState = ConnectionState.reconnecting;
    _reconnectAttempts = 0;
    notifyListeners();

    while (_reconnectAttempts < _maxReconnectAttempts && !_isOffline) {
      _reconnectAttempts++;
      debugPrint('[NetworkProvider] Reconnect attempt $_reconnectAttempts');

      await _checkServerHealth();

      if (_serverReachable) {
        _connectionState = ConnectionState.connected;
        _connectionEventController.add(ConnectionEvent.reconnected);
        _startServerHealthMonitoring();
        debugPrint('[NetworkProvider] Reconnection successful');
        notifyListeners();
        return;
      }

      // Exponential backoff
      final delay = _reconnectBaseDelay * _reconnectAttempts;
      await Future.delayed(delay);
    }

    // Max attempts reached - go offline
    _connectionState = ConnectionState.disconnected;
    _isOffline = true;
    _serverReachable = false;
    _connectionEventController.add(ConnectionEvent.disconnected);
    debugPrint('[NetworkProvider] Reconnection failed after $_reconnectAttempts attempts - now offline');
    notifyListeners();
  }

  /// Manual retry trigger (can be called from UI)
  Future<void> retryConnection() async {
    if (!_isOffline) {
      _reconnectAttempts = 0;
      await _startReconnectionSequence();
    }
  }

  /// Report a network failure (called by API on request failures)
  /// After consecutive failures, sets offline mode
  void reportNetworkFailure() {
    _consecutiveFailures++;
    debugPrint('[NetworkProvider] Network failure reported ($_consecutiveFailures/$_failureThresholdForOffline)');

    if (_consecutiveFailures >= _failureThresholdForOffline && !_isOffline) {
      _isOffline = true;
      _serverReachable = false;
      _connectionState = ConnectionState.disconnected;
      _connectionEventController.add(ConnectionEvent.disconnected);
      debugPrint('[NetworkProvider] Circuit breaker triggered - now offline');
      notifyListeners();
    }
  }

  /// Report a successful network request (resets failure counter)
  void reportNetworkSuccess() {
    if (_consecutiveFailures > 0) {
      debugPrint('[NetworkProvider] Network success - resetting failure counter');
      _consecutiveFailures = 0;
    }

    if (_isOffline) {
      _isOffline = false;
      _serverReachable = true;
      _connectionState = ConnectionState.connected;
      _connectionEventController.add(ConnectionEvent.reconnected);
      debugPrint('[NetworkProvider] Network restored - back online');
      _startServerHealthMonitoring();
      notifyListeners();
    }
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    NetworkType newType;
    bool offline = false;

    debugPrint('[NetworkProvider] Handling connectivity change: $results');

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
      final oldType = _currentNetworkType;
      final wasOffline = _isOffline;
      _currentNetworkType = newType;
      _isOffline = offline;

      debugPrint('[NetworkProvider] Network changed: $oldType -> $newType (offline: $wasOffline -> $offline)');

      // Emit connection events and trigger reconnection
      if (wasOffline && !offline) {
        // Going online - start reconnection
        _connectionEventController.add(ConnectionEvent.connected);
        _startReconnectionSequence();
      } else if (!wasOffline && offline) {
        // Going offline
        _connectionState = ConnectionState.disconnected;
        _serverReachable = false;
        _connectionEventController.add(ConnectionEvent.disconnected);
        _stopServerHealthMonitoring();
      }

      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _serverHealthTimer?.cancel();
    _connectionEventController.close();
    super.dispose();
  }
}