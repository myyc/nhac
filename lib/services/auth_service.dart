import 'package:shared_preferences/shared_preferences.dart';
import 'navidrome_api.dart';

class LoginResult {
  final bool success;
  final String? error;
  
  LoginResult({required this.success, this.error});
}

class AuthService {
  static const _serverUrlKey = 'server_url';
  static const _usernameKey = 'username';
  static const _passwordKey = 'password';
  
  // Keys for last valid (working) credentials
  static const _lastValidServerKey = 'last_valid_server';
  static const _lastValidUsernameKey = 'last_valid_username';
  static const _lastValidPasswordKey = 'last_valid_password';
  
  // Keys for last attempted credentials (temporary)
  static const _lastAttemptServerKey = 'last_attempt_server';
  static const _lastAttemptUsernameKey = 'last_attempt_username';

  NavidromeApi? _api;
  
  NavidromeApi? get api => _api;
  bool get isAuthenticated => _api != null;

  Future<void> loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString(_serverUrlKey);
    final username = prefs.getString(_usernameKey);
    final password = prefs.getString(_passwordKey);

    if (serverUrl != null && username != null && password != null) {
      _api = NavidromeApi(
        baseUrl: serverUrl,
        username: username,
        password: password,
      );
      
      final isValid = await _api!.ping();
      if (!isValid) {
        _api = null;
        await clearCredentials();
      }
    }
  }

  Future<LoginResult> login({
    required String serverUrl, 
    required String username, 
    required String password,
  }) async {
    // Save the attempt for retry
    await saveLastAttempt(serverUrl, username);
    
    String formattedUrl = serverUrl.trim();
    if (!formattedUrl.startsWith('http://') && !formattedUrl.startsWith('https://')) {
      formattedUrl = 'http://$formattedUrl';
    }
    if (formattedUrl.endsWith('/')) {
      formattedUrl = formattedUrl.substring(0, formattedUrl.length - 1);
    }

    final testApi = NavidromeApi(
      baseUrl: formattedUrl,
      username: username,
      password: password,
    );

    try {
      final result = await testApi.pingWithError();
      if (result.success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_serverUrlKey, formattedUrl);
        await prefs.setString(_usernameKey, username);
        await prefs.setString(_passwordKey, password);
        
        // Save as last valid credentials
        await _saveAsLastValid(formattedUrl, username, password);
        
        _api = testApi;
        return LoginResult(success: true);
      } else {
        return LoginResult(success: false, error: result.error ?? 'Login failed');
      }
    } catch (e) {
      print('Login error: $e');
      return LoginResult(success: false, error: 'Unexpected error: ${e.toString()}');
    }
  }

  Future<void> logout() async {
    _api = null;
    await clearCredentials();
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_serverUrlKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_passwordKey);
  }
  
  /// Get last valid credentials for pre-filling login form
  Future<Map<String, String?>> getLastValidCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    
    // First try to get last valid credentials
    String? server = prefs.getString(_lastValidServerKey);
    String? username = prefs.getString(_lastValidUsernameKey);
    String? password = prefs.getString(_lastValidPasswordKey);
    
    // If no last valid, try current active credentials
    if (server == null || username == null || password == null) {
      server = prefs.getString(_serverUrlKey);
      username = prefs.getString(_usernameKey);
      password = prefs.getString(_passwordKey);
    }
    
    return {
      'server': server,
      'username': username,
      'password': password,
    };
  }
  
  /// Save last attempted credentials (temporary, for current session)
  Future<void> saveLastAttempt(String server, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastAttemptServerKey, server);
    await prefs.setString(_lastAttemptUsernameKey, username);
  }
  
  /// Get last attempted credentials (for retry after error)
  Future<Map<String, String?>> getLastAttemptCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'server': prefs.getString(_lastAttemptServerKey),
      'username': prefs.getString(_lastAttemptUsernameKey),
    };
  }
  
  /// Save credentials as last valid when login succeeds
  Future<void> _saveAsLastValid(String server, String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastValidServerKey, server);
    await prefs.setString(_lastValidUsernameKey, username);
    await prefs.setString(_lastValidPasswordKey, password);
  }
}