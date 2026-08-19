import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/details_models.dart';
import '../models/media_models.dart';

class TmdbApiClient {
  TmdbApiClient({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const _baseUrl = 'https://api.themoviedb.org/3';

  Future<List<Media>> searchMulti(String query) async {
    final json = await _get('/search/multi', <String, String>{
      'query': query,
      'page': '1',
    });
    final results = (json['results'] as List<dynamic>? ?? <dynamic>[]);
    return results
        .whereType<Map<String, dynamic>>()
        .where(
          (item) => item['media_type'] == 'movie' || item['media_type'] == 'tv',
        )
        .map(_mediaFromJson)
        .toList();
  }

  Future<List<Media>> getUpcomingMovies({int page = 1}) async {
    final json = await _get('/movie/upcoming', <String, String>{
      'page': '$page',
    });
    final results = (json['results'] as List<dynamic>? ?? <dynamic>[]);
    return results
        .whereType<Map<String, dynamic>>()
        .map((item) => _mediaFromJson(item, forceType: MediaType.movie))
        .toList();
  }

  Future<List<Media>> getOnTheAirTv({int page = 1}) async {
    final json = await _get('/tv/on_the_air', <String, String>{
      'page': '$page',
    });
    final results = (json['results'] as List<dynamic>? ?? <dynamic>[]);
    return results
        .whereType<Map<String, dynamic>>()
        .map((item) => _mediaFromJson(item, forceType: MediaType.tv))
        .toList();
  }

  Future<MediaDetails> getMovieDetails(int id) async {
    final json = await _get('/movie/$id', const <String, String>{});
    return _movieDetailsFromJson(json);
  }

  Future<MediaDetails> getTvDetails(int id) async {
    final json = await _get('/tv/$id', const <String, String>{});
    return _tvDetailsFromJson(json);
  }

  Future<int?> getTvdbId(int tmdbId) async {
    try {
      final json = await _get('/tv/$tmdbId/external_ids', const {});
      return (json['tvdb_id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<List<Episode>> getSeasonDetails(int tvId, int seasonNumber) async {
    final json = await _get(
      '/tv/$tvId/season/$seasonNumber',
      const <String, String>{},
    );
    final episodes = (json['episodes'] as List<dynamic>? ?? <dynamic>[]);
    return episodes
        .whereType<Map<String, dynamic>>()
        .map(_episodeFromJson)
        .toList();
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> params,
  ) async {
    if (apiKey.isEmpty) {
      throw StateError('TMDB_API_KEY manquant');
    }
    final uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: <String, String>{
        ...params,
        'api_key': apiKey,
        'language': 'fr-FR',
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('TMDB ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Media _mediaFromJson(Map<String, dynamic> json, {MediaType? forceType}) {
    final mediaType =
        forceType ?? MediaType.fromString(json['media_type'] as String?);
    return Media(
      id: (json['id'] as num).toInt(),
      title:
          (json['title'] as String?) ?? (json['name'] as String?) ?? 'Unknown',
      posterPath: _fullImage(json['poster_path'] as String?, width: 'w500'),
      backdropPath: _fullImage(json['backdrop_path'] as String?, width: 'w780'),
      overview: (json['overview'] as String?) ?? '',
      releaseDate:
          (json['release_date'] as String?) ??
          (json['first_air_date'] as String?),
      voteAverage: ((json['vote_average'] as num?) ?? 0).toDouble(),
      mediaType: mediaType,
      genreIds: ((json['genre_ids'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<num>()
          .map((e) => e.toInt())
          .toList(),
    );
  }

  MediaDetails _movieDetailsFromJson(Map<String, dynamic> json) {
    return MediaDetails(
      id: (json['id'] as num).toInt(),
      title: (json['title'] as String?) ?? '',
      overview: (json['overview'] as String?) ?? '',
      posterPath: _fullImage(json['poster_path'] as String?, width: 'w500'),
      backdropPath: _fullImage(json['backdrop_path'] as String?, width: 'w780'),
      releaseDate: json['release_date'] as String?,
      voteAverage: ((json['vote_average'] as num?) ?? 0).toDouble(),
      mediaType: MediaType.movie,
      genres: ((json['genres'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map((g) => (g['name'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }

  MediaDetails _tvDetailsFromJson(Map<String, dynamic> json) {
    final seasons = ((json['seasons'] as List<dynamic>?) ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((s) {
          return Season(
            id: (s['id'] as num?)?.toInt() ?? 0,
            name: (s['name'] as String?) ?? '',
            seasonNumber: (s['season_number'] as num?)?.toInt() ?? 0,
            episodeCount: (s['episode_count'] as num?)?.toInt() ?? 0,
          );
        })
        .toList();
    return MediaDetails(
      id: (json['id'] as num).toInt(),
      title: (json['name'] as String?) ?? '',
      overview: (json['overview'] as String?) ?? '',
      posterPath: _fullImage(json['poster_path'] as String?, width: 'w500'),
      backdropPath: _fullImage(json['backdrop_path'] as String?, width: 'w780'),
      releaseDate: json['first_air_date'] as String?,
      voteAverage: ((json['vote_average'] as num?) ?? 0).toDouble(),
      mediaType: MediaType.tv,
      tvStatus: TvStatus.fromApiValue(json['status'] as String?),
      genres: ((json['genres'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map((g) => (g['name'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
      seasons: seasons,
    );
  }

  Episode _episodeFromJson(Map<String, dynamic> json) {
    return Episode(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      overview: (json['overview'] as String?) ?? '',
      episodeNumber: (json['episode_number'] as num?)?.toInt() ?? 0,
      seasonNumber: (json['season_number'] as num?)?.toInt() ?? 0,
      stillPath: _fullImage(json['still_path'] as String?, width: 'w300'),
      airDate: json['air_date'] as String?,
      runtime: (json['runtime'] as num?)?.toInt(),
    );
  }

  String? _fullImage(String? rawPath, {required String width}) {
    if (rawPath == null || rawPath.isEmpty) return null;
    return 'https://image.tmdb.org/t/p/$width$rawPath';
  }
}
