import 'package:flutter_app/src/core/app_config.dart';
import 'package:flutter_app/src/data/models/auth_models.dart';
import 'package:flutter_app/src/data/models/details_models.dart';
import 'package:flutter_app/src/data/models/media_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig', () {
    test('exposes default environment-backed values', () {
      expect(AppConfig.appVersion, isNotEmpty);
      expect(AppConfig.appBuildNumber, greaterThan(0));
      expect(AppConfig.updateManifestUrl, isNotEmpty);
      expect(AppConfig.tmdbApiKey, isA<String>());
      expect(AppConfig.backendBaseUrl, isA<String>());
      expect(AppConfig.androidUpdateUrl, isA<String>());
      expect(AppConfig.iosUpdateUrl, isA<String>());
      expect(AppConfig.updateDownloadUrl, isA<String>());
      expect(AppConfig.tvdbApiKey, isA<String>());
    });
  });

  group('media models', () {
    test('parses enums with safe fallbacks', () {
      expect(MediaType.fromString('movie'), MediaType.movie);
      expect(MediaType.fromString('tv'), MediaType.tv);
      expect(MediaType.fromString('unknown'), MediaType.movie);

      expect(WatchCategory.fromString('series'), WatchCategory.series);
      expect(WatchCategory.fromString('films'), WatchCategory.films);
      expect(WatchCategory.fromString('oops'), WatchCategory.series);

      expect(WatchStatus.fromString('in_progress'), WatchStatus.inProgress);
      expect(WatchStatus.fromString('watched'), WatchStatus.watched);
      expect(WatchStatus.fromString('oops'), WatchStatus.notStarted);
    });

    test('returns default status by category', () {
      expect(WatchCategory.series.defaultStatus(), WatchStatus.notStarted);
      expect(WatchCategory.anime.defaultStatus(), WatchStatus.notStarted);
      expect(WatchCategory.films.defaultStatus(), WatchStatus.notWatched);
    });

    test('firstOrNull returns null for empty iterables', () {
      expect(<int>[].firstOrNull, isNull);
      expect([1, 2, 3].firstOrNull, 1);
    });
  });

  group('details models', () {
    test('parses TV status ignoring case', () {
      expect(
        TvStatus.fromApiValue('Returning Series'),
        TvStatus.returningSeries,
      );
      expect(TvStatus.fromApiValue('ended'), TvStatus.ended);
      expect(TvStatus.fromApiValue('missing'), isNull);
    });

    test('computes watch category from media details', () {
      const movieDetails = MediaDetails(
        id: 1,
        title: 'Movie',
        overview: 'Overview',
        posterPath: null,
        backdropPath: null,
        releaseDate: '2024-01-01',
        voteAverage: 7.2,
        mediaType: MediaType.movie,
      );
      const animeDetails = MediaDetails(
        id: 2,
        title: 'Anime',
        overview: 'Overview',
        posterPath: null,
        backdropPath: null,
        releaseDate: '2024-01-01',
        voteAverage: 8.0,
        mediaType: MediaType.tv,
        genres: ['Animation'],
      );
      const seriesDetails = MediaDetails(
        id: 3,
        title: 'Series',
        overview: 'Overview',
        posterPath: '/poster.jpg',
        backdropPath: '/backdrop.jpg',
        releaseDate: '2024-01-01',
        voteAverage: 8.5,
        mediaType: MediaType.tv,
        genres: ['Drama'],
      );

      expect(movieDetails.watchCategory(), WatchCategory.films);
      expect(animeDetails.watchCategory(), WatchCategory.anime);
      expect(seriesDetails.watchCategory(), WatchCategory.series);
    });

    test('converts media details to media summary', () {
      const details = MediaDetails(
        id: 4,
        title: 'Series',
        overview: 'Overview',
        posterPath: '/poster.jpg',
        backdropPath: '/backdrop.jpg',
        releaseDate: '2024-01-01',
        voteAverage: 8.5,
        mediaType: MediaType.tv,
        tvStatus: TvStatus.ended,
        seasons: [
          Season(
            id: 10,
            name: 'Season 1',
            seasonNumber: 1,
            episodeCount: 10,
            episodes: [
              Episode(
                id: 100,
                name: 'Ep1',
                overview: 'Pilot',
                episodeNumber: 1,
                seasonNumber: 1,
                stillPath: null,
              ),
            ],
          ),
        ],
      );

      final media = details.toMedia();

      expect(media.id, details.id);
      expect(media.title, details.title);
      expect(media.posterPath, details.posterPath);
      expect(media.backdropPath, details.backdropPath);
      expect(media.overview, details.overview);
      expect(media.releaseDate, details.releaseDate);
      expect(media.voteAverage, details.voteAverage);
      expect(media.mediaType, details.mediaType);
      expect(details.seasons.single.episodes.single.name, 'Ep1');
    });
  });

  group('auth models', () {
    test('auth exception uses its message as string representation', () {
      const exception = AuthException(
        'Erreur',
        retryAfterSeconds: 30,
        attemptsRemaining: 2,
        requiresOtp: true,
      );

      expect(exception.toString(), 'Erreur');
      expect(exception.retryAfterSeconds, 30);
      expect(exception.attemptsRemaining, 2);
      expect(exception.requiresOtp, isTrue);
    });

    test('auth tokens and user profile expose constructor values', () {
      const tokens = AuthTokens(
        accessToken: 'token',
        refreshToken: 'refresh',
        expiresInSeconds: 3600,
      );
      const profile = UserProfile(
        userId: 42,
        email: 'user@example.com',
        displayName: 'User',
      );

      expect(tokens.accessToken, 'token');
      expect(tokens.refreshToken, 'refresh');
      expect(tokens.expiresInSeconds, 3600);
      expect(profile.userId, 42);
      expect(profile.email, 'user@example.com');
      expect(profile.displayName, 'User');
    });
  });
}
