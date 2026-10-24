// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/date_formatter.dart';
import '../../core/episode_watch_key.dart';
import '../../core/network_error_classifier.dart';
import '../../data/models/backend_models.dart';
import '../../data/models/details_models.dart';
import '../../data/models/media_models.dart';
import '../../data/repositories/media_repository.dart';
import '../theme/slide_up_route.dart';
import 'details/episode_detail_page.dart';
import 'details/media_header.dart';
import 'details/rewatch_choice.dart';
import 'details/season_section.dart';
import 'details/watch_history_dialog.dart';

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({
    super.key,
    required this.repository,
    required this.media,
  });

  final MediaRepository repository;
  final Media media;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  MediaDetails? _details;
  WatchStatus? _status;
  bool _tracked = false;
  bool _loading = true;
  String? _error;
  Set<String> _watchedEpisodes = {};
  Map<String, int> _episodeWatchedAt = {};
  Map<String, int> _episodeViewCounts = {};
  int? _movieWatchedAtMillis;
  int _movieViewCount = 0;
  List<int> _movieWatchDates = [];
  bool _showEpisodes = false;
  int _tvTabDirection = 1;
  final ScrollController _scrollCtrl = ScrollController();
  final Map<int, List<Episode>> _episodesBySeason = {};
  double _tvSwipeDelta = 0;
  int _nextEpisodeJumpToken = 0;
  Episode? _nextEpisodeTarget;
  final ValueNotifier<bool> _showExtendedNextEpisodeCta = ValueNotifier<bool>(
    true,
  );
  bool _navigatingToNextEpisode = false;
  bool _fetchedFromCache = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScrollChanged);
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScrollChanged);
    _scrollCtrl.dispose();
    _showExtendedNextEpisodeCta.dispose();
    super.dispose();
  }

  void _onScrollChanged() {
    if (!_scrollCtrl.hasClients) return;
    final showExtended = _scrollCtrl.offset < 64;
    if (showExtended != _showExtendedNextEpisodeCta.value) {
      _showExtendedNextEpisodeCta.value = showExtended;
    }
  }

  Future<void> _refreshProgressState() async {
    final details = _details;
    if (details == null) return;

    try {
      final progressList = await widget.repository.getEpisodeProgress(
        details.id,
      );
      final viewCounts = Map<String, int>.from(
        await widget.repository.getEpisodeViewCounts(details.id),
      );
      final watchedSet = progressList
          .where((p) => p.isWatched)
          .map((p) => '${p.seasonNumber}_${p.episodeNumber}')
          .toSet();
      final watchedAtMap = {
        for (final p in progressList.where((p) => p.isWatched))
          '${p.seasonNumber}_${p.episodeNumber}': p.updatedAtMillis ?? 0,
      };
      for (final key in watchedSet) {
        viewCounts.putIfAbsent(key, () => 1);
      }

      if (details.mediaType == MediaType.movie) {
        final movieViewCount = await widget.repository.getMovieViewCount(
          details.id,
        );
        final movieDates = movieViewCount > 0
            ? await widget.repository.getMovieWatchDates(details.id)
            : const <int>[];
        final movieFirst = movieViewCount > 0
            ? await widget.repository.getMovieFirstWatchedAt(details.id)
            : null;
        if (!mounted) return;
        setState(() {
          _watchedEpisodes = watchedSet;
          _episodeWatchedAt = watchedAtMap;
          _episodeViewCounts = viewCounts;
          _movieViewCount = movieViewCount;
          _movieWatchDates = movieDates;
          _movieWatchedAtMillis = movieFirst;
          _status = movieViewCount > 0
              ? WatchStatus.watched
              : WatchStatus.notWatched;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _watchedEpisodes = watchedSet;
        _episodeWatchedAt = watchedAtMap;
        _episodeViewCounts = viewCounts;
      });
      _updateTvStatus(details);
    } catch (_) {
      // Keep the already rendered state and rely on the next full reload.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _fetchedFromCache = false;
    });
    try {
      final details = widget.media.mediaType == MediaType.movie
          ? await widget.repository.getMovieDetails(widget.media.id)
          : await widget.repository.getTvDetails(widget.media.id);
      final fetchedFromCache = widget.repository.lastFetchWasFromCache;
      if (details.mediaType == MediaType.tv) {
        unawaited(widget.repository.prefetchSeasonEpisodes(details));
      }
      final category = details.watchCategory();
      final tracked = await widget.repository.isInWatchlist(
        widget.media.id,
        widget.media.mediaType,
        category,
      );
      final status = tracked
          ? await widget.repository.getWatchStatus(
              widget.media.id,
              widget.media.mediaType,
              category,
            )
          : null;
      final progressList = await widget.repository.getEpisodeProgress(
        widget.media.id,
      );
      final viewCounts = Map<String, int>.from(
        await widget.repository.getEpisodeViewCounts(widget.media.id),
      );
      final watchedSet = progressList
          .where((p) => p.isWatched)
          .map((p) => '${p.seasonNumber}_${p.episodeNumber}')
          .toSet();
      final watchedAtMap = {
        for (final p in progressList.where((p) => p.isWatched))
          '${p.seasonNumber}_${p.episodeNumber}': p.updatedAtMillis ?? 0,
      };
      for (final key in watchedSet) {
        viewCounts.putIfAbsent(key, () => 1);
      }
      _details = details;
      _tracked = tracked;
      _status = status;
      _watchedEpisodes = watchedSet;
      _episodeWatchedAt = watchedAtMap;
      _episodeViewCounts = viewCounts;
      _movieWatchedAtMillis =
          details.mediaType == MediaType.movie && status == WatchStatus.watched
          ? await widget.repository.getMovieFirstWatchedAt(details.id)
          : null;
      _movieViewCount = details.mediaType == MediaType.movie
          ? await widget.repository.getMovieViewCount(details.id)
          : 0;
      if (details.mediaType == MediaType.movie && _movieViewCount > 0) {
        _movieWatchDates = await widget.repository.getMovieWatchDates(
          details.id,
        );
      }
      _fetchedFromCache = fetchedFromCache;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        if (_fetchedFromCache) {
          _showOfflineBanner();
        }
      }
    }
  }

  void _showOfflineBanner() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.cloud_off, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '⚠️ Données en cache - Connexion requise pour les infos à jour',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.amber.shade700,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleWatchlist() async {
    final details = _details;
    if (details == null) return;
    final category = details.watchCategory();
    if (_tracked) {
      final label = category == WatchCategory.anime
          ? ('animé', 'cet animé')
          : category == WatchCategory.films
          ? ('film', 'ce film')
          : ('série', 'cette série');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
          title: Text('Supprimer le ${label.$1}'),
          content: Text('Retirer ${label.$2} de vos suivis ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Supprimer',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ),
          ],
        ),
      );
      if (confirmed == true) await _removeFromWatchlist();
      return;
    }
    final totalEpisodes = details.mediaType == MediaType.movie
        ? 1
        : details.seasons
              .where((s) => s.seasonNumber != 0)
              .fold(0, (acc, s) => acc + s.episodeCount);
    final defaultStatus = category.defaultStatus();
    await widget.repository.addToWatchlist(
      details.toMedia(),
      category,
      defaultStatus,
      totalEpisodes,
    );
    setState(() {
      _tracked = true;
      _status = defaultStatus;
      if (details.mediaType == MediaType.movie) {
        _movieWatchedAtMillis = null;
      }
    });
  }

  Future<void> _removeFromWatchlist() async {
    final details = _details;
    if (details == null) return;
    await widget.repository.removeFromWatchlist(
      details.toMedia(),
      details.watchCategory(),
    );
    setState(() {
      _tracked = false;
      _status = null;
      if (details.mediaType == MediaType.movie) {
        _movieWatchedAtMillis = null;
      }
    });
  }

  Future<void> _setMovieWatched(bool watched) async {
    final details = _details;
    if (details == null) return;
    final category = details.watchCategory();
    final wasWatched = _status == WatchStatus.watched;
    var rewatch = false;
    if (!watched && wasWatched) {
      final dates = _movieWatchDates;
      final choice = await _showRewatchDialog(
        context,
        isSeason: false,
        watchedDates: dates,
      );
      if (!mounted || choice == null) return;
      if (choice == RewatchChoice.rewatch) {
        watched = true;
        rewatch = true;
      } else if (dates.length > 1) {
        final selected = await _showWatchDatePickerDialog(dates);
        if (selected == null) return;
        await _deleteMovieWatchDate(selected);
        return;
      }
    }
    final newStatus = watched ? WatchStatus.watched : WatchStatus.notWatched;
    final previousStatus = _status;
    final previousMillis = _movieWatchedAtMillis;
    final previousViewCount = _movieViewCount;
    final previousWatchDates = List<int>.from(_movieWatchDates);
    final previousTracked = _tracked;
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    final nextMovieWatchedAt =
        watched && previousMillis != null && (wasWatched || rewatch)
        ? previousMillis
        : watched
        ? nowMillis
        : null;
    final nextMovieViewCount = watched
        ? (wasWatched || rewatch ? previousViewCount + 1 : 1)
        : 0;
    // Optimistic update
    setState(() {
      if (!_tracked) _tracked = true;
      _status = newStatus;
      _movieWatchedAtMillis = nextMovieWatchedAt;
      _movieViewCount = nextMovieViewCount;
      if (watched) {
        _movieWatchDates = wasWatched
            ? [..._movieWatchDates, nowMillis]
            : [nowMillis];
      } else {
        _movieWatchDates = [];
      }
    });
    try {
      if (!previousTracked) {
        await widget.repository.addToWatchlist(
          details.toMedia(),
          category,
          WatchStatus.notWatched,
          1,
        );
      }
      if (watched) {
        await widget.repository.markMovieWatched(
          details.toMedia(),
          category,
          rewatch: rewatch,
          watchedAtMillis: nowMillis,
        );
        if (previousMillis == null) {
          final firstWatchAt = await widget.repository.getMovieFirstWatchedAt(
            details.id,
          );
          if (mounted) {
            setState(() => _movieWatchedAtMillis = firstWatchAt);
          } else {
            _movieWatchedAtMillis = firstWatchAt;
          }
        }
        await _refreshProgressState();
      } else {
        await widget.repository.markMovieUnwatched(details.toMedia(), category);
      }
      final refreshedMovieViewCount = await widget.repository.getMovieViewCount(
        details.id,
      );
      final refreshedMovieWatchDates = watched
          ? await widget.repository.getMovieWatchDates(details.id)
          : const <int>[];
      if (mounted) {
        setState(() {
          _movieViewCount = refreshedMovieViewCount;
          _movieWatchDates = refreshedMovieWatchDates;
        });
      } else {
        _movieViewCount = refreshedMovieViewCount;
        _movieWatchDates = refreshedMovieWatchDates;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tracked = previousTracked;
        _status = previousStatus;
        _movieWatchedAtMillis = previousMillis;
        _movieViewCount = previousViewCount;
        _movieWatchDates = previousWatchDates;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de mettre à jour le film: $e')),
      );
    }
  }

  Future<void> _setEpisodeWatched(
    Episode episode,
    bool watched,
    int? updatedAtMillis,
    bool rewatch,
  ) async {
    final details = _details;
    if (details == null) return;
    final key = '${episode.seasonNumber}_${episode.episodeNumber}';
    final wasWatched = _watchedEpisodes.contains(key);
    final previous = <String>{..._watchedEpisodes};
    final previousAt = Map<String, int>.from(_episodeWatchedAt);
    final previousCounts = Map<String, int>.from(_episodeViewCounts);
    final next = <String>{..._watchedEpisodes};
    final nextAt = Map<String, int>.from(_episodeWatchedAt);
    final nextCounts = Map<String, int>.from(_episodeViewCounts);
    final ts = updatedAtMillis ?? DateTime.now().millisecondsSinceEpoch;
    if (watched) {
      next.add(key);
      nextAt[key] = previousAt[key] ?? ts;
      if (wasWatched || rewatch) {
        nextCounts[key] = (previousCounts[key] ?? 1) + 1;
      } else {
        nextCounts[key] = 1;
      }
    } else {
      next.remove(key);
      nextAt.remove(key);
      nextCounts.remove(key);
    }
    setState(() {
      _watchedEpisodes = next;
      _episodeWatchedAt = nextAt;
      _episodeViewCounts = nextCounts;
    });
    _updateTvStatus(details);
    if (watched) {
      await _ensureTvTrackedForEpisodeUpdate(details);
    }
    try {
      if (watched) {
        await widget.repository.markEpisodeWatched(
          mediaId: details.id,
          seasonNumber: episode.seasonNumber,
          episodeNumber: episode.episodeNumber,
          rewatch: rewatch || wasWatched,
          watchedAtMillis: ts,
        );
        await _refreshProgressState();
      } else {
        await widget.repository.markEpisodeUnwatched(
          mediaId: details.id,
          seasonNumber: episode.seasonNumber,
          episodeNumber: episode.episodeNumber,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _watchedEpisodes = previous;
        _episodeWatchedAt = previousAt;
        _episodeViewCounts = previousCounts;
      });
      _updateTvStatus(details);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de mettre à jour l\'épisode: $e')),
      );
    }
  }

  Future<void> _markSeasonWatched(
    Season targetSeason,
    bool watched, {
    bool includeAlreadyWatched = false,
    bool rewatch = false,
  }) async {
    final details = _details;
    if (details == null) return;
    if (watched) {
      await _ensureTvTrackedForEpisodeUpdate(details);
    }
    final seasons = details.seasons.where((s) => s.seasonNumber != 0).toList()
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    final updates = <RemoteEpisodeProgress>[];
    if (targetSeason.seasonNumber == 0) {
      final episodeNumbers = await _episodeNumbersToMark(
        details.id,
        targetSeason,
        watched,
      );
      for (final i in episodeNumbers) {
        updates.add(
          RemoteEpisodeProgress(
            mediaId: details.id,
            seasonNumber: 0,
            episodeNumber: i,
            isWatched: watched,
          ),
        );
      }
    } else if (watched) {
      for (final season in seasons.where(
        (s) => s.seasonNumber <= targetSeason.seasonNumber,
      )) {
        final episodeNumbers = await _episodeNumbersToMark(
          details.id,
          season,
          true,
          maxEpisodeForTarget: season.seasonNumber == targetSeason.seasonNumber
              ? targetSeason.episodeCount
              : null,
        );
        for (final i in episodeNumbers) {
          updates.add(
            RemoteEpisodeProgress(
              mediaId: details.id,
              seasonNumber: season.seasonNumber,
              episodeNumber: i,
              isWatched: true,
            ),
          );
        }
      }
    } else {
      final episodeNumbers = await _episodeNumbersToMark(
        details.id,
        targetSeason,
        false,
      );
      for (final i in episodeNumbers) {
        updates.add(
          RemoteEpisodeProgress(
            mediaId: details.id,
            seasonNumber: targetSeason.seasonNumber,
            episodeNumber: i,
            isWatched: false,
          ),
        );
      }
    }
    await _applyEpisodeUpdates(
      details,
      updates,
      includeAlreadyWatchedForMarked: includeAlreadyWatched,
      rewatch: rewatch,
    );
  }

  Future<void> _markOnlySeasonWatched(Season targetSeason, bool watched) async {
    final details = _details;
    if (details == null) return;
    if (watched) {
      await _ensureTvTrackedForEpisodeUpdate(details);
    }
    final episodeNumbers = await _episodeNumbersToMark(
      details.id,
      targetSeason,
      watched,
    );
    final updates = <RemoteEpisodeProgress>[];
    for (final i in episodeNumbers) {
      updates.add(
        RemoteEpisodeProgress(
          mediaId: details.id,
          seasonNumber: targetSeason.seasonNumber,
          episodeNumber: i,
          isWatched: watched,
        ),
      );
    }
    await _applyEpisodeUpdates(details, updates);
  }

  Future<void> _markEpisodeUpTo(
    Episode targetEpisode,
    int? updatedAtMillis,
  ) async {
    final details = _details;
    if (details == null) return;
    await _ensureTvTrackedForEpisodeUpdate(details);
    final seasons = details.seasons.where((s) => s.seasonNumber != 0).toList()
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    final targetSeason = seasons.firstWhere(
      (s) => s.seasonNumber == targetEpisode.seasonNumber,
      orElse: () => Season(
        id: 0,
        name: '',
        seasonNumber: targetEpisode.seasonNumber,
        episodeCount: targetEpisode.episodeNumber,
      ),
    );
    final ts = updatedAtMillis ?? DateTime.now().millisecondsSinceEpoch;
    final updates = <RemoteEpisodeProgress>[];
    for (final season in seasons.where(
      (s) => s.seasonNumber < targetEpisode.seasonNumber,
    )) {
      for (var i = 1; i <= season.episodeCount; i++) {
        updates.add(
          RemoteEpisodeProgress(
            mediaId: details.id,
            seasonNumber: season.seasonNumber,
            episodeNumber: i,
            isWatched: true,
            updatedAtMillis: ts,
          ),
        );
      }
    }
    final end = targetEpisode.episodeNumber
        .clamp(1, targetSeason.episodeCount)
        .toInt();
    for (var i = 1; i <= end; i++) {
      updates.add(
        RemoteEpisodeProgress(
          mediaId: details.id,
          seasonNumber: targetEpisode.seasonNumber,
          episodeNumber: i,
          isWatched: true,
          updatedAtMillis: ts,
        ),
      );
    }
    await _applyEpisodeUpdates(details, updates, sharedTimestamp: ts);
  }

  Future<void> _applyEpisodeUpdates(
    MediaDetails details,
    List<RemoteEpisodeProgress> updates, {
    int? sharedTimestamp,
    bool includeAlreadyWatchedForMarked = false,
    bool rewatch = false,
  }) async {
    if (updates.isEmpty) return;
    final previous = <String>{..._watchedEpisodes};
    final previousAt = Map<String, int>.from(_episodeWatchedAt);
    final previousCounts = Map<String, int>.from(_episodeViewCounts);
    final next = <String>{..._watchedEpisodes};
    final nextAt = Map<String, int>.from(_episodeWatchedAt);
    final nextCounts = Map<String, int>.from(_episodeViewCounts);
    final nowFallback =
        sharedTimestamp ?? DateTime.now().millisecondsSinceEpoch;
    for (final update in updates) {
      final key = '${update.seasonNumber}_${update.episodeNumber}';
      if (update.isWatched) {
        next.add(key);
        nextAt[key] = previousAt[key] ?? update.updatedAtMillis ?? nowFallback;
        final alreadyWatched = previous.contains(key);
        if (alreadyWatched) {
          nextCounts[key] = includeAlreadyWatchedForMarked
              ? (previousCounts[key] ?? 1) + 1
              : (previousCounts[key] ?? 1);
        } else {
          nextCounts[key] = 1;
        }
      } else {
        next.remove(key);
        nextAt.remove(key);
        nextCounts.remove(key);
      }
    }
    setState(() {
      _watchedEpisodes = next;
      _episodeWatchedAt = nextAt;
      _episodeViewCounts = nextCounts;
    });
    _updateTvStatus(details);
    try {
      await widget.repository.markEpisodeBatch(
        mediaId: details.id,
        updates: updates,
        includeAlreadyWatchedForMarked: includeAlreadyWatchedForMarked,
        rewatch: rewatch,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _watchedEpisodes = previous;
        _episodeWatchedAt = previousAt;
        _episodeViewCounts = previousCounts;
      });
      _updateTvStatus(details);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de mettre à jour la saison: $e')),
      );
    }
  }

  Future<List<int>> _episodeNumbersToMark(
    int mediaId,
    Season season,
    bool watched, {
    int? maxEpisodeForTarget,
  }) async {
    final maxEpisode = maxEpisodeForTarget ?? season.episodeCount;
    if (!watched) {
      return List<int>.generate(maxEpisode, (i) => i + 1, growable: false);
    }
    final episodes = await _loadSeasonEpisodesForMarking(mediaId, season);
    final released =
        episodes
            .where(_isReleasedEpisode)
            .map((e) => e.episodeNumber)
            .where((n) => n > 0 && n <= maxEpisode)
            .toSet()
            .toList()
          ..sort();
    return released;
  }

  Future<List<Episode>> _loadSeasonEpisodesForMarking(
    int mediaId,
    Season season,
  ) async {
    if (season.episodes.isNotEmpty) return season.episodes;
    try {
      return await widget.repository.getSeasonEpisodes(
        mediaId,
        season.seasonNumber,
      );
    } catch (_) {
      return const <Episode>[];
    }
  }

  bool _isReleasedEpisode(Episode episode) {
    final raw = episode.airDate;
    if (raw == null || raw.isEmpty) return false;
    final date = DateTime.tryParse(raw);
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final airDay = DateTime(date.year, date.month, date.day);
    return !airDay.isAfter(today);
  }

  Future<void> _ensureTvTrackedForEpisodeUpdate(MediaDetails details) async {
    if (_tracked) return;
    final category = details.watchCategory();
    final total = details.seasons
        .where((s) => s.seasonNumber != 0)
        .fold(0, (acc, s) => acc + s.episodeCount);
    await widget.repository.addToWatchlist(
      details.toMedia(),
      category,
      category.defaultStatus(),
      total,
    );
    setState(() {
      _tracked = true;
      _status = category.defaultStatus();
    });
  }

  void _updateTvStatus(MediaDetails details) {
    final total = details.seasons
        .where((s) => s.seasonNumber != 0)
        .fold(0, (acc, s) => acc + s.episodeCount);
    final watched = _watchedEpisodes.where((k) => !k.startsWith('0_')).length;
    WatchStatus newStatus;
    if (watched <= 0) {
      newStatus = WatchStatus.notStarted;
    } else if (total > 0 && watched >= total) {
      newStatus = details.tvStatus == TvStatus.ended
          ? WatchStatus.completed
          : WatchStatus.upToDate;
    } else {
      newStatus = WatchStatus.inProgress;
    }
    if (_status != newStatus) {
      setState(() => _status = newStatus);
      widget.repository.updateWatchStatus(
        details.toMedia(),
        details.watchCategory(),
        newStatus,
      );
    }
  }

  void _onSeasonEpisodesLoaded(int seasonNumber, List<Episode> episodes) {
    _episodesBySeason[seasonNumber] = episodes;
  }

  Future<bool?> _showMarkUpToDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
        title: const Text('Épisodes précédents manquants'),
        content: const Text(
          'Des épisodes précédents ne sont pas cochés. Voulez-vous aussi les cocher ?',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Seulement celui-ci'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text("Cocher jusqu'ici"),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleEpisodeWithCheck(Episode episode, bool target) async {
    final details = _details;
    if (details == null) return;
    final key = episode.watchKey;
    final alreadyWatched = _watchedEpisodes.contains(key);
    if (episode.seasonNumber == 0) {
      if (!target && alreadyWatched) {
        final dates = await widget.repository.getEpisodeWatchDates(
          mediaId: details.id,
          seasonNumber: episode.seasonNumber,
          episodeNumber: episode.episodeNumber,
        );
        final choice = await _showRewatchDialog(context, watchedDates: dates);
        if (!mounted || choice == null) return;
        if (choice == RewatchChoice.rewatch) {
          await _setEpisodeWatched(episode, true, null, true);
        } else if (dates.length > 1) {
          final selected = await _showWatchDatePickerDialog(dates);
          if (selected == null) return;
          await _deleteEpisodeWatchDate(episode, selected);
          return;
        } else {
          await _setEpisodeWatched(episode, false, null, false);
        }
        return;
      }
      await _setEpisodeWatched(episode, target, null, false);
      return;
    }
    if (target && alreadyWatched) {
      await _setEpisodeWatched(episode, true, null, true);
      return;
    }
    if (!target) {
      final dates = await widget.repository.getEpisodeWatchDates(
        mediaId: details.id,
        seasonNumber: episode.seasonNumber,
        episodeNumber: episode.episodeNumber,
      );
      final choice = await _showRewatchDialog(context, watchedDates: dates);
      if (!mounted || choice == null) return;
      if (choice == RewatchChoice.rewatch) {
        await _setEpisodeWatched(episode, true, null, true);
      } else if (dates.length > 1) {
        final selected = await _showWatchDatePickerDialog(dates);
        if (selected == null) return;
        await _deleteEpisodeWatchDate(episode, selected);
      } else {
        await _setEpisodeWatched(episode, false, null, false);
      }
      return;
    }
    final (orderedSeasons, offsets) = _orderedSeasonsAndOffsets(details);
    final seasonOffset = offsets[episode.seasonNumber] ?? 0;
    final expectedPreviousCount = seasonOffset + episode.episodeNumber - 1;

    final watchedPositions =
        _watchedEpisodes
            .where((k) => !k.startsWith('0_'))
            .map((k) {
              final idx = k.indexOf('_');
              if (idx <= 0 || idx >= k.length - 1) return null;
              final s = int.tryParse(k.substring(0, idx));
              final e = int.tryParse(k.substring(idx + 1));
              if (s == null || e == null) return null;
              return s * 10000 + e;
            })
            .whereType<int>()
            .toList()
          ..sort();

    final currentKey = episode.seasonNumber * 10000 + episode.episodeNumber;
    var watchedPrevious = 0;
    for (final k in watchedPositions) {
      if (k < currentKey) watchedPrevious++;
    }

    if (watchedPrevious < expectedPreviousCount) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final shouldMarkUpTo = await _showMarkUpToDialog();
      if (!mounted || shouldMarkUpTo == null) return;
      if (shouldMarkUpTo) {
        await _markEpisodeUpTo(episode, now);
      } else {
        await _setEpisodeWatched(episode, true, now, false);
      }
      return;
    }
    await _setEpisodeWatched(episode, true, null, false);
  }

  Future<int?> _showWatchDatePickerDialog(List<int> dates) {
    if (dates.isEmpty) return Future<int?>.value(null);
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
        title: const Text('Supprimer un visionnage'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final watchedAt in dates)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(formatWatchDateLabel(watchedAt)),
                    trailing: const Icon(Icons.delete_outline_rounded),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: ctx,
                        builder: (confirmCtx) => AlertDialog(
                          backgroundColor: Theme.of(confirmCtx)
                              .colorScheme
                              .surfaceContainerHigh,
                          title: const Text('Confirmer la suppression'),
                          content: Text(
                            'Supprimer le visionnage du ${formatWatchDateLabel(watchedAt)} ?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(confirmCtx).pop(false),
                              child: const Text('Annuler'),
                            ),
                            FilledButton.icon(
                              onPressed: () =>
                                  Navigator.of(confirmCtx).pop(true),
                              icon: const Icon(Icons.delete_rounded, size: 18),
                              label: const Text('Supprimer'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        Navigator.of(ctx).pop(watchedAt);
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMovieWatchDate(int watchedAtMillis) async {
    final details = _details;
    if (details == null) return;
    final previousDates = List<int>.from(_movieWatchDates);
    final previousCount = _movieViewCount;
    final previousStatus = _status;
    final previousFirst = _movieWatchedAtMillis;
    final remaining = _movieWatchDates
        .where((millis) => millis != watchedAtMillis)
        .toList();
    setState(() {
      _movieWatchDates = remaining;
      _movieViewCount = remaining.length;
      _movieWatchedAtMillis = remaining.isNotEmpty ? remaining.first : null;
      _status = remaining.isNotEmpty
          ? WatchStatus.watched
          : WatchStatus.notWatched;
    });
    try {
      await widget.repository.deleteMovieWatchEvent(
        details.toMedia(),
        details.watchCategory(),
        watchedAtMillis: watchedAtMillis,
      );
      await _refreshProgressState();
      final refreshedDates = await widget.repository.getMovieWatchDates(
        details.id,
      );
      final refreshedCount = await widget.repository.getMovieViewCount(
        details.id,
      );
      if (mounted) {
        setState(() {
          _movieWatchDates = refreshedDates;
          _movieViewCount = refreshedCount;
          _movieWatchedAtMillis = refreshedDates.isNotEmpty
              ? refreshedDates.first
              : null;
          _status = refreshedCount > 0
              ? WatchStatus.watched
              : WatchStatus.notWatched;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _movieWatchDates = previousDates;
        _movieViewCount = previousCount;
        _movieWatchedAtMillis = previousFirst;
        _status = previousStatus;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de supprimer ce visionnage: $e')),
      );
    }
  }

  Future<void> _deleteEpisodeWatchDate(
    Episode episode,
    int watchedAtMillis,
  ) async {
    final details = _details;
    if (details == null) return;
    final key = episode.watchKey;
    final previousWatched = <String>{..._watchedEpisodes};
    final previousAt = Map<String, int>.from(_episodeWatchedAt);
    final previousCounts = Map<String, int>.from(_episodeViewCounts);
    final nextWatched = <String>{..._watchedEpisodes};
    final nextAt = Map<String, int>.from(_episodeWatchedAt);
    final nextCounts = Map<String, int>.from(_episodeViewCounts);
    final remainingDates = (await widget.repository.getEpisodeWatchDates(
      mediaId: details.id,
      seasonNumber: episode.seasonNumber,
      episodeNumber: episode.episodeNumber,
    )).where((millis) => millis != watchedAtMillis).toList();
    if (remainingDates.isEmpty) {
      nextWatched.remove(key);
      nextAt.remove(key);
      nextCounts.remove(key);
    } else {
      nextWatched.add(key);
      nextAt[key] = remainingDates.first;
      nextCounts[key] = remainingDates.length;
    }
    setState(() {
      _watchedEpisodes = nextWatched;
      _episodeWatchedAt = nextAt;
      _episodeViewCounts = nextCounts;
    });
    _updateTvStatus(details);
    try {
      await widget.repository.deleteEpisodeWatchEvent(
        mediaId: details.id,
        seasonNumber: episode.seasonNumber,
        episodeNumber: episode.episodeNumber,
        watchedAtMillis: watchedAtMillis,
      );
      await _refreshProgressState();
      final progress = await widget.repository.getEpisodeProgress(details.id);
      final viewCounts = Map<String, int>.from(
        await widget.repository.getEpisodeViewCounts(details.id),
      );
      final watchedSet = progress
          .where((p) => p.isWatched)
          .map((p) => '${p.seasonNumber}_${p.episodeNumber}')
          .toSet();
      final watchedAtMap = {
        for (final p in progress.where((p) => p.isWatched))
          '${p.seasonNumber}_${p.episodeNumber}': p.updatedAtMillis ?? 0,
      };
      if (mounted) {
        setState(() {
          _watchedEpisodes = watchedSet;
          _episodeWatchedAt = watchedAtMap;
          _episodeViewCounts = viewCounts;
        });
        _updateTvStatus(details);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _watchedEpisodes = previousWatched;
        _episodeWatchedAt = previousAt;
        _episodeViewCounts = previousCounts;
      });
      _updateTvStatus(details);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de supprimer ce visionnage: $e')),
      );
    }
  }

  Future<void> _deleteSeasonLatestRewatches(Season season) async {
    final details = _details;
    if (details == null) return;
    final affectedEpisodes = await widget.repository
        .getEpisodeNumbersWithRewatches(
          mediaId: details.id,
          seasonNumber: season.seasonNumber,
        );
    if (affectedEpisodes.isEmpty) return;

    final previousWatched = <String>{..._watchedEpisodes};
    final previousAt = Map<String, int>.from(_episodeWatchedAt);
    final previousCounts = Map<String, int>.from(_episodeViewCounts);
    final nextCounts = Map<String, int>.from(_episodeViewCounts);

    for (final episodeNumber in affectedEpisodes) {
      final key = '${season.seasonNumber}_$episodeNumber';
      final currentCount = nextCounts[key];
      if (currentCount != null && currentCount > 1) {
        nextCounts[key] = currentCount - 1;
      }
    }

    setState(() {
      _episodeViewCounts = nextCounts;
    });

    try {
      await widget.repository.deleteLatestSeasonRewatchEvents(
        mediaId: details.id,
        seasonNumber: season.seasonNumber,
      );
      await _refreshProgressState();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _watchedEpisodes = previousWatched;
        _episodeWatchedAt = previousAt;
        _episodeViewCounts = previousCounts;
      });
      _updateTvStatus(details);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de supprimer les derniers rewatches de la saison: $e',
          ),
        ),
      );
    }
  }

  Future<RewatchChoice?> _showRewatchDialog(
    BuildContext context, {
    bool isSeason = false,
    List<int> watchedDates = const [],
  }) {
    final title = isSeason ? 'Saison déjà vue' : 'Déjà vu';
    final reviewLabel = isSeason
        ? 'Revoir la saison (+1 vue)'
        : 'Revoir (+1 vue)';
    final hasWatchHistoryDelete = watchedDates.length > 1;
    return showDialog<RewatchChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
        title: Text(title),
        content: Text(
          isSeason
              ? 'Voulez-vous marquer cette saison comme non vue ou ajouter une revue à tous ses épisodes ?'
              : 'Voulez-vous marquer cet élément comme non vu ou ajouter une revue ?',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(RewatchChoice.unwatch),
            child: Text(
              hasWatchHistoryDelete
                  ? 'Supprimer un visionnage'
                  : 'Marquer non vu',
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(RewatchChoice.rewatch),
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: Text(reviewLabel),
          ),
        ],
      ),
    );
  }

  void _showMovieWatchHistoryDialog() {
    if (_movieWatchDates.isEmpty) return;

    showWatchHistoryDialog(
      context: context,
      dates: _movieWatchDates,
      onDeleteDate: _deleteMovieWatchDate,
      closeDialogBeforeDelete: true,
    );
  }

  Future<void> _openEpisodeDetailPage(Episode episode) async {
    final details = _details;
    if (details == null) return;
    final (orderedSeasons, offsets) = _orderedSeasonsAndOffsets(details);

    final allEpisodes = <Episode>[];
    final unloadedSeasons = <int>{};
    for (final season in orderedSeasons) {
      final cached = _episodesBySeason[season.seasonNumber];
      if (cached != null && cached.isNotEmpty) {
        allEpisodes.addAll(cached);
      } else if (season.episodes.isNotEmpty) {
        _episodesBySeason[season.seasonNumber] = season.episodes;
        allEpisodes.addAll(season.episodes);
      } else {
        unloadedSeasons.add(season.seasonNumber);
        allEpisodes.addAll(
          List.generate(
            season.episodeCount,
            (index) => Episode(
              id: 0,
              name: 'Épisode ${index + 1}',
              overview: '',
              episodeNumber: index + 1,
              seasonNumber: season.seasonNumber,
              stillPath: null,
            ),
          ),
        );
      }
    }

    if (allEpisodes.isEmpty || !mounted) return;

    final index = allEpisodes.indexWhere(
      (e) =>
          e.seasonNumber == episode.seasonNumber &&
          e.episodeNumber == episode.episodeNumber,
    );
    if (index < 0) return;

    await Navigator.of(context).push<void>(
      SlideUpRoute(
        builder: (ctx) => EpisodeDetailPage(
          episodes: allEpisodes,
          unloadedSeasons: unloadedSeasons,
          loadSeasonEpisodes: (seasonNumber) async {
            final episodes = await widget.repository.getSeasonEpisodes(
              details.id,
              seasonNumber,
            );
            _episodesBySeason[seasonNumber] = episodes;
            return episodes;
          },
          initialIndex: index,
          mediaId: details.id,
          repository: widget.repository,
          watchedEpisodes: _watchedEpisodes,
          episodeWatchedAt: _episodeWatchedAt,
          episodeViewCounts: _episodeViewCounts,
          seasonOffsets: offsets,
          seriesTitle: details.title,
          isReleasedCheck: _isReleasedEpisode,
          onToggleWatched: _toggleEpisodeWithCheck,
          getProgress: () => (
            watched: _watchedEpisodes,
            watchedAt: _episodeWatchedAt,
            viewCounts: _episodeViewCounts,
          ),
        ),
      ),
    );
    if (mounted) {
      await _refreshProgressState();
    }
  }

  Color? _progressColor() {
    return switch (_status) {
      WatchStatus.inProgress => const Color(0xFFFFC107),
      WatchStatus.upToDate => const Color(0xFF4CAF50),
      WatchStatus.completed || WatchStatus.watched => const Color(0xFF9C27B0),
      _ => null,
    };
  }

  double _progressValue(MediaDetails details) {
    if (_status == WatchStatus.inProgress) {
      final total = details.seasons
          .where((s) => s.seasonNumber != 0)
          .fold(0, (acc, s) => acc + s.episodeCount);
      if (total <= 0) return 0;
      final watched = _watchedEpisodes.where((k) => !k.startsWith('0_')).length;
      return (watched / total).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  void _setTvTab(bool showEpisodes) {
    if (_showEpisodes == showEpisodes) return;
    setState(() {
      _tvTabDirection = showEpisodes ? 1 : -1;
      _showEpisodes = showEpisodes;
    });
  }

  void _handleTvTabSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    const minSwipeVelocity = 250.0;
    const minSwipeDistance = 80.0;
    if ((velocity <= -minSwipeVelocity || _tvSwipeDelta <= -minSwipeDistance) &&
        !_showEpisodes) {
      _setTvTab(true);
    } else if ((velocity >= minSwipeVelocity ||
            _tvSwipeDelta >= minSwipeDistance) &&
        _showEpisodes) {
      _setTvTab(false);
    }
    _tvSwipeDelta = 0;
  }

  Future<Episode?> _findNextEpisodeToWatch(
    MediaDetails details,
    List<Season> orderedSeasons,
  ) async {
    for (final season in orderedSeasons.where((s) => s.seasonNumber != 0)) {
      List<Episode> seasonEpisodes =
          _episodesBySeason[season.seasonNumber] ?? season.episodes;
      if (seasonEpisodes.isEmpty && season.episodeCount > 0) {
        final fetched = await widget.repository.getSeasonEpisodes(
          details.id,
          season.seasonNumber,
        );
        _episodesBySeason[season.seasonNumber] = fetched;
        seasonEpisodes = fetched;
      }
      if (seasonEpisodes.isEmpty) continue;
      final orderedEpisodes = [...seasonEpisodes]
        ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      for (final episode in orderedEpisodes) {
        if (!_isReleasedEpisode(episode)) continue;
        if (_watchedEpisodes.contains(episode.watchKey)) continue;
        return episode;
      }
    }
    return null;
  }

  Future<void> _goToNextEpisode() async {
    final details = _details;
    if (details == null || details.mediaType != MediaType.tv) return;
    if (_navigatingToNextEpisode) return;

    setState(() {
      _navigatingToNextEpisode = true;
    });
    try {
      final (orderedSeasons, _) = _orderedSeasonsAndOffsets(details);
      late final Episode? nextEpisode;
      try {
        nextEpisode = await _findNextEpisodeToWatch(details, orderedSeasons);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Impossible de charger les épisodes pour trouver le prochain: $e',
            ),
          ),
        );
        return;
      }
      if (!mounted) return;

      if (nextEpisode == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun prochain épisode à regarder.')),
        );
        return;
      }

      setState(() {
        _tvTabDirection = 1;
        _showEpisodes = true;
        _nextEpisodeTarget = nextEpisode;
        _nextEpisodeJumpToken++;
      });
    } finally {
      if (mounted) {
        setState(() {
          _navigatingToNextEpisode = false;
        });
      }
    }
  }

  Widget _buildNextEpisodeFab(bool isTV) {
    if (!isTV) return const SizedBox.shrink();
    return _NextEpisodeFab(
      showExtended: _showExtendedNextEpisodeCta,
      navigating: _navigatingToNextEpisode,
      onTap: _navigatingToNextEpisode ? null : _goToNextEpisode,
    );
  }

  Widget _buildTvTabContent(
    MediaDetails details,
    List<Season> orderedSeasons,
    Map<int, int> seasonOffsets,
  ) {
    const aboutKey = ValueKey('tv-tab-about');
    const episodesKey = ValueKey('tv-tab-episodes');
    final direction = _tvTabDirection.toDouble();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, _) =>
          currentChild ?? const SizedBox.shrink(),
      transitionBuilder: (child, animation) {
        return ClipRect(
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(direction * 0.18, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _showEpisodes
          ? KeyedSubtree(
              key: episodesKey,
              child: orderedSeasons.isEmpty
                  ? _buildNoSeasonsState()
                  : Column(
                      children: [
                        for (final season in orderedSeasons)
                          SeasonSection(
                            key: PageStorageKey<String>(
                              'season_${details.id}_${season.seasonNumber}',
                            ),
                            mediaId: details.id,
                            repository: widget.repository,
                            parentScrollController: _scrollCtrl,
                            season: season,
                            seasonOffset:
                                seasonOffsets[season.seasonNumber] ?? 0,
                            watchedEpisodes: _watchedEpisodes,
                            episodeViewCounts: _episodeViewCounts,
                            onToggleEpisode:
                                (episode, watched, updatedAtMillis) =>
                                    _setEpisodeWatched(
                                      episode,
                                      watched,
                                      updatedAtMillis,
                                      false,
                                    ),
                            onDeleteEpisodeWatchDate: _deleteEpisodeWatchDate,
                            onDeleteSeasonLatestRewatches:
                                _deleteSeasonLatestRewatches,
                            onMarkSeasonWatched: _markSeasonWatched,
                            onRewatchSeason: (targetSeason) =>
                                _markSeasonWatched(
                                  targetSeason,
                                  true,
                                  includeAlreadyWatched: true,
                                  rewatch: true,
                                ),
                            onMarkOnlySeasonWatched: _markOnlySeasonWatched,
                            onMarkEpisodeUpTo: _markEpisodeUpTo,
                            onOpenEpisode: _openEpisodeDetailPage,
                            onEpisodesLoaded: _onSeasonEpisodesLoaded,
                            jumpRequestToken: _nextEpisodeJumpToken,
                            jumpTargetEpisode: _nextEpisodeTarget,
                          ),
                      ],
                    ),
            )
          : KeyedSubtree(
              key: aboutKey,
              child: _TvAbout(
                details: details,
                category: details.watchCategory(),
              ),
            ),
    );
  }

  Widget _buildNoSeasonsState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.38),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 34,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                'Aucune saison disponible',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Les données de saisons/épisodes ne sont pas encore en cache pour ce titre. Connecte-toi au réseau puis réessaye.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _details == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      final isOffline = isOfflineOrServerUnreachableError(_error!);
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOffline ? Icons.cloud_off_rounded : Icons.error_outline,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  isOffline
                      ? 'Ce contenu n\'est pas disponible hors-ligne.'
                      : 'Impossible de charger ce contenu.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  isOffline
                      ? 'Aucune donnée en cache n\'a été trouvée pour cette série/ce film. Connecte-toi au réseau pour charger les informations.'
                      : _error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final details = _details;
    if (details == null) return const Scaffold(body: SizedBox.shrink());

    final isTV = details.mediaType == MediaType.tv;
    final progressColor = (_tracked && isTV) ? _progressColor() : null;
    final (orderedSeasons, seasonOffsets) = _orderedSeasonsAndOffsets(details);
    final statusBarHeight = MediaQuery.paddingOf(context).top;

    return Scaffold(
      bottomNavigationBar: !_tracked
          ? _AddBottomBar(
              category: details.watchCategory(),
              onAdd: _toggleWatchlist,
            )
          : null,
      floatingActionButton: _buildNextEpisodeFab(isTV),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: isTV ? (_) => _tvSwipeDelta = 0 : null,
        onHorizontalDragUpdate: isTV
            ? (details) => _tvSwipeDelta += details.primaryDelta ?? 0
            : null,
        onHorizontalDragEnd: isTV ? _handleTvTabSwipe : null,
        child: CustomScrollView(
          controller: _scrollCtrl,
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _DetailsHeaderDelegate(
                details: details,
                isTV: isTV,
                showEpisodes: _showEpisodes,
                onShowEpisodesChanged: _setTvTab,
                tracked: _tracked,
                progressColor: progressColor,
                progressValue: progressColor != null
                    ? _progressValue(details)
                    : null,
                watchedGlobal: _tracked && isTV
                    ? _watchedEpisodes.where((k) => !k.startsWith('0_')).length
                    : null,
                totalGlobal: _tracked && isTV
                    ? details.seasons
                          .where((s) => s.seasonNumber != 0)
                          .fold<int>(0, (acc, s) => acc + s.episodeCount)
                    : null,
                onBack: () => Navigator.of(context).pop(),
                onToggleWatchlist: _toggleWatchlist,
                statusBarHeight: statusBarHeight,
              ),
            ),
            if (isTV)
              SliverToBoxAdapter(
                child: _buildTvTabContent(
                  details,
                  orderedSeasons,
                  seasonOffsets,
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: _MovieInfoStrip(
                  releaseDate: details.releaseDate,
                  isWatched: _status == WatchStatus.watched,
                  watchedAtMillis: _movieWatchedAtMillis,
                  movieViewCount: _movieViewCount,
                  onChanged: _setMovieWatched,
                  onShowHistory: _movieWatchDates.length > 1
                      ? _showMovieWatchHistoryDialog
                      : null,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Synopsis',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        details.overview.isEmpty
                            ? 'Aucun synopsis disponible.'
                            : details.overview,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  List<Season> _orderedSeasons(List<Season> seasons) {
    final specials = seasons.where((s) => s.seasonNumber == 0).toList();
    final regular = seasons.where((s) => s.seasonNumber != 0).toList()
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    return [...regular, ...specials];
  }

  Map<int, int> _seasonOffsets(List<Season> seasons) {
    var offset = 0;
    final map = <int, int>{};
    for (final season in seasons.where((s) => s.seasonNumber != 0)) {
      map[season.seasonNumber] = offset;
      offset += season.episodeCount < 0 ? 0 : season.episodeCount;
    }
    return map;
  }

  MediaDetails? _seasonsCacheSource;
  List<Season>? _cachedOrderedSeasons;
  Map<int, int>? _cachedSeasonOffsets;

  /// Returns the ordered seasons and their episode offsets for [details],
  /// recomputing only when `details` itself changes (new instance returned
  /// by `_load`/`_refreshProgressState`) instead of on every `build()`.
  (List<Season>, Map<int, int>) _orderedSeasonsAndOffsets(
    MediaDetails details,
  ) {
    if (!identical(_seasonsCacheSource, details)) {
      final ordered = _orderedSeasons(details.seasons);
      _seasonsCacheSource = details;
      _cachedOrderedSeasons = ordered;
      _cachedSeasonOffsets = _seasonOffsets(ordered);
    }
    return (_cachedOrderedSeasons!, _cachedSeasonOffsets!);
  }
}

/// Floating "next episode" CTA, isolated from [_DetailsScreenState] so that
/// toggling its compact/extended label on scroll (every scroll frame) only
/// rebuilds this small subtree via [showExtended], instead of the whole
/// details screen.
class _NextEpisodeFab extends StatelessWidget {
  const _NextEpisodeFab({
    required this.showExtended,
    required this.navigating,
    required this.onTap,
  });

  final ValueListenable<bool> showExtended;
  final bool navigating;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.primaryContainer,
      elevation: 6,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        key: const ValueKey('next-episode-fab'),
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: ValueListenableBuilder<bool>(
          valueListenable: showExtended,
          builder: (context, extended, _) {
            return AnimatedContainer(
              key: const ValueKey('next-episode-fab-container'),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeInOutCubic,
              height: 56,
              width: extended ? 186 : 56,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(
                    left: 16,
                    child: navigating
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          )
                        : Icon(
                            Icons.play_arrow_rounded,
                            color: colorScheme.onPrimaryContainer,
                          ),
                  ),
                  Positioned(
                    left: 44,
                    right: 16,
                    child: ClipRect(
                      child: AnimatedAlign(
                        alignment: Alignment.centerLeft,
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeInOutCubic,
                        widthFactor: extended ? 1 : 0,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeInOutCubic,
                          opacity: extended ? 1 : 0,
                          child: Text(
                            'Aller au prochain',
                            key: const ValueKey('next-episode-fab-label'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DetailsHeaderDelegate extends SliverPersistentHeaderDelegate {
  _DetailsHeaderDelegate({
    required this.details,
    required this.isTV,
    required this.showEpisodes,
    required this.onShowEpisodesChanged,
    required this.tracked,
    required this.progressColor,
    required this.progressValue,
    required this.onBack,
    required this.onToggleWatchlist,
    required this.statusBarHeight,
    this.watchedGlobal,
    this.totalGlobal,
  });

  final MediaDetails details;
  final bool isTV;
  final bool showEpisodes;
  final ValueChanged<bool> onShowEpisodesChanged;
  final bool tracked;
  final Color? progressColor;
  final double? progressValue;
  final VoidCallback onBack;
  final VoidCallback onToggleWatchlist;
  final double statusBarHeight;
  final int? watchedGlobal;
  final int? totalGlobal;

  static const double _headerMaxBase = 210;
  static const double _headerMinBase = 59;
  static const double _tabsHeight = 48;

  @override
  double get minExtent =>
      _headerMinBase + statusBarHeight + (isTV ? _tabsHeight : 0);

  @override
  double get maxExtent =>
      _headerMaxBase + statusBarHeight + (isTV ? _tabsHeight : 0);

  double get _collapseRange => _headerMaxBase - _headerMinBase;

  @override
  bool shouldRebuild(covariant _DetailsHeaderDelegate old) => true;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = (shrinkOffset / _collapseRange).clamp(0.0, 1.0);
    final titleAlpha = ((progress - 0.75) / 0.25).clamp(0.0, 1.0);
    final contentAlpha = (1.0 - titleAlpha).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Backdrop image — fills the header minus the tabs area
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: isTV ? _tabsHeight : 0,
          child: MediaHeader(
            details: details,
            contentAlpha: contentAlpha,
            progressColor: progressColor,
            progressValue: progressValue,
            watchedGlobal: watchedGlobal,
            totalGlobal: totalGlobal,
          ),
        ),

        // Tab bar — always pinned at the bottom of the header (TV only)
        if (isTV)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: _tabsHeight,
            child: _TvTabs(
              showEpisodes: showEpisodes,
              onChanged: onShowEpisodesChanged,
            ),
          ),

        // Action row (back button, collapsing title, menu)
        Positioned(
          top: statusBarHeight,
          left: 0,
          right: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                  onPressed: onBack,
                ),
                Expanded(
                  child: titleAlpha > 0
                      ? Text(
                          details.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: titleAlpha),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : const SizedBox.shrink(),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white,
                  ),
                  onSelected: (value) {
                    if (value == 'toggle') onToggleWatchlist();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(
                        tracked ? 'Retirer des suivis' : 'Ajouter aux suivis',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TvTabs extends StatelessWidget {
  const _TvTabs({required this.showEpisodes, required this.onChanged});

  final bool showEpisodes;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary;
    final selectedTextColor = Theme.of(context).colorScheme.onSurface;
    final unselectedTextColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final textTheme = Theme.of(context).textTheme.labelLarge;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: _TvTabButton(
              label: 'À propos',
              selected: !showEpisodes,
              selectedColor: selectedColor,
              selectedTextColor: selectedTextColor,
              unselectedTextColor: unselectedTextColor,
              textStyle: textTheme,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _TvTabButton(
              label: 'Épisodes',
              selected: showEpisodes,
              selectedColor: selectedColor,
              selectedTextColor: selectedTextColor,
              unselectedTextColor: unselectedTextColor,
              textStyle: textTheme,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvTabButton extends StatelessWidget {
  const _TvTabButton({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.selectedTextColor,
    required this.unselectedTextColor,
    required this.textStyle,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final Color selectedTextColor;
  final Color unselectedTextColor;
  final TextStyle? textStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? selectedColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: textStyle?.copyWith(
            color: selected ? selectedTextColor : unselectedTextColor,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _TvAbout extends StatelessWidget {
  const _TvAbout({required this.details, required this.category});

  final MediaDetails details;
  final WatchCategory category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category == WatchCategory.anime
                ? 'Informations sur l\'animé'
                : 'Informations sur la série',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            details.overview.isEmpty
                ? 'Aucun synopsis disponible.'
                : details.overview,
          ),
        ],
      ),
    );
  }
}

class _MovieInfoStrip extends StatelessWidget {
  const _MovieInfoStrip({
    required this.releaseDate,
    required this.isWatched,
    required this.watchedAtMillis,
    required this.movieViewCount,
    required this.onChanged,
    this.onShowHistory,
  });

  final String? releaseDate;
  final bool isWatched;
  final int? watchedAtMillis;
  final int movieViewCount;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onShowHistory;

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return 'Date inconnue';
    try {
      final d = DateTime.parse(raw);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return raw;
    }
  }

  String _formatMillis(int? raw) {
    if (raw == null) return 'Vu';
    final d = DateTime.fromMillisecondsSinceEpoch(raw);
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.calendar_month_rounded, size: 16),
                  label: Text(_formatDate(releaseDate)),
                ),
                Chip(
                  avatar: const Icon(Icons.visibility_rounded, size: 16),
                  label: Text(
                    isWatched ? _formatMillis(watchedAtMillis) : 'Pas vu',
                  ),
                ),
                if (isWatched && movieViewCount > 1 && onShowHistory != null)
                  ActionChip(
                    key: const ValueKey('movie-rewatch-history-chip'),
                    avatar: const Icon(Icons.history_rounded, size: 16),
                    label: Text('x$movieViewCount vues'),
                    onPressed: onShowHistory,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          WatchedToggleButton(
            key: const ValueKey('movie-watched-toggle'),
            checked: isWatched,
            reviewCount: isWatched && movieViewCount > 1
                ? movieViewCount
                : null,
            onTap: () => onChanged(!isWatched),
            tooltip: isWatched
                ? 'Marquer le film non vu'
                : 'Marquer le film vu',
            size: 36,
          ),
        ],
      ),
    );
  }
}

class _AddBottomBar extends StatelessWidget {
  const _AddBottomBar({required this.category, required this.onAdd});

  final WatchCategory category;
  final VoidCallback onAdd;

  String get _label {
    return switch (category) {
      WatchCategory.films => '+ Ajouter le film',
      WatchCategory.anime => '+ Ajouter l\'animé',
      _ => '+ Ajouter la série',
    };
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: GestureDetector(
        onTap: onAdd,
        child: Container(
          width: double.infinity,
          height: 59,
          color: const Color(0xFFFFD400),
          alignment: Alignment.center,
          child: Text(
            _label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xC7000000),
            ),
          ),
        ),
      ),
    );
  }
}
