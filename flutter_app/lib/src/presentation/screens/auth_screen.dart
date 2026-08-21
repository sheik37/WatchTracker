import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.appVersionLabel,
    required this.isLoading,
    required this.onLogin,
    required this.onRegister,
    required this.onForgotPassword,
    required this.onResendVerification,
    this.errorMessage,
    this.infoMessage,
    this.retryAfterSeconds,
    this.attemptsRemaining,
    this.showResendVerification = false,
    this.showOtpCodeField = false,
    this.admin2faEmail,
    this.resendCooldownSeconds,
    this.forgotCooldownSeconds,
    this.onModeChanged,
  });

  final bool isLoading;
  final String appVersionLabel;
  final String? errorMessage;
  final String? infoMessage;
  final int? retryAfterSeconds;
  final int? attemptsRemaining;
  final bool showResendVerification;
  final bool showOtpCodeField;
  final String? admin2faEmail;
  final int? resendCooldownSeconds;
  final int? forgotCooldownSeconds;
  final Future<void> Function(String email, String password, String? otpCode)
  onLogin;
  final Future<void> Function(String email, String password) onRegister;
  final Future<void> Function(String email) onForgotPassword;
  final Future<void> Function(String email) onResendVerification;
  final VoidCallback? onModeChanged;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _isRegisterMode = false;
  bool _showPassword = false;

  bool get _hasMinLength => _passwordCtrl.text.length >= 10;
  bool get _hasLower => _passwordCtrl.text
      .split('')
      .any((c) => c.toLowerCase() != c.toUpperCase() && c == c.toLowerCase());
  bool get _hasUpper => _passwordCtrl.text
      .split('')
      .any((c) => c.toLowerCase() != c.toUpperCase() && c == c.toUpperCase());
  bool get _hasDigit =>
      _passwordCtrl.text.split('').any((c) => '0123456789'.contains(c));
  bool get _hasSymbol => _passwordCtrl.text
      .split('')
      .any((c) => !RegExp(r'[A-Za-z0-9]').hasMatch(c));
  bool get _passwordValid =>
      _hasMinLength && _hasLower && _hasUpper && _hasDigit && _hasSymbol;

  bool get _isAdminTarget =>
      widget.admin2faEmail != null &&
      _emailCtrl.text.trim().toLowerCase() ==
          widget.admin2faEmail!.toLowerCase();

  bool get _shouldShowOtp =>
      !_isRegisterMode && (widget.showOtpCodeField || _isAdminTarget);

  bool get _isRateLimited => (widget.retryAfterSeconds ?? 0) > 0;

  bool get _canSubmit {
    if (widget.isLoading || _isRateLimited) return false;
    if (!_emailCtrl.text.contains('@')) return false;
    if (_isRegisterMode) return _passwordValid;
    if (_passwordCtrl.text.isEmpty) return false;
    if (_shouldShowOtp && _otpCtrl.text.length < 6) return false;
    return true;
  }

  bool get _canResend =>
      widget.showResendVerification &&
      _emailCtrl.text.contains('@') &&
      !widget.isLoading &&
      !_isRateLimited &&
      (widget.resendCooldownSeconds ?? 0) <= 0;

  bool get _canForgot =>
      !_isRegisterMode &&
      _emailCtrl.text.contains('@') &&
      !widget.isLoading &&
      !_isRateLimited &&
      (widget.forgotCooldownSeconds ?? 0) <= 0;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    try {
      if (_isRegisterMode) {
        await widget.onRegister(email, password);
      } else {
        await widget.onLogin(
          email,
          password,
          _shouldShowOtp ? _otpCtrl.text.trim() : null,
        );
      }
    } catch (_) {
      // errors are handled by parent via errorMessage prop
    }
  }

  @override
  Widget build(BuildContext context) {
    final resendCooldown = widget.resendCooldownSeconds ?? 0;
    final forgotCooldown = widget.forgotCooldownSeconds ?? 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 48),
                    Image.asset(
                      'assets/images/watchtracker_logo.png',
                      width: 110,
                      height: 110,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.movie_filter_rounded,
                        size: 110,
                        color: Color(0xFF006A6A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'WatchTracker',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isRegisterMode ? 'Inscription' : 'Connexion',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isRegisterMode
                          ? 'Crée un compte personnel pour ta propre liste.'
                          : 'Connecte-toi pour charger ta liste personnelle.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _isRegisterMode
                              ? OutlinedButton(
                                  onPressed: widget.isLoading
                                      ? null
                                      : () {
                                          setState(
                                            () => _isRegisterMode = false,
                                          );
                                          widget.onModeChanged?.call();
                                        },
                                  child: const Text('Connexion'),
                                )
                              : FilledButton(
                                  onPressed: null,
                                  child: const Text('Connexion'),
                                ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _isRegisterMode
                              ? FilledButton(
                                  onPressed: null,
                                  child: const Text('Inscription'),
                                )
                              : OutlinedButton(
                                  onPressed: widget.isLoading
                                      ? null
                                      : () {
                                          setState(
                                            () => _isRegisterMode = true,
                                          );
                                          widget.onModeChanged?.call();
                                        },
                                  child: const Text('Inscription'),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _OutlinedTextField(
                      controller: _emailCtrl,
                      label: 'Adresse mail',
                      keyboardType: TextInputType.emailAddress,
                      enabled: !widget.isLoading,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    _OutlinedTextField(
                      controller: _passwordCtrl,
                      label: _isRegisterMode
                          ? 'Mot de passe (10+, min/maj/chiffre/symbole)'
                          : 'Mot de passe',
                      obscureText: !_showPassword,
                      enabled: !widget.isLoading,
                      onChanged: (_) => setState(() {}),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        tooltip: _showPassword
                            ? 'Masquer le mot de passe'
                            : 'Afficher le mot de passe',
                      ),
                    ),
                    if (_shouldShowOtp) ...[
                      const SizedBox(height: 12),
                      _OutlinedTextField(
                        controller: _otpCtrl,
                        label: 'Code 2FA (admin)',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                        ],
                        enabled: !widget.isLoading,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                    if (_isRegisterMode) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: _PasswordCriteria(
                          checks: [
                            ('10 caractères minimum', _hasMinLength),
                            ('au moins une minuscule', _hasLower),
                            ('au moins une majuscule', _hasUpper),
                            ('au moins un chiffre', _hasDigit),
                            ('au moins un symbole', _hasSymbol),
                          ],
                        ),
                      ),
                    ],
                    if (widget.errorMessage != null &&
                        widget.errorMessage!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    if (widget.infoMessage != null &&
                        widget.infoMessage!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.infoMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                    if (_isRateLimited) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Trop de tentatives. Réessaie dans ${widget.retryAfterSeconds}s.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ] else if (widget.attemptsRemaining != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Tentatives restantes avant blocage : ${widget.attemptsRemaining}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _canSubmit ? _submit : null,
                        child: widget.isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _isRegisterMode
                                    ? 'Créer un compte'
                                    : 'Se connecter',
                              ),
                      ),
                    ),
                    if (!_isRegisterMode) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _canForgot
                              ? () => widget.onForgotPassword(
                                  _emailCtrl.text.trim(),
                                )
                              : null,
                          child: Text(
                            forgotCooldown > 0
                                ? 'Mot de passe oublié (${forgotCooldown}s)'
                                : 'Mot de passe oublié',
                          ),
                        ),
                      ),
                    ],
                    if (_isRegisterMode && widget.showResendVerification) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _canResend
                              ? () => widget.onResendVerification(
                                  _emailCtrl.text.trim(),
                                )
                              : null,
                          child: Text(
                            resendCooldown > 0
                                ? 'Renvoyer l\'email (${resendCooldown}s)'
                                : 'Renvoyer l\'email de vérification',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text(
                'Version ${widget.appVersionLabel}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlinedTextField extends StatelessWidget {
  const _OutlinedTextField({
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.inputFormatters,
    this.enabled = true,
    this.onChanged,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      enabled: enabled,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class _PasswordCriteria extends StatelessWidget {
  const _PasswordCriteria({required this.checks});

  final List<(String, bool)> checks;

  @override
  Widget build(BuildContext context) {
    return Column(
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
    );
  }
}
