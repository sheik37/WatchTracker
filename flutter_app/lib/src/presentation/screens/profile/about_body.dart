import 'package:flutter/material.dart';

import '../../../core/app_update_launcher.dart';
import '../../../core/app_update_service.dart';

/// "À propos" sub-screen of the profile screen: app version plus
/// update-check UI (uses [AppUpdateResult]/[AppUpdateLauncher]).
class AboutBody extends StatelessWidget {
  const AboutBody({
    super.key,
    required this.version,
    required this.checkingForUpdates,
    required this.appUpdateError,
    required this.appUpdateResult,
    required this.onCheckForUpdates,
    required this.onOpenUpdateDownload,
    required this.onOpenReleaseNotes,
  });

  final String version;
  final bool checkingForUpdates;
  final String? appUpdateError;
  final AppUpdateResult? appUpdateResult;
  final Future<void> Function() onCheckForUpdates;
  final Future<void> Function() onOpenUpdateDownload;
  final Future<void> Function() onOpenReleaseNotes;

  @override
  Widget build(BuildContext context) {
    final releaseNotes = appUpdateResult?.releaseNotes?.trim();
    final releaseNotesUrl = releaseNotes == null || releaseNotes.isEmpty
        ? null
        : AppUpdateLauncher.extractFirstHttpUrl(releaseNotes);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 16),
        Center(
          child: Image.asset(
            'assets/images/watchtracker_logo.png',
            width: 120,
            height: 120,
            errorBuilder: (_, _, _) => const Icon(
              Icons.movie_filter_rounded,
              size: 120,
              color: Color(0xFF006A6A),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Version', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(version),
                const Divider(height: 24),
                Text(
                  'Mises à jour',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  appUpdateResult == null
                      ? 'Appuie sur "Vérifier les mises à jour" pour récupérer la dernière version.'
                      : 'Version installée : ${appUpdateResult!.currentLabel}',
                ),
                if (appUpdateResult != null) ...[
                  const SizedBox(height: 4),
                  Text('Dernière version : ${appUpdateResult!.latestLabel}'),
                ],
                if (releaseNotes != null && releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  if (releaseNotesUrl != null)
                    TextButton(
                      onPressed: () {
                        onOpenReleaseNotes();
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Voir la note'),
                    )
                  else
                    Text(releaseNotes),
                ],
                if (appUpdateError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    appUpdateError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: checkingForUpdates
                      ? null
                      : () {
                          onCheckForUpdates();
                        },
                  child: Text(
                    checkingForUpdates
                        ? 'Vérification...'
                        : 'Vérifier les mises à jour',
                  ),
                ),
                if (appUpdateResult?.isUpdateAvailable == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton(
                      onPressed: () {
                        onOpenUpdateDownload();
                      },
                      child: const Text('Télécharger la mise à jour'),
                    ),
                  ),
                if (appUpdateResult != null &&
                    appUpdateResult!.isUpdateAvailable == false) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Tu as déjà la dernière version.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
