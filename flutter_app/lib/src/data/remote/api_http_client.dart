import 'dart:convert';

import 'package:http/http.dart' as http;

/// Client HTTP minimal mutualisant la construction d'URI, l'appel réseau,
/// le contrôle du code de statut et le décodage JSON communs aux clients
/// d'API distantes (TMDB, TVDB, ...).
///
/// Ce client ne porte aucune logique de mapping métier : les clients
/// spécifiques restent responsables de construire les chemins/paramètres et
/// de transformer les réponses JSON en modèles applicatifs.
class ApiHttpClient {
  ApiHttpClient({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  /// URL de base de l'API (sans slash final), ex: `https://api.example.com/3`.
  final String baseUrl;
  final http.Client _client;

  /// Effectue un GET brut sur `$baseUrl$path` avec les query parameters et
  /// en-têtes fournis, sans vérifier le statut ni décoder le corps.
  Future<http.Response> getRaw(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    Map<String, String>? headers,
  }) {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    return _client.get(uri, headers: headers);
  }

  /// Effectue un POST JSON brut sur `$baseUrl$path`, sans vérifier le statut
  /// ni décoder le corps.
  Future<http.Response> postRaw(
    String path, {
    Map<String, dynamic> body = const <String, dynamic>{},
    Map<String, String>? headers,
  }) {
    final uri = Uri.parse('$baseUrl$path');
    return _client.post(
      uri,
      headers: {'Content-Type': 'application/json', ...?headers},
      body: jsonEncode(body),
    );
  }

  /// Effectue un GET sur `$baseUrl$path`, vérifie que le statut est un
  /// succès (2xx) puis décode le corps en JSON.
  ///
  /// [errorLabel] personnalise le préfixe du message d'erreur levé en cas
  /// d'échec (ex: `'TMDB'` ou `'TVDB'`).
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    Map<String, String>? headers,
    required String errorLabel,
  }) async {
    final response = await getRaw(
      path,
      queryParameters: queryParameters,
      headers: headers,
    );
    ensureSuccess(response, errorLabel);
    return decodeJson(response);
  }

  /// Effectue un POST JSON sur `$baseUrl$path`, vérifie le statut puis
  /// décode le corps en JSON.
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic> body = const <String, dynamic>{},
    Map<String, String>? headers,
    required String errorLabel,
  }) async {
    final response = await postRaw(path, body: body, headers: headers);
    ensureSuccess(response, errorLabel);
    return decodeJson(response);
  }

  /// Lève une [StateError] si le statut de [response] n'est pas un succès
  /// (2xx).
  void ensureSuccess(http.Response response, String errorLabel) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('$errorLabel ${response.statusCode}: ${response.body}');
    }
  }

  /// Décode le corps de [response] en JSON.
  Map<String, dynamic> decodeJson(http.Response response) {
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
