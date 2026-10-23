// ignore_for_file: use_build_context_synchronously

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/date_formatter.dart';
import '../../../core/episode_watch_key.dart';
import '../../../core/network_error_classifier.dart';
import '../../../data/models/details_models.dart';
import '../../../data/repositories/media_repository.dart';
import 'rewatch_choice.dart';
class WatchedToggleButton extends StatelessWidget {
  const WatchedToggleButton({
    super.key,
    required this.checked,
    required this.onTap,
    required this.tooltip,
    this.reviewCount,
    this.size = 34,
  });

  final bool checked;
  final VoidCallback? onTap;
  final String tooltip;
  final int? reviewCount;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = colorScheme.primary;
    final inactiveColor = colorScheme.surfaceContainerHigh;
    final borderColor = checked ? activeColor : colorScheme.outlineVariant;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        checked: checked,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked ? activeColor : inactiveColor,
                border: Border.all(color: borderColor),
                boxShadow: checked
                    ? [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: !checked
                      ? Container(
                          key: const ValueKey('unchecked'),
                          width: size * 0.18,
                          height: size * 0.18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.outlineVariant,
                          ),
                        )
                      : (reviewCount ?? 0) > 1
                      ? Text(
                          'x${reviewCount!}',
                          key: ValueKey('review-count-${reviewCount!}'),
                          style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: size * 0.32,
                          ),
                        )
                      : Icon(
                          Icons.check_rounded,
                          key: const ValueKey('checked'),
                          color: colorScheme.onPrimary,
                          size: size * 0.56,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SeasonSection extends StatefulWidget {
  const SeasonSection({
    super.key,
    required this.mediaId,
    required this.repository,
    required this.parentScrollController,
    required this.season,
    required this.seasonOffset,
    required this.watchedEpisodes,
    required this.episodeViewCounts,
    required this.onToggleEpisode,
    required this.onDeleteEpisodeWatchDate,
    required this.onDeleteSeasonLatestRewatches,
    required this.onMarkSeasonWatched,
    required this.onRewatchSeason,
    required this.onMarkOnlySeasonWatched,
    required this.onMarkEpisodeUpTo,
    required this.onOpenEpisode,
    required this.onEpisodesLoaded,
    required this.jumpRequestToken,
    required this.jumpTargetEpisode,
  });

  final int mediaId;
  final MediaRepository repository;
  final ScrollController parentScrollController;
  final Season season;
  final int seasonOffset;
  final Set<String> watchedEpisodes;
  final Map<String, int> episodeViewCounts;
  final Future<void> Function(Episode, bool, int?) onToggleEpisode;
  final Future<void> Function(Episode, int) onDeleteEpisodeWatchDate;
  final Future<void> Function(Season) onDeleteSeasonLatestRewatches;
  final Future<void> Function(Season, bool) onMarkSeasonWatched;
  final Future<void> Function(Season) onRewatchSeason;
  final Future<void> Function(Season, bool) onMarkOnlySeasonWatched;
  final Future<void> Function(Episode, int?) onMarkEpisodeUpTo;
  final Future<void> Function(Episode) onOpenEpisode;
  final void Function(int seasonNumber, List<Episode> episodes)
  onEpisodesLoaded;
  final int jumpRequestToken;
  final Episode? jumpTargetEpisode;

  @override
  State<SeasonSection> createState() => _SeasonSectionState();
}

class _SeasonSectionState extends State<SeasonSection> {
  bool _expanded = false;
  bool _loadingEpisodes = false;
  bool _episodesLoadFailed = false;
  List<Episode> _episodes = [];
  final ScrollController _episodesScrollCtrl = ScrollController();
  int _lastHandledJumpToken = 0;
  final Map<String, GlobalKey> _episodeTileKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _maybeHandleJumpToEpisode();
      }
    });
  }

  @override
  void didUpdateWidget(covariant SeasonSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.jumpRequestToken != oldWidget.jumpRequestToken ||
        widget.jumpTargetEpisode != oldWidget.jumpTargetEpisode) {
      _maybeHandleJumpToEpisode();
    }
  }

  @override
  void dispose() {
    _episodesScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _maybeHandleJumpToEpisode() async {
    final target = widget.jumpTargetEpisode;
    if (target == null) return;
    if (target.seasonNumber != widget.season.seasonNumber) return;
    if (widget.jumpRequestToken == 0 ||
        widget.jumpRequestToken == _lastHandledJumpToken) {
      return;
    }

    _lastHandledJumpToken = widget.jumpRequestToken;

    await Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );

    if (!_expanded) {
      setState(() {
        _expanded = true;
      });
    }

    await _loadEpisodesIfNeeded();
    if (!mounted) return;

    final index = _episodes.indexWhere(
      (ep) =>
          ep.seasonNumber == target.seasonNumber &&
          ep.episodeNumber == target.episodeNumber,
    );
    if (index < 0) return;

    final targetKey = _episodeTileKey(target);
    final roughOffset = index * 108.0;

    for (var attempt = 0; attempt < 3; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      final targetContext = targetKey.currentContext;
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
        if (!targetContext.mounted) return;
        if (!mounted || !widget.parentScrollController.hasClients) return;
        final renderBox = targetContext.findRenderObject() as RenderBox?;
        if (renderBox == null || !renderBox.attached) return;
        final view = View.of(targetContext);
        final screenHeight = view.physicalSize.height / view.devicePixelRatio;
        final itemCenterY =
            renderBox.localToGlobal(Offset.zero).dy +
            (renderBox.size.height / 2);
        final desiredCenterY = screenHeight / 2;
        final delta = itemCenterY - desiredCenterY;
        if (delta.abs() > 8) {
          final targetOffset =
              (widget.parentScrollController.position.pixels + delta)
                  .clamp(
                    0.0,
                    widget.parentScrollController.position.maxScrollExtent,
                  )
                  .toDouble();
          await widget.parentScrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
        }
        return;
      }

      if (_episodesScrollCtrl.hasClients) {
        final nudgedOffset = (roughOffset + (attempt * 96))
            .clamp(0.0, _episodesScrollCtrl.position.maxScrollExtent)
            .toDouble();
        _episodesScrollCtrl.jumpTo(nudgedOffset);
      }
    }
  }

  GlobalKey _episodeTileKey(Episode ep) => _episodeTileKeys.putIfAbsent(
    ep.watchKey,
    () =>
        GlobalKey(debugLabel: 'episode-${ep.seasonNumber}-${ep.episodeNumber}'),
  );

  bool _isWatched(Episode ep) =>
      widget.watchedEpisodes.contains(ep.watchKey);

  int _episodeViewCount(Episode ep) =>
      widget.episodeViewCounts[ep.watchKey] ??
      (_isWatched(ep) ? 1 : 0);

  int? _episodeReviewCount(Episode ep) {
    final count = _episodeViewCount(ep);
    return count > 1 ? count : null;
  }

  bool get _isSpecialSeason => widget.season.seasonNumber == 0;

  int _countWatchedBeforePosition(List<int> watchedPositions, int value) {
    var left = 0;
    var right = watchedPositions.length;
    while (left < right) {
      final mid = (left + right) >> 1;
      if (watchedPositions[mid] < value) {
        left = mid + 1;
      } else {
        right = mid;
      }
    }
    return left;
  }

  int _expectedPreviousCount(Episode episode) =>
      widget.seasonOffset + episode.episodeNumber - 1;

  int? _parseEpisodePositionKey(String key) {
    final idx = key.indexOf('_');
    if (idx <= 0 || idx >= key.length - 1) return null;
    final s = int.tryParse(key.substring(0, idx));
    final e = int.tryParse(key.substring(idx + 1));
    if (s == null || e == null) return null;
    return _episodePositionKey(s, e);
  }

  int _episodePositionKey(int seasonNumber, int episodeNumber) =>
      seasonNumber * 10000 + episodeNumber;

  Future<void> _loadEpisodesIfNeeded() async {
    if (_episodes.isNotEmpty || widget.season.episodeCount <= 0) return;
    if (widget.season.episodes.isNotEmpty) {
      setState(() => _episodes = widget.season.episodes);
      widget.onEpisodesLoaded(
        widget.season.seasonNumber,
        widget.season.episodes,
      );
      return;
    }
    setState(() {
      _loadingEpisodes = true;
      _episodesLoadFailed = false;
    });
    try {
      final fetched = await widget.repository.getSeasonEpisodes(
        widget.mediaId,
        widget.season.seasonNumber,
      );
      if (!mounted) return;
      final fetchedFromCache = widget.repository.lastFetchWasFromCache;
      setState(() => _episodes = fetched);
      widget.onEpisodesLoaded(widget.season.seasonNumber, fetched);
      if (fetchedFromCache) {
        _showEpisodesOfflineSnackbar();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _episodesLoadFailed = true);
      final message = e.toString();
      final friendly = isOfflineOrServerUnreachableError(message)
          ? 'Hors-ligne: aucun épisode en cache pour cette saison.'
          : 'Impossible de charger les épisodes.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendly)));
    } finally {
      if (mounted) {
        setState(() => _loadingEpisodes = false);
      }
    }
  }

  void _showEpisodesOfflineSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.cloud_off, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '⚠️ Liste d\'épisodes en cache',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.amber.shade700,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _onEpisodeCheckRequest(Episode episode, bool target) async {
    if (!target) {
      if (_isWatched(episode)) {
        final dates = await widget.repository.getEpisodeWatchDates(
          mediaId: widget.mediaId,
          seasonNumber: episode.seasonNumber,
          episodeNumber: episode.episodeNumber,
        );
        final choice = await _showRewatchEpisodeDialog(dates);
        if (choice == null) return;
        if (choice == RewatchChoice.rewatch) {
          await widget.onToggleEpisode(episode, true, null);
        } else if (dates.length > 1) {
          final selected = await _showWatchDatePickerDialog(dates);
          if (selected == null) return;
          await widget.onDeleteEpisodeWatchDate(episode, selected);
        } else {
          await widget.onToggleEpisode(episode, false, null);
        }
        return;
      }
      await widget.onToggleEpisode(episode, false, null);
      return;
    }
    if (_isSpecialSeason) {
      await widget.onToggleEpisode(episode, true, null);
      return;
    }
    final watchedPositions =
        widget.watchedEpisodes
            .map(_parseEpisodePositionKey)
            .whereType<int>()
            .toList()
          ..sort();
    final current = _episodePositionKey(
      episode.seasonNumber,
      episode.episodeNumber,
    );
    final watchedPrevious = _countWatchedBeforePosition(
      watchedPositions,
      current,
    );
    if (watchedPrevious < _expectedPreviousCount(episode)) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final shouldMarkUpTo = await _showMarkPreviousEpisodesDialog();
      if (!mounted || shouldMarkUpTo == null) return;
      if (shouldMarkUpTo) {
        await widget.onMarkEpisodeUpTo(episode, now);
      } else {
        await widget.onToggleEpisode(episode, true, now);
      }
      return;
    }
    await widget.onToggleEpisode(episode, true, null);
  }

  Future<bool?> _showMarkPreviousEpisodesDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: const Text('Épisodes précédents manquants'),
        content: const Text(
          'Des épisodes précédents ne sont pas cochés. Voulez-vous aussi les cocher ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seulement celui-ci'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showMarkPreviousSeasonsDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: const Text('Saisons précédentes manquantes'),
        content: const Text(
          'Des épisodes de saisons précédentes ne sont pas cochés. Voulez-vous aussi les cocher ?',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seulement cette saison'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text("Cocher jusqu'ici"),
          ),
        ],
      ),
    );
  }

  String _seasonTitle() => _isSpecialSeason
      ? 'Épisodes spéciaux'
      : 'Saison ${widget.season.seasonNumber}';

  Future<void> _onSeasonCheckRequest(bool target) async {
    if (!target && !_isSpecialSeason && _isSeasonFullyWatched()) {
      final hasRewatches = _seasonHasRewatches();
      final choice = await _showRewatchSeasonDialog(hasRewatches);
      if (choice == null) return;
      if (choice == RewatchChoice.rewatch) {
        await widget.onRewatchSeason(widget.season);
      } else if (hasRewatches) {
        final confirmed = await _showDeleteSeasonRewatchConfirmation();
        if (confirmed != true) return;
        await widget.onDeleteSeasonLatestRewatches(widget.season);
      } else {
        await widget.onMarkSeasonWatched(widget.season, false);
      }
      return;
    }
    if (!target || _isSpecialSeason) {
      await widget.onMarkSeasonWatched(widget.season, target);
      return;
    }
    final watchedPositions =
        widget.watchedEpisodes
            .map(_parseEpisodePositionKey)
            .whereType<int>()
            .toList()
          ..sort();
    final firstEpisodePosition = _episodePositionKey(
      widget.season.seasonNumber,
      1,
    );
    final watchedBefore = _countWatchedBeforePosition(
      watchedPositions,
      firstEpisodePosition,
    );
    final expectedBefore = widget.seasonOffset;
    if (watchedBefore < expectedBefore) {
      final includePrevious = await _showMarkPreviousSeasonsDialog();
      if (includePrevious == null) return;
      if (includePrevious) {
        await widget.onMarkSeasonWatched(widget.season, true);
      } else {
        await widget.onMarkOnlySeasonWatched(widget.season, true);
      }
      return;
    }
    await widget.onMarkSeasonWatched(widget.season, true);
  }

  bool _isSeasonFullyWatched() {
    if (_episodes.isNotEmpty) {
      return _episodes.every(_isWatched);
    }
    if (widget.season.episodeCount <= 0) return false;
    var watched = 0;
    for (final key in widget.watchedEpisodes) {
      if (key.startsWith('${widget.season.seasonNumber}_')) {
        watched++;
      }
    }
    return watched >= widget.season.episodeCount;
  }

  int? _seasonReviewCount(int totalCount) {
    if (!_isSeasonFullyWatched() || totalCount <= 0) return null;
    int? minCount;
    if (_episodes.isNotEmpty) {
      for (final episode in _episodes) {
        final episodeCount = _episodeViewCount(episode);
        if (minCount == null || episodeCount < minCount) {
          minCount = episodeCount;
        }
      }
    } else {
      for (var i = 1; i <= totalCount; i++) {
        final key = '${widget.season.seasonNumber}_$i';
        final episodeCount = widget.episodeViewCounts[key] ?? 1;
        if (minCount == null || episodeCount < minCount) {
          minCount = episodeCount;
        }
      }
    }
    if (minCount == null || minCount <= 1) return null;
    return minCount;
  }

  bool _seasonHasRewatches() {
    if (_episodes.isNotEmpty) {
      return _episodes.every((episode) => _episodeViewCount(episode) > 1);
    }
    if (widget.season.episodeCount <= 0) return false;
    for (var i = 1; i <= widget.season.episodeCount; i++) {
      if ((widget.episodeViewCounts['${widget.season.seasonNumber}_$i'] ?? 0) <=
          1) {
        return false;
      }
    }
    return true;
  }

  Future<bool?> _showDeleteSeasonRewatchConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: const Text('Supprimer les derniers rewatches'),
        content: const Text(
          'Cela supprimera le rewatch le plus récent de chaque épisode de cette saison qui en possède au moins un. Continuer ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  Future<RewatchChoice?> _showRewatchEpisodeDialog(List<int> dates) {
    return showDialog<RewatchChoice>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: const Text('Épisode déjà vu'),
        content: const Text(
          'Voulez-vous le marquer non vu ou ajouter une revue (+1 vue) ?',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(RewatchChoice.unwatch),
            child: Text(
              dates.length > 1 ? 'Supprimer un visionnage' : 'Marquer non vu',
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(RewatchChoice.rewatch),
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: const Text('Revoir (+1 vue)'),
          ),
        ],
      ),
    );
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

  Future<RewatchChoice?> _showRewatchSeasonDialog(bool hasRewatches) {
    return showDialog<RewatchChoice>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: const Text('Saison déjà vue'),
        content: const Text(
          'Voulez-vous marquer cette saison non vue ou ajouter une revue à tous ses épisodes ?',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(RewatchChoice.unwatch),
            child: Text(
              hasRewatches
                  ? 'Supprimer les derniers rewatches'
                  : 'Marquer non vu',
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(RewatchChoice.rewatch),
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: const Text('Revoir la saison (+1 vue)'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasEpisodes = widget.season.episodeCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.38),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                Icons.playlist_remove_rounded,
                size: 34,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                hasEpisodes
                    ? (_episodesLoadFailed
                          ? 'Épisodes indisponibles hors-ligne'
                          : 'Aucun épisode chargé')
                    : 'Saison vide',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                hasEpisodes
                    ? (_episodesLoadFailed
                          ? 'Aucune donnée en cache n\'a été trouvée pour cette saison.'
                          : 'Les épisodes n’ont pas encore été chargés.')
                    : 'Cette saison ne contient pas d’épisodes.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (hasEpisodes) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _loadEpisodesIfNeeded,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Réessayer'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _episodeNumbers(Episode episode) {
    final globalNumber = widget.seasonOffset + episode.episodeNumber;
    return 'S${episode.seasonNumber.toString().padLeft(2, '0')} | E${episode.episodeNumber.toString().padLeft(2, '0')} (E${globalNumber.toString().padLeft(2, '0')})';
  }

  bool _isFutureEpisodeRelease(Episode episode) {
    final raw = episode.airDate;
    if (raw == null || raw.isEmpty) return true;
    final date = DateTime.tryParse(raw);
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final airDay = DateTime(date.year, date.month, date.day);
    return airDay.isAfter(today);
  }

  @override
  Widget build(BuildContext context) {
    final watchedCount = widget.watchedEpisodes
        .where((k) => k.startsWith('${widget.season.seasonNumber}_'))
        .length;
    final totalCount = widget.season.episodeCount;
    final allWatched = totalCount > 0 && watchedCount >= totalCount;
    final seasonReviewCount = _seasonReviewCount(totalCount);
    final showProgress = watchedCount > 0 && totalCount > 0;
    final progress = totalCount > 0 ? watchedCount / totalCount : 0.0;
    final progressColor = allWatched
        ? const Color(0xFF4CAF50)
        : const Color(0xFFFFC107);
    final progressTrackColor = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.8);

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.45),
          child: InkWell(
            onTap: () {
              setState(() {
                _expanded = !_expanded;
              });
              if (_expanded) {
                _loadEpisodesIfNeeded();
              }
            },
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              _seasonTitle(),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              _expanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                            ),
                          ],
                        ),
                      ),
                      if (totalCount > 0) ...[
                        Text(
                          '$watchedCount/$totalCount',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                      ],
                      WatchedToggleButton(
                        key: ValueKey(
                          'season-toggle-${widget.season.seasonNumber}',
                        ),
                        checked: allWatched,
                        reviewCount: seasonReviewCount,
                        size: 36,
                        tooltip: allWatched
                            ? 'Marquer la saison non vue'
                            : 'Marquer la saison vue',
                        onTap: () => _onSeasonCheckRequest(!allWatched),
                      ),
                    ],
                  ),
                ),
                if (showProgress)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        key: ValueKey(
                          'season-progress-${widget.season.seasonNumber}',
                        ),
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 8,
                        color: progressColor,
                        backgroundColor: progressTrackColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_expanded)
          _loadingEpisodes
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _episodes.isEmpty
              ? _buildEmptyState()
              : SizedBox(
                  height: (_episodes.length * 96.0).clamp(0.0, 520.0),
                  child: NotificationListener<OverscrollNotification>(
                    onNotification: (notification) {
                      if (!_episodesScrollCtrl.hasClients ||
                          !widget.parentScrollController.hasClients) {
                        return false;
                      }
                      final inner = _episodesScrollCtrl.position;
                      final parent = widget.parentScrollController.position;
                      final isAtInnerBottom =
                          inner.pixels >= inner.maxScrollExtent;
                      final isAtInnerTop =
                          inner.pixels <= inner.minScrollExtent;
                      if ((notification.overscroll > 0 && isAtInnerBottom) ||
                          (notification.overscroll < 0 && isAtInnerTop)) {
                        final target = (parent.pixels + notification.overscroll)
                            .clamp(0.0, parent.maxScrollExtent)
                            .toDouble();
                        if ((target - parent.pixels).abs() > 0.5) {
                          widget.parentScrollController.jumpTo(target);
                        }
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _episodesScrollCtrl,
                      padding: EdgeInsets.zero,
                      itemCount: _episodes.length,
                      itemBuilder: (context, index) {
                        final ep = _episodes[index];
                        final watched = _isWatched(ep);
                        final showReleaseStatus =
                            !_isWatched(ep) &&
                            (_isFutureEpisodeRelease(ep) || ep.airDate == null);
                        return Padding(
                          key: _episodeTileKey(ep),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Card(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.35),
                            child: ListTile(
                              onTap: () => widget.onOpenEpisode(ep),
                              leading: SizedBox(
                                width: 72,
                                height: 72,
                                child: ep.stillPath == null
                                    ? const Icon(
                                        Icons.image_not_supported_rounded,
                                      )
                                    : CachedNetworkImage(
                                        imageUrl: ep.stillPath!,
                                        fit: BoxFit.cover,
                                        placeholder: (_, _) => Center(
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                          ),
                                        ),
                                        errorWidget: (_, _, _) => const Icon(
                                          Icons.image_not_supported_rounded,
                                        ),
                                      ),
                              ),
                              title: _isSpecialSeason
                                  ? Text(
                                      ep.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : Text(
                                      _episodeNumbers(ep),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                              subtitle: _isSpecialSeason
                                  ? null
                                  : Text(
                                      ep.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              trailing: showReleaseStatus
                                  ? _EpisodeReleaseStatus(airDate: ep.airDate)
                                  : WatchedToggleButton(
                                      key: ValueKey(
                                        'episode-toggle-${ep.seasonNumber}_${ep.episodeNumber}',
                                      ),
                                      checked: watched,
                                      reviewCount: _episodeReviewCount(ep),
                                      size: 32,
                                      tooltip: watched
                                          ? 'Marquer l\'épisode non vu'
                                          : 'Marquer l\'épisode vu',
                                      onTap: () =>
                                          _onEpisodeCheckRequest(ep, !watched),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        const Divider(height: 1),
      ],
    );
  }
}

class _EpisodeReleaseStatus extends StatelessWidget {
  const _EpisodeReleaseStatus({required this.airDate});

  final String? airDate;

  @override
  Widget build(BuildContext context) {
    final raw = airDate;
    if (raw == null || raw.isEmpty) {
      return const Text(
        'A venir',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold),
      );
    }
    final date = DateTime.tryParse(raw);
    if (date == null) {
      return const Text(
        'A venir',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold),
      );
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final episodeDay = DateTime(date.year, date.month, date.day);
    final days = episodeDay.difference(today).inDays;
    final value = days <= 0 ? '0' : '$days';
    final unit = days == 1 ? 'jour' : 'jours';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        Text(unit, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
