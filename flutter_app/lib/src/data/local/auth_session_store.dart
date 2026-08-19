import 'package:shared_preferences/shared_preferences.dart';

class AuthSessionStore {
  static const _tokenKey = 'backend_auth_token';
  static const _refreshTokenKey = 'backend_refresh_token';
  static const _tokenExpiresAtKey = 'backend_token_expires_at_ms';
  static const _emailKey = 'backend_username';
  static const _displayNameKey = 'backend_display_name';
  static const _userIdKey = 'backend_user_id';

  Future<String?> token() async =>
      (await SharedPreferences.getInstance()).getString(_tokenKey);
  Future<String?> refreshToken() async =>
      (await SharedPreferences.getInstance()).getString(_refreshTokenKey);
  Future<int?> tokenExpiresAtMillis() async =>
      (await SharedPreferences.getInstance()).getInt(_tokenExpiresAtKey);
  Future<String?> email() async =>
      (await SharedPreferences.getInstance()).getString(_emailKey);
  Future<String?> displayName() async =>
      (await SharedPreferences.getInstance()).getString(_displayNameKey);
  Future<int?> userId() async =>
      (await SharedPreferences.getInstance()).getInt(_userIdKey);

  Future<void> saveTokens({
    required String token,
    required String? refreshToken,
    required int expiresInSeconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    if (refreshToken == null || refreshToken.isEmpty) {
      await prefs.remove(_refreshTokenKey);
    } else {
      await prefs.setString(_refreshTokenKey, refreshToken);
    }
    await prefs.setInt(
      _tokenExpiresAtKey,
      DateTime.now().millisecondsSinceEpoch + (expiresInSeconds * 1000),
    );
  }

  Future<void> saveUserProfile({
    required int userId,
    required String email,
    required String? displayName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userIdKey, userId);
    await prefs.setString(_emailKey, email);
    if (displayName == null || displayName.isEmpty) {
      await prefs.remove(_displayNameKey);
    } else {
      await prefs.setString(_displayNameKey, displayName);
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_tokenExpiresAtKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_displayNameKey);
    await prefs.remove(_userIdKey);
  }
}
