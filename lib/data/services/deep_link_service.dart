import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:injectable/injectable.dart';
import 'package:logger/logger.dart';

import '../../core/network/api_client.dart';

/// Outcome of an email-verification deep link.
class EmailVerificationResult {
  final bool isSuccess;
  final String message;

  const EmailVerificationResult._(this.isSuccess, this.message);

  const EmailVerificationResult.success()
      : this._(true, 'Email verified successfully!');

  const EmailVerificationResult.failure(String message)
      : this._(false, message);
}

/// Handles `sekretess://` deep links.
///
/// The only link the app reacts to is the email-verification callback
/// `sekretess://verify`, registered in `AndroidManifest.xml` (intent-filter)
/// and `ios/Runner/Info.plist` (`CFBundleURLTypes`). iOS cannot filter by host
/// declaratively — it hands over every `sekretess://` URL — so the host check
/// below is what keeps the two platforms behaving the same.
///
/// Two link shapes are supported, so the flow works whether the token is
/// consumed by the server or by the app:
///
/// * `sekretess://verify` — the server already validated the token and only
///   redirects into the app. An optional `status` query parameter carries the
///   outcome (treated as success when absent; any other value is a failure and
///   may be described by a `message` parameter).
/// * `sekretess://verify?token=<token>` (or `sekretess://verify/<token>`) —
///   the app itself calls `GET /auth/verify/<token>` to confirm the address.
@lazySingleton
class DeepLinkService {
  static const String _scheme = 'sekretess';
  static const String _verifyHost = 'verify';
  static const String _failureMessage =
      'Email verification failed. The link may have expired.';

  final ApiClient _apiClient;
  final Logger _logger = Logger();
  final AppLinks _appLinks = AppLinks();
  final StreamController<EmailVerificationResult> _results =
      StreamController<EmailVerificationResult>.broadcast();

  StreamSubscription<Uri>? _subscription;
  bool _isInitialized = false;

  /// Buffers a result that arrived before the UI subscribed — the cold-start
  /// link is delivered while `main()` is still wiring things up.
  EmailVerificationResult? _pendingResult;

  DeepLinkService(this._apiClient);

  /// Emits once per handled verification link.
  Stream<EmailVerificationResult> get verificationResults => _results.stream;

  /// A result that arrived before anyone was listening. Reading it clears it.
  EmailVerificationResult? takePendingResult() {
    final pending = _pendingResult;
    _pendingResult = null;
    return pending;
  }

  /// Starts listening for deep links, including the one that cold-started the
  /// app. Safe to call more than once.
  Future<void> initialize() async {
    if (_isInitialized) {
      _logger.i('DeepLinkService already initialized');
      return;
    }
    _isInitialized = true;

    // Links delivered while the app is running (Android onNewIntent /
    // iOS application:openURL:). `uriLinkStream` also replays the link that
    // launched the app, so cold start needs no separate call.
    _subscription = _appLinks.uriLinkStream.listen(
      _handleLink,
      onError: (Object e) => _logger.e('Deep link stream error', error: e),
    );
  }

  Future<void> _handleLink(Uri uri) async {
    _logger.i('Deep link received: $uri');

    if (uri.scheme != _scheme || uri.host != _verifyHost) {
      _logger.w('Ignoring unsupported deep link: $uri');
      return;
    }

    final token = _extractToken(uri);
    if (token != null) {
      final verified = await _apiClient.verifyEmail(token);
      _emit(verified
          ? const EmailVerificationResult.success()
          : const EmailVerificationResult.failure(_failureMessage));
      return;
    }

    final status = uri.queryParameters['status']?.toLowerCase();
    if (status == null || status == 'success' || status == 'ok') {
      _emit(const EmailVerificationResult.success());
    } else {
      _emit(EmailVerificationResult.failure(
        uri.queryParameters['message'] ?? _failureMessage,
      ));
    }
  }

  void _emit(EmailVerificationResult result) {
    if (_results.hasListener) {
      _results.add(result);
    } else {
      _pendingResult = result;
    }
  }

  /// Reads the token from `?token=...` or from the first path segment.
  String? _extractToken(Uri uri) {
    final queryToken = uri.queryParameters['token']?.trim();
    if (queryToken != null && queryToken.isNotEmpty) return queryToken;

    for (final segment in uri.pathSegments) {
      final trimmed = segment.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  @disposeMethod
  void dispose() {
    _subscription?.cancel();
    _results.close();
  }
}
