import 'package:shared_preferences/shared_preferences.dart';
import 'navidrome_api.dart';

class AuthService {
  static const _serverUrlKey = 'server_url';
  static const _usernameKey = 'username';
  static const _passwordKey = 'password';

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

  Future<bool> login({
    required String serverUrl, 
    required String username, 
    required String password,
  }) async {
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
      final success = await testApi.ping();
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_serverUrlKey, formattedUrl);
        await prefs.setString(_usernameKey, username);
        await prefs.setString(_passwordKey, password);
        
        _api = testApi;
        return true;
      }
    } catch (e) {
      print('Login error: $e');
    }
    
    return false;
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
}