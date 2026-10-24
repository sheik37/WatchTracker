import 'package:flutter/material.dart';

/// "Modifier le mot de passe" sub-screen of the profile screen.
class ChangePasswordBody extends StatefulWidget {
  const ChangePasswordBody({
    super.key,
    required this.currentController,
    required this.newController,
    required this.confirmController,
    required this.loading,
    required this.error,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController currentController;
  final TextEditingController newController;
  final TextEditingController confirmController;
  final bool loading;
  final String? error;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;

  @override
  State<ChangePasswordBody> createState() => _ChangePasswordBodyState();
}

class _ChangePasswordBodyState extends State<ChangePasswordBody> {
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        widget.currentController.text.isNotEmpty &&
        widget.newController.text.isNotEmpty &&
        widget.confirmController.text.isNotEmpty &&
        !widget.loading;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: widget.currentController,
          obscureText: !_showCurrentPassword,
          enabled: !widget.loading,
          onChanged: (_) => widget.onChanged(),
          decoration: InputDecoration(
            labelText: 'Mot de passe actuel',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _showCurrentPassword = !_showCurrentPassword),
              icon: Icon(
                _showCurrentPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              tooltip: _showCurrentPassword
                  ? 'Masquer le mot de passe'
                  : 'Afficher le mot de passe',
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.newController,
          obscureText: !_showNewPassword,
          enabled: !widget.loading,
          onChanged: (_) => widget.onChanged(),
          decoration: InputDecoration(
            labelText: 'Nouveau mot de passe',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _showNewPassword = !_showNewPassword),
              icon: Icon(
                _showNewPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              tooltip: _showNewPassword
                  ? 'Masquer le mot de passe'
                  : 'Afficher le mot de passe',
            ),
          ),
        ),
        _PasswordCriteriaChecklist(password: widget.newController.text),
        const SizedBox(height: 12),
        TextField(
          controller: widget.confirmController,
          obscureText: !_showConfirmPassword,
          enabled: !widget.loading,
          onChanged: (_) => widget.onChanged(),
          decoration: InputDecoration(
            labelText: 'Confirmer le mot de passe',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _showConfirmPassword = !_showConfirmPassword),
              icon: Icon(
                _showConfirmPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              tooltip: _showConfirmPassword
                  ? 'Masquer le mot de passe'
                  : 'Afficher le mot de passe',
            ),
          ),
        ),
        _PasswordCriteriaChecklist(password: widget.confirmController.text),
        if (widget.error != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: canSubmit ? widget.onSubmit : null,
            child: Text(
              widget.loading ? 'Modification...' : 'Modifier le mot de passe',
            ),
          ),
        ),
      ],
    );
  }
}

class _PasswordCriteriaChecklist extends StatelessWidget {
  const _PasswordCriteriaChecklist({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final checks = <(String, bool)>[
      ('10 caractères minimum', password.length >= 10),
      ('au moins une minuscule', password.contains(RegExp(r'[a-z]'))),
      ('au moins une majuscule', password.contains(RegExp(r'[A-Z]'))),
      ('au moins un chiffre', password.contains(RegExp(r'[0-9]'))),
      ('au moins un symbole', password.contains(RegExp(r'[^A-Za-z0-9]'))),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: checks.map((entry) {
          final (label, isValid) = entry;
          return Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${isValid ? "• ✓ " : "• ✗ "}$label',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isValid
                    ? const Color(0xFF2E7D32)
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
