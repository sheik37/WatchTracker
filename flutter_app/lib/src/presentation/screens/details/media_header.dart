import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../data/models/details_models.dart';
import '../../../data/models/media_models.dart';

/// Backdrop/title header shown behind the collapsing app bar of the details
/// screen. Fades its title/overview content in and out as the surrounding
/// [SliverPersistentHeader] collapses.
class MediaHeader extends StatelessWidget {
  const MediaHeader({
    super.key,
    required this.details,
    required this.contentAlpha,
    this.progressColor,
    this.progressValue,
    this.watchedGlobal,
    this.totalGlobal,
  });

  final MediaDetails details;
  final double contentAlpha;
  final Color? progressColor;
  final double? progressValue;
  final int? watchedGlobal;
  final int? totalGlobal;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (details.backdropPath != null || details.posterPath != null)
          CachedNetworkImage(
            imageUrl: details.backdropPath ?? details.posterPath!,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => Container(color: Colors.black54),
          )
        else
          Container(color: Colors.black87),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xB3000000)],
              stops: [0.4, 1.0],
            ),
          ),
        ),
        Positioned(
          bottom: progressColor != null ? 10 : 0,
          left: 16,
          right: 16,
          child: Opacity(
            opacity: contentAlpha,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  details.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (details.mediaType == MediaType.tv) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${details.seasons.where((s) => s.seasonNumber != 0).length} saison(s)',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      if (details.tvStatus != null) ...[
                        const Text(
                          ' • ',
                          style: TextStyle(color: Colors.white70, fontSize: 18),
                        ),
                        Text(
                          details.tvStatus!.label,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      if (watchedGlobal != null &&
                          totalGlobal != null &&
                          totalGlobal! > 0) ...[
                        const Text(
                          ' • ',
                          style: TextStyle(color: Colors.white70, fontSize: 18),
                        ),
                        Text(
                          '$watchedGlobal / $totalGlobal épisodes vus',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (progressColor != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 6,
              color: progressColor,
              backgroundColor: Colors.black.withValues(alpha: 0.35),
            ),
          ),
      ],
    );
  }
}

extension on TvStatus {
  String get label => switch (this) {
    TvStatus.returningSeries => 'Série en cours',
    TvStatus.ended => 'Terminée',
    TvStatus.canceled => 'Annulée',
    TvStatus.planned => 'Prévue',
    TvStatus.inProduction => 'En production',
  };
}
