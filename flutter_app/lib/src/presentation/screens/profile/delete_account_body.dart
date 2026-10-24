import 'package:flutter/material.dart';

/// "Supprimer le compte" confirmation sub-screen of the profile screen.
class DeleteAccountBody extends StatelessWidget {
  const DeleteAccountBody({
    super.key,
    required this.loading,
    required this.error,
    required this.onDelete,
  });

  final bool loading;
  final String? error;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'La suppression du compte est définitive. Toutes vos données liées à ce compte (profil, suivi de contenus, progression des épisodes et sessions actives) seront supprimées de manière irréversible.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Conformément aux obligations réglementaires, certaines traces techniques strictement nécessaires à la sécurité et à la conformité peuvent être conservées pour une durée limitée.',
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: loading ? null : onDelete,
              child: Text(loading ? 'Suppression...' : 'Supprimer mon compte'),
            ),
          ),
        ],
      ),
    );
  }
}
