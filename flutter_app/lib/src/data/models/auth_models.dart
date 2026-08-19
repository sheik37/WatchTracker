class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresInSeconds,
  });

  final String accessToken;
  final String? refreshToken;
  final int expiresInSeconds;
}

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.email,
    required this.displayName,
  });

  final int userId;
  final String email;
  final String? displayName;
}

class AuthException implements Exception {
  const AuthException(
    this.message, {
    this.retryAfterSeconds,
    this.attemptsRemaining,
    this.requiresOtp = false,
  });

  final String message;
  final int? retryAfterSeconds;
  final int? attemptsRemaining;
  final bool requiresOtp;

  @override
  String toString() => message;
}
