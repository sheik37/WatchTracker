import 'package:flutter/material.dart';

import '../../data/models/media_models.dart';
import '../../data/repositories/media_repository.dart';
import '../theme/slide_up_route.dart';
import '../widgets/media_card.dart';
import 'details_screen.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({
    super.key,
    required this.repository,
    required this.category,
  });

  final MediaRepository repository;
  final WatchCategory category;

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  late Future<_WatchlistSections> _future;
  final Map<WatchStatus, bool> _expanded = {};
  bool _staleExpanded = true;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.repository.watchlistVersion.addListener(_onWatchlistChanged);
    for (final s in WatchStatus.values) {
      _expanded[s] = true;
    }
  }

  @override
  void dispose() {
    widget.repository.watchlistVersion.removeListener(_onWatchlistChanged);
    super.dispose();
  }

  void _onWatchlistChanged() {
    if (!mounted) return;
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _loadSections();
    });
  }

  Future<_WatchlistSections> _loadSections() async {
    final items = await widget.repository.getWatchlist(widget.category);
    return _WatchlistSections.fromItems(widget.category, items);
  }

  @override
  Widget build(BuildContext context) {
    final statuses = _statusesForCategory(widget.category);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.category.label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: FutureBuilder<_WatchlistSections>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final sections = snapshot.data ?? _WatchlistSections.empty();

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                if (widget.category != WatchCategory.films) ...[
                  _SectionHeader(
                    title: 'Pas regardé depuis un moment',
                    expanded: _staleExpanded,
                    onToggle: () =>
                        setState(() => _staleExpanded = !_staleExpanded),
                  ),
                  if (_staleExpanded)
                    sections.staleItems.isEmpty
                        ? _emptySection()
                        : _SectionGrid(
                            items: sections.staleItems,
                            onTap: _openDetails,
                          ),
                ],
                for (final status in statuses) ...[
                  _SectionHeader(
                    title: status.label,
                    expanded: _expanded[status] ?? true,
                    onToggle: () => setState(
                      () => _expanded[status] = !(_expanded[status] ?? true),
                    ),
                  ),
                  if (_expanded[status] ?? true)
                    ((sections.byStatus[status] ?? const <WatchlistItem>[])
                            .isEmpty)
                        ? _emptySection()
                        : _SectionGrid(
                            items: sections.byStatus[status]!,
                            onTap: _openDetails,
                          ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _emptySection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: Text(
          'Aucun titre dans cette sous-liste',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Future<void> _openDetails(WatchlistItem item) async {
    await Navigator.of(context).push(
      SlideUpRoute<void>(
        builder: (_) =>
            DetailsScreen(repository: widget.repository, media: item.media),
      ),
    );
    _reload();
  }

  List<WatchStatus> _statusesForCategory(WatchCategory category) {
    return switch (category) {
      WatchCategory.films => const [
        WatchStatus.notWatched,
        WatchStatus.watched,
      ],
      _ => const [
        WatchStatus.notStarted,
        WatchStatus.inProgress,
        WatchStatus.upToDate,
        WatchStatus.completed,
      ],
    };
  }
}

class _WatchlistSections {
  const _WatchlistSections({required this.staleItems, required this.byStatus});

  final List<WatchlistItem> staleItems;
  final Map<WatchStatus, List<WatchlistItem>> byStatus;

  factory _WatchlistSections.empty() =>
      const _WatchlistSections(staleItems: [], byStatus: {});

  factory _WatchlistSections.fromItems(
    WatchCategory category,
    List<WatchlistItem> items,
  ) {
    final staleItems = <WatchlistItem>[];
    final byStatus = <WatchStatus, List<WatchlistItem>>{};
    final staleCutoffMillis = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;

    for (final item in items) {
      final watchedAt = item.lastWatchedAt;
      final isStale =
          category != WatchCategory.films &&
          watchedAt != null &&
          item.watchedEpisodes > 0 &&
          watchedAt < staleCutoffMillis;
      if (isStale) {
        staleItems.add(item);
        continue;
      }
      (byStatus[item.status] ??= <WatchlistItem>[]).add(item);
    }

    return _WatchlistSections(staleItems: staleItems, byStatus: byStatus);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.expanded,
    required this.onToggle,
  });

  final String title;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionGrid extends StatelessWidget {
  const _SectionGrid({required this.items, required this.onTap});

  final List<WatchlistItem> items;
  final Future<void> Function(WatchlistItem) onTap;

  @override
  Widget build(BuildContext context) {
    final rows = <List<WatchlistItem>>[];
    for (var i = 0; i < items.length; i += 3) {
      rows.add(items.sublist(i, i + 3 > items.length ? items.length : i + 3));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...row.map(
                  (item) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _WatchlistCard(item: item, onTap: onTap),
                    ),
                  ),
                ),
                if (row.length < 3)
                  ...List.generate(
                    3 - row.length,
                    (_) => const Expanded(child: SizedBox()),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _WatchlistCard extends StatelessWidget {
  const _WatchlistCard({required this.item, required this.onTap});

  final WatchlistItem item;
  final Future<void> Function(WatchlistItem) onTap;

  Color? _progressColor() {
    return switch (item.status) {
      WatchStatus.inProgress => const Color(0xFFFFC107),
      WatchStatus.upToDate => const Color(0xFF4CAF50),
      WatchStatus.completed => const Color(0xFF9C27B0),
      WatchStatus.watched => const Color(0xFF9C27B0),
      _ => null,
    };
  }

  double _progress() {
    if (item.status == WatchStatus.inProgress) {
      if (item.totalEpisodes <= 0) return 0;
      return (item.watchedEpisodes / item.totalEpisodes).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final progressColor = _progressColor();
    final showProgress =
        item.media.mediaType != MediaType.movie &&
        item.status != WatchStatus.notStarted &&
        item.status != WatchStatus.notWatched &&
        progressColor != null;

    return MediaCard(
      posterPath: item.media.posterPath,
      title: item.media.title,
      onTap: () => onTap(item),
      bottomContent: showProgress
          ? Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _progress(),
                minHeight: 6,
                color: progressColor,
                backgroundColor: Colors.black.withValues(alpha: 0.35),
              ),
            )
          : null,
    );
  }
}
