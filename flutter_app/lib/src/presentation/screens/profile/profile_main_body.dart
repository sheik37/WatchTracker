import 'package:flutter/material.dart';

/// Read-only default body of the profile screen: a summary card with the
/// user's display name, email, and session state.
class ProfileMainBody extends StatelessWidget {
  const ProfileMainBody({
    super.key,
    required this.displayName,
    required this.email,
    required this.backendUrl,
  });

  final String displayName;
  final String email;
  final String backendUrl;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Informations du compte',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Nom d\'utilisateur : $displayName'),
                Text('Adresse e-mail : $email'),
                const Text('Session : connectée'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
