import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/details_models.dart';
import 'watchtracker_database.dart';

/// Service pour gérer le cache hors-ligne des métadonnées de médias/saisons/épisodes
/// Utilise une stratégie Hybrid : TTL 30 jours + LRU avec limite 50 MB
class MetadataCache {
  MetadataCache(this._database);

  final WatchTrackerDatabase _database;

  // Configuration
  static const int cacheTtlDays = 30;
  static const int defaultMaxCacheSizeBytes = 50 * 1024 * 1024; // 50 MB
  static const int minCacheSizeBytes = 10 * 1024 * 1024; // 10 MB
  static const int maxCacheSizeBytesLimit = 500 * 1024 * 1024; // 500 MB
  static const String _maxCacheSizePrefsKey = 'cache_max_size_bytes';

  int? _runtimeMaxCacheSizeBytes;

  /// Sauvegarde les métadonnées d'un média
  Future<void> saveMediaMetadata(
    int mediaId,
    String mediaType,
    MediaDetails details,
  ) async {
    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert('media_metadata', {
      'id': mediaId,
      'media_type': mediaType,
      'title': details.title,
      'overview': details.overview,
      'poster_path': details.posterPath,
      'backdrop_path': details.backdropPath,
      'release_date': details.releaseDate,
      'vote_average': details.voteAverage,
      'genres': details.genres.join(','),
      'tv_status': details.tvStatus?.apiValue,
      'cached_at': now,
      'last_accessed_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _enforceCacheSizeLimit();
  }

  /// Récupère les métadonnées d'un média (met à jour last_accessed_at)
  Future<MediaMetadataRow?> getMediaMetadata(
    int mediaId,
    String mediaType,
  ) async {
    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Mettre à jour last_accessed_at
    await db.update(
      'media_metadata',
      {'last_accessed_at': now},
      where: 'id = ? AND media_type = ?',
      whereArgs: [mediaId, mediaType],
    );

    final result = await db.query(
      'media_metadata',
      where: 'id = ? AND media_type = ?',
      whereArgs: [mediaId, mediaType],
    );

    if (result.isEmpty) return null;
    return MediaMetadataRow.fromMap(result.first);
  }

  /// Sauvegarde les métadonnées de saisons
  Future<void> saveSeasonMetadata(int mediaId, List<Season> seasons) async {
    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Remplace complètement le découpage existant pour éviter les saisons
    // résiduelles d'une source précédente (TMDB vs TVDB).
    await db.delete(
      'season_metadata',
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );

    for (final season in seasons) {
      await db.insert('season_metadata', {
        'media_id': mediaId,
        'season_number': season.seasonNumber,
        'id': season.id,
        'name': season.name,
        'episode_count': season.episodeCount,
        'cached_at': now,
        'last_accessed_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await _enforceCacheSizeLimit();
  }

  /// Récupère les métadonnées des saisons
  Future<List<SeasonMetadataRow>> getSeasonMetadata(int mediaId) async {
    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Mettre à jour last_accessed_at
    await db.update(
      'season_metadata',
      {'last_accessed_at': now},
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );

    final result = await db.query(
      'season_metadata',
      where: 'media_id = ?',
      whereArgs: [mediaId],
      orderBy: 'season_number',
    );

    return result.map(SeasonMetadataRow.fromMap).toList();
  }

  /// Sauvegarde les métadonnées des épisodes
  Future<void> saveEpisodeMetadata(
    int mediaId,
    int seasonNumber,
    List<Episode> episodes,
  ) async {
    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final episode in episodes) {
      await db.insert('episode_metadata', {
        'media_id': mediaId,
        'season_number': seasonNumber,
        'episode_number': episode.episodeNumber,
        'id': episode.id,
        'name': episode.name,
        'overview': episode.overview,
        'still_path': episode.stillPath,
        'air_date': episode.airDate,
        'runtime': episode.runtime,
        'cached_at': now,
        'last_accessed_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await _enforceCacheSizeLimit();
  }

  /// Récupère les métadonnées des épisodes
  Future<List<EpisodeMetadataRow>> getEpisodeMetadata(
    int mediaId,
    int seasonNumber,
  ) async {
    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Mettre à jour last_accessed_at
    await db.update(
      'episode_metadata',
      {'last_accessed_at': now},
      where: 'media_id = ? AND season_number = ?',
      whereArgs: [mediaId, seasonNumber],
    );

    final result = await db.query(
      'episode_metadata',
      where: 'media_id = ? AND season_number = ?',
      whereArgs: [mediaId, seasonNumber],
      orderBy: 'episode_number',
    );

    return result.map(EpisodeMetadataRow.fromMap).toList();
  }

  /// Nettoie le cache en fonction de la stratégie Hybrid (TTL + LRU)
  Future<void> cleanupCache() async {
    final db = await _database.database;
    final now = DateTime.now();
    final expiryThreshold = now.subtract(const Duration(days: cacheTtlDays));

    // 1. Supprimer les entrées expirées
    await db.delete(
      'media_metadata',
      where: 'cached_at < ?',
      whereArgs: [expiryThreshold.millisecondsSinceEpoch],
    );
    await db.delete(
      'season_metadata',
      where: 'cached_at < ?',
      whereArgs: [expiryThreshold.millisecondsSinceEpoch],
    );
    await db.delete(
      'episode_metadata',
      where: 'cached_at < ?',
      whereArgs: [expiryThreshold.millisecondsSinceEpoch],
    );

    // 2. Vérifier la taille du cache
    final maxCacheSizeBytes = await getMaxCacheSizeBytes();
    final cacheSize = await _calculateCacheSize();
    if (cacheSize > maxCacheSizeBytes) {
      // Supprimer les moins récemment utilisées
      await _evictLruItems(cacheSize, maxCacheSizeBytes);
    }
  }

  /// Calcule la taille totale du cache en bytes
  Future<int> _calculateCacheSize() async {
    final db = await _database.database;

    // Estimation basée sur le nombre de lignes * taille moyenne
    final mediaCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM media_metadata'),
    )!;
    final seasonCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM season_metadata'),
    )!;
    final episodeCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM episode_metadata'),
    )!;

    // Taille moyenne par type d'entrée
    const mediaSize = 500; // bytes
    const seasonSize = 100; // bytes
    const episodeSize = 200; // bytes

    return (mediaCount * mediaSize) +
        (seasonCount * seasonSize) +
        (episodeCount * episodeSize);
  }

  Future<void> _enforceCacheSizeLimit() async {
    final maxCacheSizeBytes = await getMaxCacheSizeBytes();
    final cacheSize = await _calculateCacheSize();
    if (cacheSize > maxCacheSizeBytes) {
      await _evictLruItems(cacheSize, maxCacheSizeBytes);
    }
  }

  /// Supprime les éléments les moins récemment utilisés jusqu'à atteindre la limite
  Future<void> _evictLruItems(int currentSize, int maxCacheSizeBytes) async {
    final db = await _database.database;
    final targetSize = (maxCacheSizeBytes * 0.8)
        .toInt(); // Garder 80% de capacité
    final needToFree = currentSize - targetSize;

    // Supprimer les média les moins récemment consultés
    await db.delete(
      'media_metadata',
      where: 'id IN (SELECT id FROM media_metadata ORDER BY last_accessed_at ASC LIMIT ?)',
      whereArgs: [(needToFree / 500).ceil()],
    );

    // Cascade delete des seasons et episodes
    await db.rawDelete('''
      DELETE FROM season_metadata 
      WHERE media_id NOT IN (SELECT id FROM media_metadata)
    ''');
    await db.rawDelete('''
      DELETE FROM episode_metadata 
      WHERE media_id NOT IN (SELECT id FROM media_metadata)
    ''');
  }

  Future<int> getMaxCacheSizeBytes() async {
    final runtimeValue = _runtimeMaxCacheSizeBytes;
    if (runtimeValue != null) return runtimeValue;
    final prefs = await SharedPreferences.getInstance();
    final configured = prefs.getInt(_maxCacheSizePrefsKey);
    final normalized = _normalizeCacheMaxSize(configured);
    _runtimeMaxCacheSizeBytes = normalized;
    return normalized;
  }

  Future<void> setMaxCacheSizeBytes(int bytes) async {
    final normalized = _normalizeCacheMaxSize(bytes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxCacheSizePrefsKey, normalized);
    _runtimeMaxCacheSizeBytes = normalized;
    await _enforceCacheSizeLimit();
  }

  int _normalizeCacheMaxSize(int? bytes) {
    final value = bytes ?? defaultMaxCacheSizeBytes;
    if (value < minCacheSizeBytes) return minCacheSizeBytes;
    if (value > maxCacheSizeBytesLimit) return maxCacheSizeBytesLimit;
    return value;
  }

  /// Supprime tout le cache
  Future<void> clearAllCache() async {
    final db = await _database.database;
    await db.delete('media_metadata');
    await db.delete('season_metadata');
    await db.delete('episode_metadata');
  }

  /// Vérifie si une entrée est en cache et non expirée
  Future<bool> isMediaCached(int mediaId, String mediaType) async {
    final db = await _database.database;
    final expiryThreshold = DateTime.now().subtract(
      const Duration(days: cacheTtlDays),
    );

    final result = await db.query(
      'media_metadata',
      where: 'id = ? AND media_type = ? AND cached_at >= ?',
      whereArgs: [mediaId, mediaType, expiryThreshold.millisecondsSinceEpoch],
    );

    return result.isNotEmpty;
  }

  /// Récupère la taille du cache pour affichage UI
  /// Utilisé dans les Settings pour montrer l'utilisation
  Future<int> getCacheSizeForUI() async {
    return _calculateCacheSize();
  }
}

/// Modèles pour les lignes du cache
class MediaMetadataRow {
  MediaMetadataRow({
    required this.id,
    required this.mediaType,
    required this.title,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.releaseDate,
    required this.voteAverage,
    required this.genres,
    required this.tvStatus,
    required this.cachedAt,
  });

  final int id;
  final String mediaType;
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double voteAverage;
  final List<String> genres;
  final String? tvStatus;
  final int cachedAt;

  factory MediaMetadataRow.fromMap(Map<String, dynamic> map) {
    return MediaMetadataRow(
      id: map['id'] as int,
      mediaType: map['media_type'] as String,
      title: map['title'] as String,
      overview: map['overview'] as String?,
      posterPath: map['poster_path'] as String?,
      backdropPath: map['backdrop_path'] as String?,
      releaseDate: map['release_date'] as String?,
      voteAverage: (map['vote_average'] as num?)?.toDouble() ?? 0.0,
      genres: ((map['genres'] as String?)?.split(',') ?? <String>[])
          .where((g) => g.isNotEmpty)
          .toList(),
      tvStatus: map['tv_status'] as String?,
      cachedAt: map['cached_at'] as int,
    );
  }
}

class SeasonMetadataRow {
  SeasonMetadataRow({
    required this.id,
    required this.mediaId,
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
  });

  final int? id;
  final int mediaId;
  final int seasonNumber;
  final String? name;
  final int? episodeCount;

  factory SeasonMetadataRow.fromMap(Map<String, dynamic> map) {
    return SeasonMetadataRow(
      id: map['id'] as int?,
      mediaId: map['media_id'] as int,
      seasonNumber: map['season_number'] as int,
      name: map['name'] as String?,
      episodeCount: map['episode_count'] as int?,
    );
  }
}

class EpisodeMetadataRow {
  EpisodeMetadataRow({
    required this.id,
    required this.mediaId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.name,
    required this.overview,
    required this.stillPath,
    required this.airDate,
    required this.runtime,
  });

  final int? id;
  final int mediaId;
  final int seasonNumber;
  final int episodeNumber;
  final String? name;
  final String? overview;
  final String? stillPath;
  final String? airDate;
  final int? runtime;

  factory EpisodeMetadataRow.fromMap(Map<String, dynamic> map) {
    return EpisodeMetadataRow(
      id: map['id'] as int?,
      mediaId: map['media_id'] as int,
      seasonNumber: map['season_number'] as int,
      episodeNumber: map['episode_number'] as int,
      name: map['name'] as String?,
      overview: map['overview'] as String?,
      stillPath: map['still_path'] as String?,
      airDate: map['air_date'] as String?,
      runtime: map['runtime'] as int?,
    );
  }
}
