import 'package:flutter/material.dart';
import 'package:flutter_app/src/data/models/details_models.dart';
import 'package:flutter_app/src/presentation/screens/details_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final episodes = [
    Episode(
      id: 1,
      name: 'Le premier pas',
      overview: 'Un épisode fondateur.',
      episodeNumber: 1,
      seasonNumber: 1,
      stillPath: null,
      airDate: '2025-01-01',
      runtime: 42,
    ),
    Episode(
      id: 2,
      name: 'Le second souffle',
      overview: 'Les choses se compliquent.',
      episodeNumber: 2,
      seasonNumber: 1,
      stillPath: null,
      airDate: '2025-01-08',
      runtime: 45,
    ),
    Episode(
      id: 3,
      name: 'Épisode futur',
      overview: 'Pas encore diffusé.',
      episodeNumber: 3,
      seasonNumber: 1,
      stillPath: null,
      airDate: '2099-01-01',
      runtime: null,
    ),
  ];

  final crossSeasonEpisodes = [
    Episode(
      id: 10,
      name: 'Fin de saison 1',
      overview: 'Dernier épisode S1.',
      episodeNumber: 3,
      seasonNumber: 1,
      stillPath: null,
      airDate: '2025-01-01',
      runtime: 42,
    ),
    Episode(
      id: 11,
      name: 'Début de saison 2',
      overview: 'Premier épisode S2.',
      episodeNumber: 1,
      seasonNumber: 2,
      stillPath: null,
      airDate: '2025-02-01',
      runtime: 44,
    ),
  ];

  const defaultOffsets = {1: 0};
  const defaultSeriesTitle = 'Ma Série';

  Widget buildPage({
    int initialIndex = 0,
    Set<String> watchedEpisodes = const {},
    bool Function(Episode)? isReleasedCheck,
    Future<void> Function(Episode, bool)? onToggleWatched,
    List<Episode>? episodeList,
    Map<int, int>? seasonOffsets,
    String? seriesTitle,
  }) {
    return MaterialApp(
      home: EpisodeDetailPage(
        episodes: episodeList ?? episodes,
        initialIndex: initialIndex,
        watchedEpisodes: watchedEpisodes,
        seasonOffsets: seasonOffsets ?? defaultOffsets,
        seriesTitle: seriesTitle ?? defaultSeriesTitle,
        isReleasedCheck: isReleasedCheck ?? (ep) => ep.airDate != '2099-01-01',
        onToggleWatched: onToggleWatched ?? (_, __) async {},
      ),
    );
  }

  testWidgets('displays episode number in appbar title', (tester) async {
    await tester.pumpWidget(buildPage());
    expect(find.text('S01 | E01'), findsOneWidget);
  });

  testWidgets('displays series title on the page', (tester) async {
    await tester.pumpWidget(buildPage(seriesTitle: 'Breaking Bad'));
    await tester.pumpAndSettle();
    expect(find.text('Breaking Bad'), findsOneWidget);
  });

  testWidgets('displays global episode number', (tester) async {
    await tester.pumpWidget(
      buildPage(seasonOffsets: {1: 5}),
    );
    await tester.pumpAndSettle();
    // global = offset(5) + episodeNumber(1) = 6 → "Ép. 06"
    expect(find.textContaining('Ép. 06'), findsOneWidget);
  });

  testWidgets('navigates to next episode via Suivant button', (tester) async {
    await tester.pumpWidget(buildPage(initialIndex: 0));
    await tester.pumpAndSettle();

    expect(find.text('S01 | E01'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();

    expect(find.text('S01 | E02'), findsOneWidget);
  });

  testWidgets('navigates to previous episode via Précédent button', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage(initialIndex: 1));
    await tester.pumpAndSettle();

    expect(find.text('S01 | E02'), findsOneWidget);

    await tester.tap(find.text('Précédent'));
    await tester.pumpAndSettle();

    expect(find.text('S01 | E01'), findsOneWidget);
  });

  testWidgets('cross-season navigation: next from last ep of S1 shows S2 E1', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildPage(
        episodeList: crossSeasonEpisodes,
        initialIndex: 0,
        seasonOffsets: {1: 0, 2: 3},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('S01 | E03'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();

    expect(find.text('S02 | E01'), findsOneWidget);
  });

  testWidgets('Précédent disabled on first episode', (tester) async {
    await tester.pumpWidget(buildPage(initialIndex: 0));
    await tester.pumpAndSettle();

    final prevButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Précédent'),
    );
    expect(prevButton.onPressed, isNull);
  });

  testWidgets('Suivant disabled on last episode', (tester) async {
    await tester.pumpWidget(buildPage(initialIndex: 2));
    await tester.pumpAndSettle();

    final nextButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Suivant'),
    );
    expect(nextButton.onPressed, isNull);
  });

  testWidgets('menu shows Marquer comme vu when episode not watched', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage());

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Marquer comme vu'), findsOneWidget);
    expect(find.text('Marquer non vu'), findsNothing);
  });

  testWidgets('menu shows Marquer non vu when episode is watched', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage(watchedEpisodes: {'1_1'}));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Marquer non vu'), findsOneWidget);
    expect(find.text('Marquer comme vu'), findsNothing);
  });

  testWidgets('toggling via menu calls the callback', (tester) async {
    Episode? toggledEpisode;
    bool? toggledValue;

    await tester.pumpWidget(
      buildPage(
        onToggleWatched: (ep, value) async {
          toggledEpisode = ep;
          toggledValue = value;
        },
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marquer comme vu'));
    await tester.pump();

    expect(toggledValue, isTrue);
    expect(toggledEpisode?.episodeNumber, 1);
  });

  testWidgets('menu item is disabled for unreleased episodes', (tester) async {
    await tester.pumpWidget(buildPage(initialIndex: 2));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    final item = tester.widget<PopupMenuItem<String>>(
      find.byType(PopupMenuItem<String>),
    );
    expect(item.enabled, isFalse);
  });

  testWidgets('supports back navigation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EpisodeDetailPage(
                    episodes: episodes,
                    initialIndex: 0,
                    watchedEpisodes: const {},
                    seasonOffsets: defaultOffsets,
                    seriesTitle: defaultSeriesTitle,
                    isReleasedCheck: (_) => true,
                    onToggleWatched: (_, __) async {},
                  ),
                ),
              ),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(find.byType(EpisodeDetailPage), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir'), findsOneWidget);
  });
}
