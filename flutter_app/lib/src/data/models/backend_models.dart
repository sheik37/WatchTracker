class RemoteWatchlistItem {
  const RemoteWatchlistItem({
    required this.id,
    required this.title,
    required this.posterPath,
    required this.mediaType,
    required this.contentCategory,
    required this.contentStatus,
    required this.totalEpisodes,
    this.addedAtMillis,
    this.updatedAtMillis,
  });

  final int id;
  final String title;
  final String? posterPath;
  final String mediaType;
  final String contentCategory;
  final String contentStatus;
  final int totalEpisodes;
  final int? addedAtMillis;
  final int? updatedAtMillis;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'poster_path': posterPath,
      'media_type': mediaType,
      'content_category': contentCategory,
      'content_status': contentStatus,
      'total_episodes': totalEpisodes,
    };
  }

  static RemoteWatchlistItem fromJson(Map<String, dynamic> json) {
    return RemoteWatchlistItem(
      id: (json['id'] as num).toInt(),
      title: (json['title'] as String?) ?? '',
      posterPath: json['poster_path'] as String?,
      mediaType: (json['media_type'] as String?) ?? 'movie',
      contentCategory: (json['content_category'] as String?) ?? 'series',
      contentStatus: (json['content_status'] as String?) ?? 'not_started',
      totalEpisodes: (json['total_episodes'] as num?)?.toInt() ?? 0,
      addedAtMillis: _parseDateMillis(json['added_at']),
      updatedAtMillis: _parseDateMillis(json['updated_at']),
    );
  }
}

class RemoteEpisodeProgress {
  const RemoteEpisodeProgress({
    required this.seasonNumber,
    required this.episodeNumber,
    required this.isWatched,
    this.mediaId,
    this.updatedAtMillis,
  });

  final int? mediaId;
  final int seasonNumber;
  final int episodeNumber;
  final bool isWatched;
  final int? updatedAtMillis;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'media_id': mediaId,
      'season_number': seasonNumber,
      'episode_number': episodeNumber,
      'is_watched': isWatched,
    };
  }

  static RemoteEpisodeProgress fromJson(Map<String, dynamic> json) {
    return RemoteEpisodeProgress(
      mediaId: (json['media_id'] as num?)?.toInt(),
      seasonNumber: (json['season_number'] as num).toInt(),
      episodeNumber: (json['episode_number'] as num).toInt(),
      isWatched: (json['is_watched'] as bool?) ?? false,
      updatedAtMillis: _parseDateMillis(json['updated_at']),
    );
  }
}

class RemoteWatchlistTombstone {
  const RemoteWatchlistTombstone({
    required this.id,
    required this.mediaType,
    required this.contentCategory,
    required this.deletedAtMillis,
  });

  final int id;
  final String mediaType;
  final String contentCategory;
  final int deletedAtMillis;

  static RemoteWatchlistTombstone fromJson(Map<String, dynamic> json) {
    return RemoteWatchlistTombstone(
      id: (json['id'] as num).toInt(),
      mediaType: (json['media_type'] as String?) ?? 'movie',
      contentCategory: (json['content_category'] as String?) ?? 'series',
      deletedAtMillis: _parseDateMillis(json['deleted_at']) ?? 0,
    );
  }
}

class RemoteEpisodeProgressTombstone {
  const RemoteEpisodeProgressTombstone({
    required this.mediaId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.deletedAtMillis,
  });

  final int mediaId;
  final int seasonNumber;
  final int episodeNumber;
  final int deletedAtMillis;

  static RemoteEpisodeProgressTombstone fromJson(Map<String, dynamic> json) {
    return RemoteEpisodeProgressTombstone(
      mediaId: (json['media_id'] as num).toInt(),
      seasonNumber: (json['season_number'] as num).toInt(),
      episodeNumber: (json['episode_number'] as num).toInt(),
      deletedAtMillis: _parseDateMillis(json['deleted_at']) ?? 0,
    );
  }
}

class RemoteSyncSnapshot {
  const RemoteSyncSnapshot({
    required this.snapshotAtMillis,
    required this.watchlist,
    required this.episodeProgress,
    required this.watchlistTombstones,
    required this.episodeProgressTombstones,
  });

  final int snapshotAtMillis;
  final List<RemoteWatchlistItem> watchlist;
  final List<RemoteEpisodeProgress> episodeProgress;
  final List<RemoteWatchlistTombstone> watchlistTombstones;
  final List<RemoteEpisodeProgressTombstone> episodeProgressTombstones;

  static RemoteSyncSnapshot fromJson(Map<String, dynamic> json) {
    final watchlistRaw = (json['watchlist'] as List<dynamic>? ?? <dynamic>[]);
    final progressRaw =
        (json['episode_progress'] as List<dynamic>? ?? <dynamic>[]);
    final tombstonesRaw =
        (json['watchlist_tombstones'] as List<dynamic>? ?? <dynamic>[]);
    final episodeTombstonesRaw =
        (json['episode_progress_tombstones'] as List<dynamic>? ?? <dynamic>[]);
    return RemoteSyncSnapshot(
      snapshotAtMillis: _parseDateMillis(json['snapshot_at']) ?? 0,
      watchlist: watchlistRaw
          .whereType<Map<String, dynamic>>()
          .map(RemoteWatchlistItem.fromJson)
          .toList(),
      episodeProgress: progressRaw
          .whereType<Map<String, dynamic>>()
          .map(RemoteEpisodeProgress.fromJson)
          .toList(),
      watchlistTombstones: tombstonesRaw
          .whereType<Map<String, dynamic>>()
          .map(RemoteWatchlistTombstone.fromJson)
          .toList(),
      episodeProgressTombstones: episodeTombstonesRaw
          .whereType<Map<String, dynamic>>()
          .map(RemoteEpisodeProgressTombstone.fromJson)
          .toList(),
    );
  }
}

int? _parseDateMillis(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  if (value is! String || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  return parsed?.millisecondsSinceEpoch;
}
