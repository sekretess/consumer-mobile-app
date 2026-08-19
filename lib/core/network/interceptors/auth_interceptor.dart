import 'package:dio/dio.dart';

import '../../../data/models/verification_status_dto.dart';
import '../../../data/repositories/auth_repository.dart';

class AuthInterceptor extends Interceptor {
  final AuthRepository _authRepository;

  AuthInterceptor(this._authRepository);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Skip auth for login/refresh endpoints
    if (options.path.contains('/auth/')) {
      handler.next(options);
      return;
    }

    // Get access token and add to headers
    _authRepository.getAccessToken().then((token) {
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    }).catchError((error) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: error,
        ),
      );
    });
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Handle 401/403 errors - unauthorized/forbidden
    final statusCode = err.response?.statusCode;
    final isAuthEndpoint = err.requestOptions.path.contains('/auth/');

    // A login refused because the email isn't verified is not an expired
    // session — clearing user data (and the local Signal keys with it) here
    // would be wrong. Let the caller turn it into a resend prompt instead.
    if (statusCode == 403 && _isUnverifiedEmail(err.response)) {
      handler.next(err);
      return;
    }

    if ((statusCode == 401 || statusCode == 403) && !isAuthEndpoint) {
      // Try to refresh token first (only for non-auth endpoints)
      _authRepository.refreshAccessToken().then((_) {
        // Retry the request with new token
        final options = err.requestOptions;
        _authRepository.getAccessToken().then((token) {
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
            // Retry the original request
            handler.resolve(Response(
              requestOptions: options,
              data: err.response?.data,
            ));
          } else {
            // No token available, logout
            _handleUnauthorized();
            handler.reject(err);
          }
        });
      }).catchError((_) {
        // Refresh failed, logout user
        _handleUnauthorized();
        handler.reject(err);
      });
    } else if ((statusCode == 401 || statusCode == 403) && isAuthEndpoint) {
      // Auth endpoint returned 401/403, logout immediately
      _handleUnauthorized();
      handler.next(err);
    } else {
      handler.next(err);
    }
  }

  bool _isUnverifiedEmail(Response? response) {
    final status = VerificationStatusDto.tryParse(response?.data);
    return status != null && !status.verified;
  }

  void _handleUnauthorized() {
    // Clear auth state and trigger logout
    _authRepository.clearUserData();
  }
}
