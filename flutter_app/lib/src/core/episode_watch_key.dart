import '../data/models/details_models.dart';

/// Stable key identifying an [Episode] within its media's watch-progress
/// maps/sets, independent of the episode's own identity (`seasonNumber`
/// combined with `episodeNumber`).
extension EpisodeWatchKey on Episode {
  String get watchKey => '${seasonNumber}_$episodeNumber';
}
