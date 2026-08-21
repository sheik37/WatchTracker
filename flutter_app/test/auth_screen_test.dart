import 'package:flutter/material.dart';
import 'package:flutter_app/src/presentation/screens/auth_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildScreen({
    bool isLoading = false,
    int? retryUntilMillis,
    int? attemptsRemaining,
    int? resendUntilMillis,
    int? forgotUntilMillis,
    bool showResendVerification = false,
    bool showOtpCodeField = false,
    String? admin2faEmail,
    String? errorMessage,
    String? infoMessage,
    Future<void> Function(String email, String password, String? otpCode)?
    onLogin,
    Future<void> Function(String email, String password)? onRegister,
    Future<void> Function(String email)? onForgotPassword,
    Future<void> Function(String email)? onResendVerification,
    VoidCallback? onModeChanged,
  }) {
    return MaterialApp(
      home: AuthScreen(
        appVersionLabel: '2.0.8+42',
        isLoading: isLoading,
        retryUntilMillis: retryUntilMillis,
        attemptsRemaining: attemptsRemaining,
        resendUntilMillis: resendUntilMillis,
        forgotUntilMillis: forgotUntilMillis,
        showResendVerification: showResendVerification,
        showOtpCodeField: showOtpCodeField,
        admin2faEmail: admin2faEmail,
        errorMessage: errorMessage,
        infoMessage: infoMessage,
        onLogin: onLogin ?? (_, _, _) async {},
        onRegister: onRegister ?? (_, _) async {},
        onForgotPassword: onForgotPassword ?? (_) async {},
        onResendVerification: onResendVerification ?? (_) async {},
        onModeChanged: onModeChanged,
      ),
    );
  }

  testWidgets('toggles password visibility from the eye icon', (tester) async {
    await tester.pumpWidget(buildScreen());

    TextField passwordField() =>
        tester.widget<TextField>(find.byType(TextField).at(1));

    expect(passwordField().obscureText, isTrue);

    await tester.tap(find.byTooltip('Afficher le mot de passe'));
    await tester.pump();

    expect(passwordField().obscureText, isFalse);

    await tester.tap(find.byTooltip('Masquer le mot de passe'));
    await tester.pump();

    expect(passwordField().obscureText, isTrue);
  });

  testWidgets('enables registration submit only with a valid password', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen(showResendVerification: true));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Inscription'));
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'Abcd1234!');
    await tester.pump();

    FilledButton registerButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Créer un compte'),
    );

    expect(registerButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField).at(1), 'Abcd1234!x');
    await tester.pump();

    expect(registerButton().onPressed, isNotNull);
    expect(find.textContaining('10 caractères minimum'), findsOneWidget);
    expect(find.text('Renvoyer l\'email de vérification'), findsOneWidget);
  });

  testWidgets('shows OTP field automatically for the configured admin email', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildScreen(admin2faEmail: 'admin@watchtracker.net'),
    );

    expect(find.text('Code 2FA (admin)'), findsNothing);

    await tester.enterText(
      find.byType(TextField).at(0),
      'admin@watchtracker.net',
    );
    await tester.pump();

    expect(find.text('Code 2FA (admin)'), findsOneWidget);
  });

  testWidgets('shows cooldown and version information', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await tester.pumpWidget(
      buildScreen(retryUntilMillis: now + 5000, forgotUntilMillis: now + 4000),
    );
    await tester.pump();

    expect(find.textContaining('Réessaie dans '), findsOneWidget);
    expect(find.textContaining('Mot de passe oublié ('), findsOneWidget);
    expect(find.text('Version 2.0.8+42'), findsOneWidget);
  });

  testWidgets('shows resend cooldown text in register mode', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await tester.pumpWidget(
      buildScreen(showResendVerification: true, resendUntilMillis: now + 5000),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Inscription'));
    await tester.pump();

    expect(find.textContaining('Renvoyer l\'email ('), findsOneWidget);
  });

  testWidgets('renders image fallback, error and info messages', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildScreen(errorMessage: 'Erreur visible', infoMessage: 'Info visible'),
    );
    await tester.pump();

    expect(find.text('Erreur visible'), findsOneWidget);
    expect(find.text('Info visible'), findsOneWidget);
  });

  testWidgets('submits registration and displays attempts remaining', (
    tester,
  ) async {
    String? registeredEmail;
    String? registeredPassword;

    await tester.pumpWidget(
      buildScreen(
        showResendVerification: true,
        onRegister: (email, password) async {
          registeredEmail = email;
          registeredPassword = password;
        },
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Inscription'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'Abcd1234!x');
    await tester.pump();

    final registerButton = find.widgetWithText(FilledButton, 'Créer un compte');
    await tester.ensureVisible(registerButton);
    await tester.tap(registerButton);
    await tester.pump();

    expect(registeredEmail, 'user@example.com');
    expect(registeredPassword, 'Abcd1234!x');

    await tester.pumpWidget(buildScreen(attemptsRemaining: 2));
    await tester.pump();

    expect(find.text('Tentatives restantes avant blocage : 2'), findsOneWidget);
  });

  testWidgets('calls login with otp code when admin submits the form', (
    tester,
  ) async {
    String? submittedOtp;
    String? submittedEmail;

    await tester.pumpWidget(
      buildScreen(
        admin2faEmail: 'admin@watchtracker.net',
        onLogin: (email, _, otpCode) async {
          submittedEmail = email;
          submittedOtp = otpCode;
        },
      ),
    );

    await tester.enterText(
      find.byType(TextField).at(0),
      'admin@watchtracker.net',
    );
    await tester.enterText(find.byType(TextField).at(1), 'Secret123!');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(2), '123456');
    await tester.pump();

    final loginButton = find.widgetWithText(FilledButton, 'Se connecter');
    await tester.ensureVisible(loginButton);
    await tester.tap(loginButton);
    await tester.pump();

    expect(submittedEmail, 'admin@watchtracker.net');
    expect(submittedOtp, '123456');
  });

  testWidgets('calls forgot password and resend verification callbacks', (
    tester,
  ) async {
    String? forgotEmail;
    String? resendEmail;

    await tester.pumpWidget(
      buildScreen(
        showResendVerification: true,
        onForgotPassword: (email) async => forgotEmail = email,
        onResendVerification: (email) async => resendEmail = email,
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'Secret123!');
    await tester.pump();

    final forgotButton = find.widgetWithText(
      OutlinedButton,
      'Mot de passe oublié',
    );
    await tester.ensureVisible(forgotButton);
    await tester.tap(forgotButton);
    await tester.pump();

    expect(forgotEmail, 'user@example.com');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Inscription'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'Abcd1234!x');
    await tester.pump();
    final resendButton = find.widgetWithText(
      OutlinedButton,
      'Renvoyer l\'email de vérification',
    );
    await tester.ensureVisible(resendButton);
    await tester.tap(resendButton);
    await tester.pump();

    expect(resendEmail, 'user@example.com');
  });

  testWidgets('disables auth actions while loading and notifies mode change', (
    tester,
  ) async {
    var modeChanges = 0;

    await tester.pumpWidget(buildScreen(isLoading: true));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Mot de passe oublié'),
          )
          .onPressed,
      isNull,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          appVersionLabel: '2.0.8+42',
          isLoading: false,
          showResendVerification: true,
          onLogin: (_, _, _) async {},
          onRegister: (_, _) async {},
          onForgotPassword: (_) async {},
          onResendVerification: (_) async {},
          onModeChanged: () => modeChanges++,
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Inscription'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Connexion'));
    await tester.pump();

    expect(modeChanges, 2);
  });

  testWidgets('updates countdowns when widget properties change', (
    tester,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await tester.pumpWidget(buildScreen(retryUntilMillis: now + 2500));
    await tester.pump();
    expect(find.textContaining('Réessaie dans '), findsOneWidget);

    await tester.pumpWidget(
      buildScreen(retryUntilMillis: now + 4500, resendUntilMillis: now + 4500),
    );
    await tester.pump();
    expect(find.textContaining('Réessaie dans '), findsOneWidget);
    expect(find.textContaining('Renvoyer l\'email ('), findsNothing);
  });
}
