import 'media_models.dart';

enum TvStatus {
  returningSeries('Returning Series'),
  ended('Ended'),
  canceled('Canceled'),
  planned('Planned'),
  inProduction('In Production');

  const TvStatus(this.apiValue);
  final String apiValue;

  static TvStatus? fromApiValue(String? value) {
    return TvStatus.values
        .where((s) => s.apiValue.toLowerCase() == value?.toLowerCase())
        .firstOrNull;
  }
}

class MediaDetails {
  const MediaDetails({
    required this.id,
    required this.title,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.releaseDate,
    required this.voteAverage,
    required this.mediaType,
    this.tvStatus,
    this.genres = const <String>[],
    this.seasons = const <Season>[],
  });

  final int id;
  final String title;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double voteAverage;
  final MediaType mediaType;
  final TvStatus? tvStatus;
  final List<String> genres;
  final List<Season> seasons;
}

class Season {
  const Season({
    required this.id,
    required this.name,
    required this.seasonNumber,
    required this.episodeCount,
    this.episodes = const <Episode>[],
  });

  final int id;
  final String name;
  final int seasonNumber;
  final int episodeCount;
  final List<Episode> episodes;
}

class Episode {
  const Episode({
    required this.id,
    required this.name,
    required this.overview,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.stillPath,
    this.airDate,
    this.runtime,
    this.isWatched = false,
  });

  final int id;
  final String name;
  final String overview;
  final int episodeNumber;
  final int seasonNumber;
  final String? stillPath;
  final String? airDate;
  final int? runtime;
  final bool isWatched;
}

extension MediaDetailsX on MediaDetails {
  WatchCategory watchCategory() {
    if (mediaType == MediaType.movie) return WatchCategory.films;
    final hasAnimeGenre = genres.any(
      (g) =>
          g.toLowerCase() == 'animation' || g.toLowerCase().contains('anime'),
    );
    return hasAnimeGenre ? WatchCategory.anime : WatchCategory.series;
  }

  Media toMedia() {
    return Media(
      id: id,
      title: title,
      posterPath: posterPath,
      backdropPath: backdropPath,
      overview: overview,
      releaseDate: releaseDate,
      voteAverage: voteAverage,
      mediaType: mediaType,
    );
  }
}
