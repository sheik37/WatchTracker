import 'package:flutter_app/src/core/episode_watch_key.dart';
import 'package:flutter_app/src/data/models/details_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Episode.watchKey', () {
    test('combines season and episode numbers with an underscore', () {
      const episode = Episode(
        id: 1,
        name: 'Pilote',
        overview: 'Un épisode',
        episodeNumber: 3,
        seasonNumber: 2,
        stillPath: null,
        airDate: '2024-01-01',
        runtime: 42,
      );
      expect(episode.watchKey, '2_3');
    });

    test('supports special-episode season number 0', () {
      const episode = Episode(
        id: 2,
        name: 'Spécial',
        overview: 'Un spécial',
        episodeNumber: 1,
        seasonNumber: 0,
        stillPath: null,
        airDate: null,
        runtime: null,
      );
      expect(episode.watchKey, '0_1');
    });
  });
}
