import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/details_models.dart';

class TvdbApiClient {
  TvdbApiClient({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const _baseUrl = 'https://api4.thetvdb.com/v4';

  String? _token;

  Future<void> _ensureAuth({bool isRetry = false}) async {
    if (_token != null) return;
    if (apiKey.isEmpty) throw StateError('TVDB_API_KEY manquant');
    final uri = Uri.parse('$_baseUrl/login');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'apikey': apiKey}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('TVDB login ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>?;
    _token = data?['token'] as String?;
    if (_token == null) throw StateError('TVDB login: no token in response');
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> params, {
    bool isRetry = false,
  }) async {
    await _ensureAuth(isRetry: isRetry);
    final uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: params.isEmpty ? null : params,
    );
    final response = await _client.get(
      uri,
      headers: {'Authorization': 'Bearer $_token'},
    );
    if (response.statusCode == 401 && !isRetry) {
      _token = null;
      return _get(path, params, isRetry: true);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('TVDB ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Season>> getSeasonsWithCounts(int tvdbId) async {
    final json = await _get(
      '/series/$tvdbId/extended',
      {'meta': 'episodes', 'short': 'true'},
    );
    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return [];

    final rawSeasons = (data['seasons'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .where((s) {
          final type = s['type'] as Map<String, dynamic>?;
          return (type?['type'] as String?) == 'official';
        })
        .toList();

    // Group episode counts by seasonNumber
    final episodeCounts = <int, int>{};
    for (final ep in (data['episodes'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()) {
      final sn = (ep['seasonNumber'] as num?)?.toInt() ?? 0;
      episodeCounts[sn] = (episodeCounts[sn] ?? 0) + 1;
    }

    // Fetch French season name translations
    Map<int, String> frSeasonNames = {};
    try {
      frSeasonNames = await _getSeasonNameTranslations(tvdbId, 'fra');
    } catch (_) {}

    final seasons = rawSeasons
        .map((s) {
          final number = (s['number'] as num?)?.toInt() ?? 0;
          final count = episodeCounts[number] ?? 0;
          if (number == 0 && count == 0) return null;
          final defaultName = (s['name'] as String?) ??
              (number == 0 ? 'Spéciaux' : 'Saison $number');
          return Season(
            id: (s['id'] as num?)?.toInt() ?? 0,
            name: frSeasonNames[number] ?? _localiseSeasonName(defaultName, number),
            seasonNumber: number,
            episodeCount: count,
          );
        })
        .whereType<Season>()
        .toList()
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));

    return seasons;
  }

  /// Translate generic English season names to French.
  String _localiseSeasonName(String name, int number) {
    if (RegExp(r'^Season\s+\d+$', caseSensitive: false).hasMatch(name)) {
      return 'Saison $number';
    }
    if (name.toLowerCase() == 'specials') return 'Spéciaux';
    return name;
  }

  /// Fetch French season name translations from TVDB.
  /// Returns a map of seasonNumber → translated name.
  Future<Map<int, String>> _getSeasonNameTranslations(
    int tvdbId,
    String lang,
  ) async {
    final json = await _get(
      '/series/$tvdbId/extended',
      {'meta': 'translations', 'short': 'true'},
    );
    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return {};

    final rawSeasons = (data['seasons'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .where((s) {
          final type = s['type'] as Map<String, dynamic>?;
          return (type?['type'] as String?) == 'official';
        });

    final map = <int, String>{};
    for (final s in rawSeasons) {
      final number = (s['number'] as num?)?.toInt() ?? 0;
      // Look in nameTranslations for the target language
      final nameTranslations =
          (s['nameTranslations'] as List<dynamic>? ?? <dynamic>[])
              .whereType<Map<String, dynamic>>();
      for (final t in nameTranslations) {
        if ((t['language'] as String?) == lang) {
          final name = t['name'] as String?;
          if (name != null && name.isNotEmpty) map[number] = name;
          break;
        }
      }
    }
    return map;
  }

  Future<List<Episode>> getSeasonEpisodes(
    int tvdbId,
    int seasonNumber,
  ) async {
    // Fetch with season filter (standard endpoint — reliable filtering)
    final episodes = await _fetchEpisodes(tvdbId, seasonNumber);
    if (episodes.isEmpty) return episodes;

    // Overlay French translations if available
    try {
      final frMap = await _fetchEpisodeTranslationsMap(tvdbId, seasonNumber);
      if (frMap.isNotEmpty) {
        return episodes.map((ep) {
          final tr = frMap[ep.episodeNumber];
          if (tr == null) return ep;
          return Episode(
            id: ep.id,
            name: (tr['name'] as String?)?.isNotEmpty == true
                ? tr['name'] as String
                : ep.name,
            overview: (tr['overview'] as String?)?.isNotEmpty == true
                ? tr['overview'] as String
                : ep.overview,
            episodeNumber: ep.episodeNumber,
            seasonNumber: ep.seasonNumber,
            stillPath: ep.stillPath,
            airDate: ep.airDate,
            runtime: ep.runtime,
          );
        }).toList();
      }
    } catch (_) {}

    return episodes;
  }

  /// Fetch raw episodes for a season using the standard endpoint (supports season filter).
  Future<List<Episode>> _fetchEpisodes(int tvdbId, int seasonNumber) async {
    final episodes = <Episode>[];
    int page = 0;
    while (true) {
      if (page > 20) break;
      final json = await _get('/series/$tvdbId/episodes/official', {
        'page': '$page',
        'season': '$seasonNumber',
      });
      final data = json['data'] as Map<String, dynamic>?;
      final rawEpisodes =
          (data?['episodes'] as List<dynamic>? ?? <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .toList();
      if (rawEpisodes.isEmpty) break;
      for (final ep in rawEpisodes) {
        episodes.add(_episodeFromJson(ep));
      }
      final links = json['links'] as Map<String, dynamic>?;
      if (links?['next'] == null) break;
      page++;
    }
    return episodes;
  }

  /// Fetch French translations for a season's episodes.
  /// Returns a map of episodeNumber → {name, overview}.
  Future<Map<int, Map<String, dynamic>>> _fetchEpisodeTranslationsMap(
    int tvdbId,
    int seasonNumber,
  ) async {
    final map = <int, Map<String, dynamic>>{};
    int page = 0;
    while (true) {
      if (page > 20) break;
      final json = await _get('/series/$tvdbId/episodes/official/fra', {
        'page': '$page',
      });
      final data = json['data'] as Map<String, dynamic>?;
      final rawEpisodes =
          (data?['episodes'] as List<dynamic>? ?? <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .toList();
      if (rawEpisodes.isEmpty) break;

      bool foundSeason = false;
      for (final ep in rawEpisodes) {
        final sn = (ep['seasonNumber'] as num?)?.toInt() ?? -1;
        if (sn == seasonNumber) {
          foundSeason = true;
          final epNum = (ep['number'] as num?)?.toInt() ?? 0;
          map[epNum] = ep;
        }
      }

      final links = json['links'] as Map<String, dynamic>?;
      if (links?['next'] == null) break;
      // Stop early if we've passed our season (episodes are ordered by season)
      if (foundSeason) {
        final lastSn = (rawEpisodes.last['seasonNumber'] as num?)?.toInt() ?? -1;
        if (lastSn > seasonNumber) break;
      }
      page++;
    }
    return map;
  }

  Episode _episodeFromJson(Map<String, dynamic> json) {
    final rawImage = json['image'] as String?;
    String? stillPath;
    if (rawImage != null && rawImage.isNotEmpty) {
      stillPath = rawImage.startsWith('http')
          ? rawImage
          : 'https://artworks.thetvdb.com$rawImage';
    }
    return Episode(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      overview: (json['overview'] as String?) ?? '',
      episodeNumber: (json['number'] as num?)?.toInt() ?? 0,
      seasonNumber: (json['seasonNumber'] as num?)?.toInt() ?? 0,
      stillPath: stillPath,
      airDate: json['aired'] as String?,
      runtime: (json['runtime'] as num?)?.toInt(),
    );
  }
}

