import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/auth_models.dart';
import '../models/backend_models.dart';

class BackendApiClient {
  BackendApiClient({
    required this.baseUrl,
    required this.authToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String? authToken;
  final http.Client _client;

  Future<String> register(String email, String password) async {
    final json = await _requestMap(
      'POST',
      '/auth/register',
      body: <String, dynamic>{'email': email, 'password': password},
    );
    return (json['message'] as String?) ?? 'Inscription réussie';
  }

  Future<AuthTokens> login(
    String email,
    String password, {
    String? otpCode,
  }) async {
    final json = await _requestMap(
      'POST',
      '/auth/login',
      body: <String, dynamic>{
        'email': email,
        'password': password,
        if (otpCode != null && otpCode.isNotEmpty) 'otp_code': otpCode,
      },
    );
    return _tokensFromJson(json);
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    final json = await _requestMap(
      'POST',
      '/auth/refresh',
      body: <String, dynamic>{'refresh_token': refreshToken},
    );
    return _tokensFromJson(json);
  }

  Future<UserProfile> me() async {
    final json = await _requestMap('GET', '/auth/me');
    return UserProfile(
      userId: (json['user_id'] as num).toInt(),
      email: (json['email'] as String?) ?? '',
      displayName: json['display_name'] as String?,
    );
  }

  Future<UserProfile> updateMe(String? displayName) async {
    final json = await _requestMap(
      'PATCH',
      '/auth/me',
      body: <String, dynamic>{'display_name': displayName},
    );
    return UserProfile(
      userId: (json['user_id'] as num).toInt(),
      email: (json['email'] as String?) ?? '',
      displayName: json['display_name'] as String?,
    );
  }

  Future<void> logout(String? refreshToken) async {
    await _requestMap(
      'POST',
      '/auth/logout',
      body: <String, dynamic>{'refresh_token': refreshToken},
    );
  }

  Future<void> deleteMe() async {
    await _requestMap('DELETE', '/auth/me');
  }

  Future<String> resendVerification(String email) async {
    final json = await _requestMap(
      'POST',
      '/auth/resend-verification',
      body: <String, dynamic>{'email': email},
    );
    return (json['message'] as String?) ?? 'Email envoyé';
  }

  Future<String> forgotPassword(String email) async {
    final json = await _requestMap(
      'POST',
      '/auth/forgot-password',
      body: <String, dynamic>{'email': email},
    );
    return (json['message'] as String?) ?? 'Email envoyé';
  }

  Future<String> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final json = await _requestMap(
      'POST',
      '/auth/change-password',
      body: <String, dynamic>{
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
    return (json['message'] as String?) ?? 'Mot de passe modifié';
  }

  Future<List<RemoteWatchlistItem>> getWatchlist({
    String? contentCategory,
  }) async {
    final json = await _requestList(
      'GET',
      '/watchlist',
      query: <String, String>{
        if ((contentCategory?.isNotEmpty ?? false))
          'content_category': contentCategory!,
      },
    );
    return json
        .whereType<Map<String, dynamic>>()
        .map(RemoteWatchlistItem.fromJson)
        .toList();
  }

  Future<void> upsertWatchlist(RemoteWatchlistItem item) async {
    await _requestMap('POST', '/watchlist', body: item.toJson());
  }

  Future<void> deleteWatchlist({
    required int mediaId,
    required String mediaType,
    required String contentCategory,
  }) async {
    await _requestMap(
      'DELETE',
      '/watchlist/$mediaId/$mediaType/$contentCategory',
    );
  }

  Future<void> updateWatchStatus({
    required int mediaId,
    required String mediaType,
    required String contentCategory,
    required String contentStatus,
  }) async {
    await _requestMap(
      'PATCH',
      '/watchlist/$mediaId/$mediaType/$contentCategory/status',
      body: <String, dynamic>{'content_status': contentStatus},
    );
  }

  Future<void> updateWatchTotal({
    required int mediaId,
    required String mediaType,
    required String contentCategory,
    required int totalEpisodes,
  }) async {
    await _requestMap(
      'PATCH',
      '/watchlist/$mediaId/$mediaType/$contentCategory/total-episodes',
      body: <String, dynamic>{'total_episodes': totalEpisodes},
    );
  }

  Future<List<RemoteEpisodeProgress>> getEpisodeProgress(int mediaId) async {
    final json = await _requestList('GET', '/episode-progress/$mediaId');
    return json
        .whereType<Map<String, dynamic>>()
        .map(RemoteEpisodeProgress.fromJson)
        .toList();
  }

  Future<RemoteSyncSnapshot> getSyncSnapshot({int? sinceMillis}) async {
    final json = await _requestMap(
      'GET',
      '/sync/snapshot',
      query: <String, String>{if (sinceMillis != null) 'since': '$sinceMillis'},
    );
    return RemoteSyncSnapshot.fromJson(json);
  }

  Future<void> replaceEpisodeProgress(
    int mediaId,
    List<RemoteEpisodeProgress> items,
  ) async {
    await _requestMap(
      'PUT',
      '/episode-progress/$mediaId',
      body: items.map((e) => e.toJson()).toList(),
    );
  }

  Future<void> deleteEpisodeProgress({
    required int mediaId,
    required int seasonNumber,
    required int episodeNumber,
  }) async {
    await _requestMap(
      'DELETE',
      '/episode-progress/$mediaId/$seasonNumber/$episodeNumber',
    );
  }

  Future<Map<String, dynamic>> _requestMap(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final decoded = await _request(method, path, body: body, query: query);
    if (decoded is Map<String, dynamic>) return decoded;
    throw StateError('Réponse backend invalide: objet attendu');
  }

  Future<List<dynamic>> _requestList(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final decoded = await _request(method, path, body: body, query: query);
    if (decoded is List<dynamic>) return decoded;
    throw StateError('Réponse backend invalide: liste attendue');
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse(_normalizeBase(baseUrl) + path)
        .replace(queryParameters: query);
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authToken != null && authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    final request = http.Request(method, uri)
      ..headers.addAll(headers)
      ..body = body == null ? '' : jsonEncode(body);
    late http.Response response;
    try {
      final streamed = await _client.send(request);
      response = await http.Response.fromStream(streamed);
    } on SocketException {
      if (uri.scheme.toLowerCase() == 'http') {
        throw const AuthException(
          'Impossible de contacter l\'API. BACKEND_BASE_URL utilise HTTP; utilise HTTPS pour la version Android release.',
        );
      }
      throw const AuthException('Impossible de contacter l\'API.');
    } on HandshakeException {
      throw const AuthException(
        'Connexion API sécurisée impossible (certificat TLS invalide).',
      );
    }
    final raw = response.body.isEmpty ? '{}' : response.body;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
      final attemptsRemaining = int.tryParse(
        response.headers['x-auth-attempts-remaining'] ?? '',
      );
      String? detail;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) detail = decoded['detail'] as String?;
      } catch (_) {}
      final friendly = _toFriendlyMessage(detail);
      final requiresOtp =
          detail == 'Two-factor code required' ||
          detail == 'Invalid two-factor code';
      switch (response.statusCode) {
        case 400:
          throw AuthException(
            friendly ??
                'Le mot de passe ne respecte pas les règles de sécurité.',
          );
        case 401:
          throw AuthException(
            friendly ?? 'Identifiants invalides.',
            retryAfterSeconds: retryAfter,
            attemptsRemaining: attemptsRemaining,
            requiresOtp: requiresOtp,
          );
        case 403:
          throw AuthException('Ton email n\'est pas encore vérifié.');
        case 409:
          throw AuthException(
            'Cet email est déjà utilisé.',
            retryAfterSeconds: retryAfter,
            attemptsRemaining: attemptsRemaining,
          );
        case 429:
          throw AuthException(
            'Identifiants invalides à répétition : protection anti-bruteforce activée.',
            retryAfterSeconds: retryAfter,
          );
        case 503:
          throw AuthException(
            friendly ?? 'Service temporairement indisponible.',
          );
        default:
          throw AuthException('Erreur serveur (${response.statusCode}).');
      }
    }
    return jsonDecode(raw);
  }

  static String? _toFriendlyMessage(String? detail) {
    if (detail == null) return null;
    const map = <String, String>{
      'Password must contain at least 10 characters':
          'Le mot de passe doit contenir au moins 10 caractères.',
      'Password must include lower, upper, digit, and symbol': 'Le mot de passe doit inclure une minuscule, une majuscule, un chiffre et un symbole.',
      'Password was already used recently':
          'Ce mot de passe a déjà été utilisé récemment.',
      'New password must be different from current password':
          'Le nouveau mot de passe doit être différent du mot de passe actuel.',
      'Invalid or expired reset token':
          'Le lien de réinitialisation est invalide ou expiré.',
      'Email already exists': 'Cet email est déjà utilisé.',
      'Invalid credentials': 'Identifiants invalides.',
      'Two-factor code required': 'Le code 2FA est requis pour ce compte.',
      'Invalid two-factor code': 'Le code 2FA est invalide.',
      'Admin two-factor authentication is not configured':
          'Le 2FA admin n\'est pas configuré côté serveur.',
      'Current password is invalid': 'Le mot de passe actuel est incorrect.',
      'Invalid token': 'Session expirée. Reconnectez-vous et réessayez.',
      'Token has expired': 'Session expirée. Reconnectez-vous et réessayez.',
      'Not authenticated': 'Session expirée. Reconnectez-vous et réessayez.',
    };
    return map[detail] ?? detail;
  }

  String _normalizeBase(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;

  AuthTokens _tokensFromJson(Map<String, dynamic> json) {
    final accessToken =
        (json['access_token'] as String?) ?? (json['token'] as String?) ?? '';
    if (accessToken.isEmpty) {
      throw StateError('Token backend manquant');
    }
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: json['refresh_token'] as String?,
      expiresInSeconds: (json['expires_in_seconds'] as num?)?.toInt() ?? 3600,
    );
  }
}
