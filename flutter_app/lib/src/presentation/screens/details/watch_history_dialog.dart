// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../../../core/date_formatter.dart';

/// Shows the "Historique de visionnage" dialog listing the first/last watch
/// dates plus any rewatch dates (each deletable with confirmation).
///
/// Used both for a movie's watch history and for a single episode's watch
/// history; [onDeleteDate] is invoked with the timestamp to delete after the
/// user confirms.
///
/// [closeDialogBeforeDelete] controls whether the outer dialog is popped
/// before or after [onDeleteDate] completes, matching the pre-extraction
/// behavior of each call site (movie flow closes first, episode flow closes
/// after refreshing state).
Future<void> showWatchHistoryDialog({
  required BuildContext context,
  required List<int> dates,
  required Future<void> Function(int watchedAtMillis) onDeleteDate,
  bool closeDialogBeforeDelete = false,
}) {
  if (dates.isEmpty) return Future<void>.value();

  final sortedDates = List<int>.from(dates)..sort();
  final firstDate = DateTime.fromMillisecondsSinceEpoch(sortedDates.first);
  final lastDate = DateTime.fromMillisecondsSinceEpoch(sortedDates.last);
  final rewatches = sortedDates.length > 1
      ? sortedDates.sublist(1).reversed.toList()
      : <int>[];

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHigh,
      title: const Text('Historique de visionnage'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Premier visionnage : ${formatWatchDateLabel(firstDate.millisecondsSinceEpoch)}',
            ),
            if (sortedDates.length > 1) ...[
              const SizedBox(height: 6),
              Text(
                'Dernier visionnage : ${formatWatchDateLabel(lastDate.millisecondsSinceEpoch)}',
              ),
            ],
            if (rewatches.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Revues (${rewatches.length}):',
                style: Theme.of(ctx).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              ...rewatches.map((ms) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text('• ${formatWatchDateLabel(ms)}')),
                      IconButton(
                        tooltip: 'Supprimer ce visionnage',
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: ctx,
                            builder: (confirmCtx) => AlertDialog(
                              backgroundColor: Theme.of(confirmCtx)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              title: const Text('Confirmer la suppression'),
                              content: Text(
                                'Supprimer le visionnage du ${formatWatchDateLabel(ms)} ?',
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
                                  icon: const Icon(
                                    Icons.delete_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Supprimer'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                          if (closeDialogBeforeDelete) {
                            if (Navigator.of(ctx).canPop()) {
                              Navigator.of(ctx).pop();
                            }
                            await onDeleteDate(ms);
                          } else {
                            await onDeleteDate(ms);
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
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
