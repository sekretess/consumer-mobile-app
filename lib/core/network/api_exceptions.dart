/// Thrown when login is refused because the account's email address has not
/// been verified yet (HTTP 403 with `verified: false`). Carries the username
/// so the UI can offer to resend the verification email.
class EmailNotVerifiedException implements Exception {
  final String username;
  final String message;

  EmailNotVerifiedException({
    required this.username,
    required this.message,
  });

  @override
  String toString() => 'EmailNotVerifiedException($username): $message';
}

/// Thrown when resending the verification email fails (e.g. unknown user, or
/// the account has meanwhile been verified). [message] is server-provided and
/// safe to show to the user.
class ResendVerificationException implements Exception {
  final String message;

  ResendVerificationException(this.message);

  @override
  String toString() => 'ResendVerificationException: $message';
}
