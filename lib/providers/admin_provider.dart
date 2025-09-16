import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../services/navidrome_api.dart';

class AdminProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool? _hasAdminRights;
  String? _error;
  DateTime? _lastChecked;
  bool _isDisposed = false;
  static const Duration _cacheExpiry = Duration(minutes: 5);

  bool get isLoading => _isLoading;
  bool? get hasAdminRights => _hasAdminRights;
  String? get error => _error;
  bool get canScan => _hasAdminRights ?? false;

  AdminProvider();

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> checkAdminRights(NavidromeApi api) async {
    // Don't check if already loading
    if (_isLoading) return;

    // Check if we have a recent cached result
    if (_lastChecked != null &&
        DateTime.now().difference(_lastChecked!) < _cacheExpiry &&
        _hasAdminRights != null) {
      if (kDebugMode) {
        print('[AdminProvider] Using cached admin rights: $_hasAdminRights');
      }
      return;
    }

    _isLoading = true;
    _error = null;

    // Use addPostFrameCallback to avoid calling notifyListeners during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        notifyListeners();
      }
    });

    try {
      if (kDebugMode) {
        print('[AdminProvider] Checking admin rights for user: ${api.username}');
      }

      _hasAdminRights = await api.hasAdminRights();
      _lastChecked = DateTime.now();

      if (kDebugMode) {
        print('[AdminProvider] Admin rights check result: $_hasAdminRights');
      }
    } catch (e) {
      _error = e.toString();
      _hasAdminRights = false; // Default to no admin rights on error

      if (kDebugMode) {
        print('[AdminProvider] Error checking admin rights: $e');
      }
    } finally {
      _isLoading = false;

      // Use addPostFrameCallback to avoid calling notifyListeners during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed) {
          notifyListeners();
        }
      });
    }
  }

  void clearCache() {
    _hasAdminRights = null;
    _lastChecked = null;
    _error = null;

    // Use addPostFrameCallback to avoid calling notifyListeners during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        notifyListeners();
      }
    });
  }

  // Force refresh (bypass cache)
  Future<void> refreshAdminRights(NavidromeApi api) async {
    clearCache();
    await checkAdminRights(api);
  }
}