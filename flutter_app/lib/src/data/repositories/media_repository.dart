import 'package:flutter/foundation.dart';

import '../local/watchtracker_database.dart';
import '../models/auth_models.dart';
import '../models/backend_models.dart';
import '../models/details_models.dart';
import '../models/media_models.dart';
import '../remote/tvdb_api_client.dart';
import '../remote/backend_api_client.dart';
import '../remote/tmdb_api_client.dart';

class MediaRepository {
  MediaRepository(
    this._tmdbApi,
    this._tvdbClient,
    this._database, {
    String? backendBaseUrl,
  }) {
    setBackendBaseUrl(backendBaseUrl);
  }

  final TmdbApiClient _tmdbApi;
  final TvdbApiClient? _tvdbClient;
  final WatchTrackerDatabase _database;
  final Map<int, int?> _tvdbIdCache = {};
  final Map<String, List<Episode>> _seasonEpisodesCache = {};
  final Map<String, Future<List<Episode>>> _seasonEpisodesInFlight = {};
  final ValueNotifier<int> watchlistVersion = ValueNotifier<int>(0);

  String? _backendBaseUrl;
  String? _backendAuthToken;
  BackendApiClient? _backendApi;

  void setBackendBaseUrl(String? baseUrl) {
    final normalized = (baseUrl ?? '').trim();
    _backendBaseUrl = normalized.isEmpty ? null : normalized;
    _rebuildBackendApi();
  }

  void setBackendAuthToken(String? token) {
    _backendAuthToken = (token ?? '').trim().isEmpty ? null : token?.trim();
    _rebuildBackendApi();
  }

  Future<String> register(String email, String password) async {
    final backend = _requireBackend();
    return backend.register(email, password);
  }

  Future<AuthTokens> login(
    String email,
    String password, {
    String? otpCode,
  }) async {
    final backend = _requireBackend();
    return backend.login(email, password, otpCode: otpCode);
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    final backend = _requireBackend();
    return backend.refresh(refreshToken);
  }

  Future<String> resendVerification(String email) async {
    final backend = _requireBackend();
    return backend.resendVerification(email);
  }

  Future<String> forgotPassword(String email) async {
    final backend = _requireBackend();
    return backend.forgotPassword(email);
  }

  Future<String> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final backend = _requireBackend();
    return backend.changePassword(currentPassword, newPassword);
  }

  Future<void> logout(String? refreshToken) async {
    final backend = _backendApi;
    if (backend == null) return;
    await backend.logout(refreshToken);
  }

  Future<UserProfile?> getCurrentUserProfile() async {
    final backend = _backendApi;
    if (backend == null) return null;
    return backend.me();
  }

  Future<UserProfile?> updateCurrentUserDisplayName(String? displayName) async {
    final backend = _backendApi;
    if (backend == null) return null;
    return backend.updateMe(displayName);
  }

  Future<void> deleteCurrentUserAccount() async {
    final backend = _requireBackend();
    await backend.deleteMe();
  }

  Future<List<Media>> searchMedia(String query) => _tmdbApi.searchMulti(query);

  Future<List<Media>> getDiscoveryMedia() async {
    final movies = await _tmdbApi.getUpcomingMovies(page: 1);
    final tv = await _tmdbApi.getOnTheAirTv(page: 1);
    final tracked = await getTrackedMediaKeys();
    final pool = <Media>[
      ...movies,
      ...tv,
    ].where((m) => !tracked.contains('${m.mediaType.value}_${m.id}')).toList();
    pool.shuffle();
    return pool.take(32).toList();
  }

  Future<List<WatchlistItem>> getWatchlist(WatchCategory category) async {
    final rows = await _database.watchlistByCategory(category);
    return rows.map((row) {
      final mediaType = MediaType.fromString(row['media_type'] as String?);
      final totalEpisodes = (row['total_episodes'] as num?)?.toInt() ?? 0;
      final status = WatchStatus.fromString(row['content_status'] as String?);
      final watchedEpisodesDb = (row['watched_episodes'] as num?)?.toInt() ?? 0;
      final lastWatchedAt = (row['last_watched_at'] as num?)?.toInt();

      final isMovie = mediaType == MediaType.movie;
      final watchedEpisodes = isMovie
          ? (status == WatchStatus.watched ? 1 : 0)
          : watchedEpisodesDb;

      return WatchlistItem(
        media: Media(
          id: (row['id'] as num).toInt(),
          title: row['title'] as String? ?? '',
          posterPath: row['poster_path'] as String?,
          backdropPath: null,
          overview: '',
          releaseDate: null,
          voteAverage: 0,
          mediaType: mediaType,
        ),
        status: status,
        watchedEpisodes: watchedEpisodes,
        totalEpisodes: isMovie ? 1 : totalEpisodes,
        lastWatchedAt: lastWatchedAt,
      );
    }).toList();
  }

  Future<void> addToWatchlist(
    Media media,
    WatchCategory category,
    WatchStatus status,
    int totalEpisodes,
  ) async {
    await _database.addToWatchlist(
      id: media.id,
      title: media.title,
      posterPath: media.posterPath,
      mediaType: media.mediaType,
      category: category,
      status: status,
      totalEpisodes: totalEpisodes,
    );
    final backend = _backendApi;
    if (backend != null) {
      await backend.upsertWatchlist(
        RemoteWatchlistItem(
          id: media.id,
          title: media.title,
          posterPath: media.posterPath,
          mediaType: media.mediaType.value,
          contentCategory: category.value,
          contentStatus: status.value,
          totalEpisodes: totalEpisodes,
        ),
      );
    }
    _notifyWatchlistChanged();
  }

  Future<void> removeFromWatchlist(Media media, WatchCategory category) async {
    await _database.removeFromWatchlist(
      id: media.id,
      mediaType: media.mediaType,
      category: category,
    );
    final backend = _backendApi;
    if (backend != null) {
      await backend.deleteWatchlist(
        mediaId: media.id,
        mediaType: media.mediaType.value,
        contentCategory: category.value,
      );
    }
    _notifyWatchlistChanged();
  }

  Future<void> updateWatchStatus(
    Media media,
    WatchCategory category,
    WatchStatus status,
  ) async {
    await _database.updateWatchStatus(
      id: media.id,
      mediaType: media.mediaType,
      category: category,
      status: status,
    );
    final backend = _backendApi;
    if (backend != null) {
      await backend.updateWatchStatus(
        mediaId: media.id,
        mediaType: media.mediaType.value,
        contentCategory: category.value,
        contentStatus: status.value,
      );
    }
    _notifyWatchlistChanged();
  }

  Future<void> updateWatchProgressTotal(
    Media media,
    WatchCategory category,
    int totalEpisodes,
  ) async {
    await _database.updateWatchTotal(
      id: media.id,
      mediaType: media.mediaType,
      category: category,
      totalEpisodes: totalEpisodes,
    );
    final backend = _backendApi;
    if (backend != null) {
      await backend.updateWatchTotal(
        mediaId: media.id,
        mediaType: media.mediaType.value,
        contentCategory: category.value,
        totalEpisodes: totalEpisodes,
      );
    }
    _notifyWatchlistChanged();
  }

  Future<bool> isInWatchlist(int id, MediaType type, WatchCategory category) {
    return _database.isInWatchlist(id: id, mediaType: type, category: category);
  }

  Future<Set<String>> getTrackedMediaKeys() async {
    final rows = await _database.allWatchlist();
    return rows.map((r) => '${r['media_type']}_${r['id']}').toSet();
  }

  Future<List<WatchCategory>> getTrackedCategoriesForMedia(
    int id,
    MediaType type,
  ) {
    return _database.trackedCategoriesForMedia(id: id, mediaType: type);
  }

  Future<WatchStatus?> getWatchStatus(
    int id,
    MediaType type,
    WatchCategory category,
  ) {
    return _database.getWatchStatus(
      id: id,
      mediaType: type,
      category: category,
    );
  }

  Future<int?> getMovieFirstWatchedAt(int mediaId) {
    return _database.firstMovieWatchAt(mediaId);
  }

  Future<int> getMovieViewCount(int mediaId) {
    return _database.countMovieWatchEvents(mediaId);
  }

  Future<void> markMovieWatched(
    Media media,
    WatchCategory category, {
    bool rewatch = false,
    int? watchedAtMillis,
  }) async {
    final status = await getWatchStatus(media.id, media.mediaType, category);
    if (!rewatch && status != WatchStatus.watched) {
      await _database.addMovieWatchEvent(
        mediaId: media.id,
        watchedAtMillis: watchedAtMillis,
      );
    } else if (rewatch) {
      await _database.addMovieWatchEvent(
        mediaId: media.id,
        watchedAtMillis: watchedAtMillis,
      );
    }
    await updateWatchStatus(media, category, WatchStatus.watched);
  }

  Future<void> markMovieUnwatched(Media media, WatchCategory category) async {
    await _database.clearMovieWatchEvents(media.id);
    await updateWatchStatus(media, category, WatchStatus.notWatched);
  }

  Future<MediaDetails> getMovieDetails(int id) => _tmdbApi.getMovieDetails(id);
  Future<MediaDetails> getTvDetailsFast(int id) => _tmdbApi.getTvDetails(id);

  Future<int?> _getTvdbId(int tmdbId) async {
    if (_tvdbIdCache.containsKey(tmdbId)) return _tvdbIdCache[tmdbId];
    final tvdb = _tvdbClient;
    if (tvdb == null) {
      _tvdbIdCache[tmdbId] = null;
      return null;
    }
    final id = await _tmdbApi.getTvdbId(tmdbId);
    _tvdbIdCache[tmdbId] = id;
    return id;
  }

  Future<MediaDetails> getTvDetails(int id) async {
    final details = await getTvDetailsFast(id);
    if (details.watchCategory() != WatchCategory.anime) return details;
    final tvdb = _tvdbClient;
    if (tvdb == null) return details;
    try {
      final tvdbId = await _getTvdbId(id);
      if (tvdbId == null) return details;
      final seasons = await tvdb.getSeasonsWithCounts(tvdbId);
      if (seasons.isEmpty) return details;
      return MediaDetails(
        id: details.id,
        title: details.title,
        overview: details.overview,
        posterPath: details.posterPath,
        backdropPath: details.backdropPath,
        releaseDate: details.releaseDate,
        voteAverage: details.voteAverage,
        mediaType: details.mediaType,
        tvStatus: details.tvStatus,
        genres: details.genres,
        seasons: seasons,
      );
    } catch (_) {
      return details;
    }
  }

  Future<List<Episode>> getSeasonEpisodes(int tvId, int seasonNumber) async {
    final cacheKey = '${tvId}_$seasonNumber';
    final cached = _seasonEpisodesCache[cacheKey];
    if (cached != null) return cached;
    final inFlight = _seasonEpisodesInFlight[cacheKey];
    if (inFlight != null) return inFlight;

    final tvdb = _tvdbClient;
    final future = (() async {
      List<Episode> episodes;
      if (tvdb != null) {
        final tvdbId = _tvdbIdCache[tvId];
        if (tvdbId != null) {
          try {
            episodes = await tvdb.getSeasonEpisodes(tvdbId, seasonNumber);
            _seasonEpisodesCache[cacheKey] = episodes;
            return episodes;
          } catch (_) {}
        }
      }
      episodes = await _tmdbApi.getSeasonDetails(tvId, seasonNumber);
      _seasonEpisodesCache[cacheKey] = episodes;
      return episodes;
    })();
    _seasonEpisodesInFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _seasonEpisodesInFlight.remove(cacheKey);
    }
  }

  Future<void> prefetchSeasonEpisodes(MediaDetails details) async {
    if (details.mediaType != MediaType.tv) return;
    final seasons =
        details.seasons
            .where((s) => s.seasonNumber != 0)
            .map((s) => s.seasonNumber)
            .toList()
          ..sort();
    if (seasons.isEmpty) return;
    await Future.wait(
      seasons.map((seasonNumber) async {
        final cacheKey = '${details.id}_$seasonNumber';
        if (_seasonEpisodesCache.containsKey(cacheKey)) return;
        try {
          await getSeasonEpisodes(details.id, seasonNumber);
        } catch (_) {}
      }),
    );
  }

  Future<List<RemoteEpisodeProgress>> getEpisodeProgress(int mediaId) async {
    final rows = await _database.episodeProgress(mediaId);
    return rows
        .map(
          (row) => RemoteEpisodeProgress(
            mediaId: mediaId,
            seasonNumber: (row['season_number'] as num).toInt(),
            episodeNumber: (row['episode_number'] as num).toInt(),
            isWatched: ((row['is_watched'] as num?)?.toInt() ?? 0) == 1,
            updatedAtMillis: (row['updated_at'] as num?)?.toInt(),
          ),
        )
        .toList();
  }

  Future<void> updateEpisodeProgress({
    required int mediaId,
    required int seasonNumber,
    required int episodeNumber,
    required bool isWatched,
    int? updatedAtMillis,
  }) async {
    await _database.upsertEpisodeProgress(
      mediaId: mediaId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      isWatched: isWatched,
      updatedAtMillis: updatedAtMillis,
    );
    final backend = _backendApi;
    if (backend != null) {
      await backend.replaceEpisodeProgress(
        mediaId,
        await getEpisodeProgress(mediaId),
      );
    }
    _notifyWatchlistChanged();
  }

  Future<void> markEpisodeWatched({
    required int mediaId,
    required int seasonNumber,
    required int episodeNumber,
    required bool rewatch,
    int? watchedAtMillis,
  }) async {
    if (rewatch) {
      await _database.addEpisodeWatchEvent(
        mediaId: mediaId,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        watchedAtMillis: watchedAtMillis,
      );
    } else {
      await _database.markEpisodeWatchedIfNeeded(
        mediaId: mediaId,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        watchedAtMillis: watchedAtMillis,
      );
    }
    final backend = _backendApi;
    if (backend != null) {
      await backend.replaceEpisodeProgress(
        mediaId,
        await getEpisodeProgress(mediaId),
      );
    }
    _notifyWatchlistChanged();
  }

  Future<void> markEpisodeUnwatched({
    required int mediaId,
    required int seasonNumber,
    required int episodeNumber,
  }) async {
    await _database.clearEpisodeWatchEvents(
      mediaId: mediaId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
    final backend = _backendApi;
    if (backend != null) {
      await backend.replaceEpisodeProgress(
        mediaId,
        await getEpisodeProgress(mediaId),
      );
    }
    _notifyWatchlistChanged();
  }

  Future<void> markEpisodeBatch({
    required int mediaId,
    required List<RemoteEpisodeProgress> updates,
    required bool includeAlreadyWatchedForMarked,
  }) async {
    if (updates.isEmpty) return;
    final watchedUpdates = updates
        .where((u) => u.isWatched)
        .map(
          (u) => <String, int>{
            'season_number': u.seasonNumber,
            'episode_number': u.episodeNumber,
          },
        )
        .toList();
    final unwatchedUpdates = updates
        .where((u) => !u.isWatched)
        .map(
          (u) => <String, int>{
            'season_number': u.seasonNumber,
            'episode_number': u.episodeNumber,
          },
        )
        .toList();
    final sharedTs = updates.first.updatedAtMillis;
    if (watchedUpdates.isNotEmpty) {
      await _database.addEpisodeWatchEventsBatch(
        mediaId: mediaId,
        episodes: watchedUpdates,
        watchedAtMillis: sharedTs,
        includeAlreadyWatched: includeAlreadyWatchedForMarked,
      );
    }
    if (unwatchedUpdates.isNotEmpty) {
      await _database.clearEpisodeWatchEventsBatch(
        mediaId: mediaId,
        episodes: unwatchedUpdates,
      );
    }
    final backend = _backendApi;
    if (backend != null) {
      await backend.replaceEpisodeProgress(
        mediaId,
        await getEpisodeProgress(mediaId),
      );
    }
    _notifyWatchlistChanged();
  }

  Future<int> getEpisodeViewCount({
    required int mediaId,
    required int seasonNumber,
    required int episodeNumber,
  }) {
    return _database.countEpisodeWatchEvents(
      mediaId: mediaId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
  }

  Future<void> updateEpisodeProgressBatch({
    required int mediaId,
    required List<RemoteEpisodeProgress> updates,
  }) async {
    if (updates.isEmpty) return;
    await _database.upsertEpisodeProgressBatch(
      mediaId: mediaId,
      updates: updates
          .map(
            (u) => <String, Object?>{
              'season_number': u.seasonNumber,
              'episode_number': u.episodeNumber,
              'is_watched': u.isWatched ? 1 : 0,
            },
          )
          .toList(),
    );
    final backend = _backendApi;
    if (backend != null) {
      await backend.replaceEpisodeProgress(
        mediaId,
        await getEpisodeProgress(mediaId),
      );
    }
    _notifyWatchlistChanged();
  }

  Future<void> synchronizeWithBackend() async {
    final backend = _backendApi;
    if (backend == null) return;
    final sinceMillis = await _database.getSyncState('last_sync_at_millis');
    final snapshot = await backend.getSyncSnapshot(sinceMillis: sinceMillis);

    final localWatchlistRows = await _database.allWatchlist();
    final localWatchlist = localWatchlistRows
        .map(_watchlistItemFromLocalRow)
        .toList();
    final localTombstoneRows = await _database.allWatchlistTombstones();
    final localTombstones = localTombstoneRows
        .map(_watchlistTombstoneFromLocalRow)
        .toList();
    final remoteWatchlist = snapshot.watchlist;
    final remoteTombstones = snapshot.watchlistTombstones;
    final mergedTombstones = _mergeWatchlistTombstones(
      localTombstones,
      remoteTombstones,
    );

    final localWatchByKey = {
      for (final item in localWatchlist) _watchlistKey(item): item,
    };
    final remoteWatchByKey = {
      for (final item in remoteWatchlist) _watchlistKey(item): item,
    };
    final tombstoneByKey = {
      for (final item in mergedTombstones) _watchlistTombstoneKey(item): item,
    };

    final mergedWatchlist = <RemoteWatchlistItem>[];
    final pushWatchlist = <RemoteWatchlistItem>[];
    final pushDeletes = <RemoteWatchlistTombstone>[];

    final allWatchKeys = <String>{
      ...localWatchByKey.keys,
      ...remoteWatchByKey.keys,
      ...tombstoneByKey.keys,
    };
    for (final key in allWatchKeys) {
      final local = localWatchByKey[key];
      final remote = remoteWatchByKey[key];
      final tombstone = tombstoneByKey[key];
      final localUpdated = local?.updatedAtMillis ?? 0;
      final remoteUpdated = remote?.updatedAtMillis ?? 0;
      final deletedByTombstone =
          tombstone != null &&
          tombstone.deletedAtMillis >= localUpdated &&
          tombstone.deletedAtMillis >= remoteUpdated;

      if (deletedByTombstone) {
        if (local != null) {
          await _database.applyRemoteWatchlistDeletion(
            id: local.id,
            mediaType: MediaType.fromString(local.mediaType),
            category: WatchCategory.fromString(local.contentCategory),
            deletedAtMillis: tombstone.deletedAtMillis,
          );
        }
        final shouldPushDelete =
            local != null &&
            (sinceMillis == null ||
                (local.updatedAtMillis ?? 0) > sinceMillis) &&
            (tombstone.deletedAtMillis >= remoteUpdated);
        if (shouldPushDelete) {
          pushDeletes.add(tombstone);
        }
        continue;
      }

      final chosen = remote == null
          ? local
          : local == null
          ? remote
          : _preferLocalWatchlist(local, remote)
          ? local
          : remote;
      if (chosen != null) {
        mergedWatchlist.add(chosen);
      }

      if (local != null) {
        final localWins = remote == null
            ? sinceMillis == null || (local.updatedAtMillis ?? 0) > sinceMillis
            : _preferLocalWatchlist(local, remote);
        if (localWins) {
          pushWatchlist.add(local);
        }
      }
    }

    for (final item in mergedWatchlist) {
      await _database.addToWatchlist(
        id: item.id,
        title: item.title,
        posterPath: item.posterPath,
        mediaType: MediaType.fromString(item.mediaType),
        category: WatchCategory.fromString(item.contentCategory),
        status: WatchStatus.fromString(item.contentStatus),
        totalEpisodes: item.totalEpisodes,
        addedAtMillis: item.addedAtMillis,
        updatedAtMillis: item.updatedAtMillis,
      );
    }

    for (final tombstone in mergedTombstones) {
      await _database.applyRemoteWatchlistDeletion(
        id: tombstone.id,
        mediaType: MediaType.fromString(tombstone.mediaType),
        category: WatchCategory.fromString(tombstone.contentCategory),
        deletedAtMillis: tombstone.deletedAtMillis,
      );
    }

    for (final item in pushWatchlist) {
      await backend.upsertWatchlist(item);
    }
    for (final tombstone in pushDeletes) {
      await backend.deleteWatchlist(
        mediaId: tombstone.id,
        mediaType: tombstone.mediaType,
        contentCategory: tombstone.contentCategory,
      );
    }

    final localEpisodeRows = await _database.allEpisodeProgress();
    final localProgress = localEpisodeRows
        .map(
          (row) => RemoteEpisodeProgress(
            mediaId: (row['media_id'] as num?)?.toInt(),
            seasonNumber: (row['season_number'] as num).toInt(),
            episodeNumber: (row['episode_number'] as num).toInt(),
            isWatched: ((row['is_watched'] as num?)?.toInt() ?? 0) == 1,
            updatedAtMillis: (row['updated_at'] as num?)?.toInt(),
          ),
        )
        .toList();
    final localProgressByKey = {
      for (final item in localProgress) _episodeKey(item): item,
    };
    final remoteProgressByKey = {
      for (final item in snapshot.episodeProgress) _episodeKey(item): item,
    };
    final episodeTombstones = {
      for (final item in snapshot.episodeProgressTombstones)
        '${item.mediaId}_${item.seasonNumber}_${item.episodeNumber}': item,
    };

    final mergedProgress = <RemoteEpisodeProgress>[];
    final pushProgress = <RemoteEpisodeProgress>[];
    final pushEpisodeDeletes = <RemoteEpisodeProgressTombstone>[];
    final allProgressKeys = <String>{
      ...localProgressByKey.keys,
      ...remoteProgressByKey.keys,
      ...episodeTombstones.keys,
    };
    for (final key in allProgressKeys) {
      final local = localProgressByKey[key];
      final remote = remoteProgressByKey[key];
      final tombstone = episodeTombstones[key];
      final localUpdated = local?.updatedAtMillis ?? 0;
      final remoteUpdated = remote?.updatedAtMillis ?? 0;
      final deletedByTombstone =
          tombstone != null &&
          tombstone.deletedAtMillis >= localUpdated &&
          tombstone.deletedAtMillis >= remoteUpdated;

      if (deletedByTombstone) {
        if (local != null) {
          await _database.applyRemoteEpisodeProgressDeletion(
            mediaId: local.mediaId!,
            seasonNumber: local.seasonNumber,
            episodeNumber: local.episodeNumber,
            deletedAtMillis: tombstone.deletedAtMillis,
          );
        }
        final shouldPushDelete =
            local != null &&
            (sinceMillis == null ||
                (local.updatedAtMillis ?? 0) > sinceMillis) &&
            (tombstone.deletedAtMillis >= remoteUpdated);
        if (shouldPushDelete) {
          pushEpisodeDeletes.add(tombstone);
        }
        continue;
      }

      final chosen = remote == null
          ? local
          : local == null
          ? remote
          : _preferLocalEpisode(local, remote)
          ? local
          : remote;
      if (chosen != null) {
        mergedProgress.add(chosen);
      }

      if (local != null) {
        final localWins = remote == null
            ? sinceMillis == null || (local.updatedAtMillis ?? 0) > sinceMillis
            : _preferLocalEpisode(local, remote);
        if (localWins) {
          pushProgress.add(local);
        }
      }
    }

    final byMedia = <int, List<RemoteEpisodeProgress>>{};
    for (final item in mergedProgress) {
      final mediaId = item.mediaId;
      if (mediaId == null) continue;
      byMedia.putIfAbsent(mediaId, () => <RemoteEpisodeProgress>[]).add(item);
    }

    for (final entry in byMedia.entries) {
      final mediaId = entry.key;
      final items = entry.value;
      await _database.upsertEpisodeProgressBatch(
        mediaId: mediaId,
        updates: items
            .map(
              (u) => <String, Object?>{
                'season_number': u.seasonNumber,
                'episode_number': u.episodeNumber,
                'is_watched': u.isWatched ? 1 : 0,
                'updated_at': u.updatedAtMillis,
              },
            )
            .toList(),
      );
    }

    for (final item in pushProgress) {
      if (item.mediaId == null) continue;
      await backend.replaceEpisodeProgress(item.mediaId!, [
        RemoteEpisodeProgress(
          mediaId: item.mediaId,
          seasonNumber: item.seasonNumber,
          episodeNumber: item.episodeNumber,
          isWatched: item.isWatched,
        ),
      ]);
    }
    for (final tombstone in pushEpisodeDeletes) {
      await backend.deleteEpisodeProgress(
        mediaId: tombstone.mediaId,
        seasonNumber: tombstone.seasonNumber,
        episodeNumber: tombstone.episodeNumber,
      );
    }

    await _database.setSyncState(
      'last_sync_at_millis',
      snapshot.snapshotAtMillis,
    );
    _notifyWatchlistChanged();
  }

  RemoteWatchlistItem _watchlistItemFromLocalRow(Map<String, Object?> row) {
    return RemoteWatchlistItem(
      id: (row['id'] as num).toInt(),
      title: row['title'] as String? ?? '',
      posterPath: row['poster_path'] as String?,
      mediaType: row['media_type'] as String? ?? MediaType.movie.value,
      contentCategory:
          row['content_category'] as String? ?? WatchCategory.series.value,
      contentStatus:
          row['content_status'] as String? ?? WatchStatus.notStarted.value,
      totalEpisodes: (row['total_episodes'] as num?)?.toInt() ?? 0,
      addedAtMillis: (row['added_at'] as num?)?.toInt(),
      updatedAtMillis: (row['updated_at'] as num?)?.toInt(),
    );
  }

  RemoteWatchlistTombstone _watchlistTombstoneFromLocalRow(
    Map<String, Object?> row,
  ) {
    return RemoteWatchlistTombstone(
      id: (row['id'] as num).toInt(),
      mediaType: row['media_type'] as String? ?? MediaType.movie.value,
      contentCategory:
          row['content_category'] as String? ?? WatchCategory.series.value,
      deletedAtMillis: (row['deleted_at'] as num?)?.toInt() ?? 0,
    );
  }

  List<RemoteWatchlistTombstone> _mergeWatchlistTombstones(
    List<RemoteWatchlistTombstone> local,
    List<RemoteWatchlistTombstone> remote,
  ) {
    final map = <String, RemoteWatchlistTombstone>{};
    for (final item in [...remote, ...local]) {
      final key = _watchlistTombstoneKey(item);
      final existing = map[key];
      if (existing == null || item.deletedAtMillis > existing.deletedAtMillis) {
        map[key] = item;
      }
    }
    return map.values.toList();
  }

  bool _preferLocalWatchlist(
    RemoteWatchlistItem local,
    RemoteWatchlistItem remote,
  ) {
    final localUpdated = local.updatedAtMillis ?? 0;
    final remoteUpdated = remote.updatedAtMillis ?? 0;
    if (localUpdated != remoteUpdated) return localUpdated > remoteUpdated;
    final localStatus = WatchStatus.fromString(local.contentStatus);
    final remoteStatus = WatchStatus.fromString(remote.contentStatus);
    final sameContent =
        local.title == remote.title &&
        local.posterPath == remote.posterPath &&
        local.contentStatus == remote.contentStatus &&
        local.totalEpisodes == remote.totalEpisodes;
    if (sameContent) return false;
    return _statusRank(localStatus) >= _statusRank(remoteStatus) &&
        local.totalEpisodes >= remote.totalEpisodes;
  }

  bool _preferLocalEpisode(
    RemoteEpisodeProgress local,
    RemoteEpisodeProgress remote,
  ) {
    final localUpdated = local.updatedAtMillis ?? 0;
    final remoteUpdated = remote.updatedAtMillis ?? 0;
    if (localUpdated != remoteUpdated) return localUpdated > remoteUpdated;
    return local.isWatched && !remote.isWatched;
  }

  int _statusRank(WatchStatus status) {
    return switch (status) {
      WatchStatus.notStarted => 0,
      WatchStatus.inProgress => 1,
      WatchStatus.upToDate => 2,
      WatchStatus.completed => 3,
      WatchStatus.watched => 4,
      WatchStatus.notWatched => -1,
    };
  }

  String _watchlistKey(RemoteWatchlistItem item) =>
      '${item.id}_${item.mediaType}_${item.contentCategory}';

  String _watchlistTombstoneKey(RemoteWatchlistTombstone item) =>
      '${item.id}_${item.mediaType}_${item.contentCategory}';

  String _episodeKey(RemoteEpisodeProgress item) =>
      '${item.mediaId}_${item.seasonNumber}_${item.episodeNumber}';

  Future<void> clearLocalSessionData() async {
    await _database.clearSessionData();
    _notifyWatchlistChanged();
  }

  void _rebuildBackendApi() {
    final base = _backendBaseUrl;
    if (base == null || base.isEmpty) {
      _backendApi = null;
      return;
    }
    _backendApi = BackendApiClient(baseUrl: base, authToken: _backendAuthToken);
  }

  BackendApiClient _requireBackend() {
    final backend = _backendApi;
    if (backend == null) {
      throw StateError('BACKEND_BASE_URL manquant');
    }
    return backend;
  }

  void _notifyWatchlistChanged() {
    watchlistVersion.value = watchlistVersion.value + 1;
  }
}
