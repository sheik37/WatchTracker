enum MediaType {
  movie('movie'),
  tv('tv');

  const MediaType(this.value);
  final String value;

  static MediaType fromString(String? value) {
    return MediaType.values.where((t) => t.value == value).firstOrNull ??
        MediaType.movie;
  }
}

enum WatchCategory {
  series('series', 'Series'),
  films('films', 'Films'),
  anime('anime', 'Anime');

  const WatchCategory(this.value, this.label);
  final String value;
  final String label;

  static WatchCategory fromString(String? value) {
    return WatchCategory.values.where((t) => t.value == value).firstOrNull ??
        WatchCategory.series;
  }
}

enum WatchStatus {
  notStarted('not_started', 'Pas commence'),
  inProgress('in_progress', 'En cours'),
  upToDate('up_to_date', 'A jour'),
  completed('completed', 'Termine'),
  watched('watched', 'Vu'),
  notWatched('not_watched', 'Pas encore vu');

  const WatchStatus(this.value, this.label);
  final String value;
  final String label;

  static WatchStatus fromString(String? value) {
    return WatchStatus.values.where((s) => s.value == value).firstOrNull ??
        WatchStatus.notStarted;
  }
}

extension WatchCategoryX on WatchCategory {
  WatchStatus defaultStatus() {
    switch (this) {
      case WatchCategory.series:
      case WatchCategory.anime:
        return WatchStatus.notStarted;
      case WatchCategory.films:
        return WatchStatus.notWatched;
    }
  }
}

class Media {
  const Media({
    required this.id,
    required this.title,
    required this.posterPath,
    required this.backdropPath,
    required this.overview,
    required this.releaseDate,
    required this.voteAverage,
    required this.mediaType,
    this.genreIds = const <int>[],
  });

  final int id;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String overview;
  final String? releaseDate;
  final double voteAverage;
  final MediaType mediaType;
  final List<int> genreIds;
}

class WatchlistItem {
  const WatchlistItem({
    required this.media,
    required this.status,
    required this.watchedEpisodes,
    required this.totalEpisodes,
    this.lastWatchedAt,
  });

  final Media media;
  final WatchStatus status;
  final int watchedEpisodes;
  final int totalEpisodes;
  final int? lastWatchedAt;
}

extension FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
