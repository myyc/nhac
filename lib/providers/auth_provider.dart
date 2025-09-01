import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../services/navidrome_api.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  bool _isLoading = true; // Start with loading state to prevent login screen flash
  String? _error;

  bool get isLoading => _isLoading;
  bool get isAuthenticated => _authService.isAuthenticated;
  String? get error => _error;
  NavidromeApi? get api => _authService.api;

  Future<void> initialize() async {
    _isLoading = true;
    _error = null;
    
    try {
      await _authService.loadCredentials();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _authService.login(
        serverUrl: serverUrl,
        username: username,
        password: password,
      );
      
      if (!success) {
        _error = 'Failed to connect to server. Please check your credentials.';
      }
      
      return success;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    await _authService.logout();
    
    _isLoading = false;
    notifyListeners();
  }
}