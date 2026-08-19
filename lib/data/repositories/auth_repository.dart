import 'dart:async';
import 'dart:convert';
import 'package:injectable/injectable.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_response.dart';
import '../services/cryptographic_service.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/app_constants.dart';

abstract class IAuthRepository {
  /// Throws [EmailNotVerifiedException] when the account exists but its email
  /// address has not been verified yet.
  Future<void> authorize(String username, String password);

  /// Re-sends the signup verification email. Returns the server's confirmation
  /// message; throws [ResendVerificationException] on failure.
  Future<String> resendVerificationEmail(String username);

  Future<String?> getAccessToken();
  Future<void> refreshAccessToken();
  Future<bool> isAuthorized();
  Future<void> logout();
  Future<void> clearUserData();
  Future<String?> getUsername();
  Stream<bool> get logoutStream;
}

@lazySingleton
class AuthRepository implements IAuthRepository {
  final ApiClient _apiClient;
  final SharedPreferences _prefs;
  final CryptographicService _cryptographicService;
  static const String _authStateKey = 'auth_state';
  final _logoutController = StreamController<bool>.broadcast();

  AuthRepository(this._apiClient, this._prefs, this._cryptographicService);

  @override
  Stream<bool> get logoutStream => _logoutController.stream;

  @override
  Future<void> authorize(String username, String password) async {
    final response = await _apiClient.login(username, password);
    await _persistAuthState(response);
  }

  @override
  Future<String> resendVerificationEmail(String username) =>
      _apiClient.resendVerificationEmail(username);

  @override
  Future<String?> getAccessToken() async {
    try {
      final authState = await _readAuthState();
      if (authState == null) return null;

      final token = authState.accessToken;
      if (!_isTokenExpired(token)) {
        return token;
      }

      // Token expired, try to refresh
      await refreshAccessToken();
      final refreshedAuthState = await _readAuthState();
      return refreshedAuthState?.accessToken;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> refreshAccessToken() async {
    final authState = await _readAuthState();
    if (authState == null) {
      throw Exception('No auth state found');
    }

    final refreshToken = authState.refreshToken;
    if (_isTokenExpired(refreshToken)) {
      await clearUserData();
      throw Exception('Refresh token expired');
    }

    final refreshed = await _apiClient.refreshToken(refreshToken);
    await _persistAuthState(refreshed);
  }

  @override
  Future<bool> isAuthorized() async {
    try {
      final token = await getAccessToken();
      return token != null && !_isTokenExpired(token);
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> logout() async {
    await _cryptographicService.clearSignalKeys();
    await _removeAuthState();
    _logoutController.add(true);
  }

  @override
  Future<void> clearUserData() async {
    await _cryptographicService.clearSignalKeys();
    await _removeAuthState();
    _logoutController.add(true);
  }

  @override
  Future<String?> getUsername() async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final decodedToken = JwtDecoder.decode(token);
      return decodedToken[AppConstants.usernameClaim] as String?;
    } catch (e) {
      return null;
    }
  }

  bool _isTokenExpired(String token) {
    try {
      return JwtDecoder.isExpired(token);
    } catch (e) {
      return true;
    }
  }

  Future<void> _persistAuthState(AuthResponse response) async {
    final json = jsonEncode(response.toJson());
    await _prefs.setString(_authStateKey, json);
  }

  Future<AuthResponse?> _readAuthState() async {
    final jsonString = _prefs.getString(_authStateKey);
    if (jsonString == null) return null;

    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return AuthResponse.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  Future<void> _removeAuthState() async {
    await _prefs.remove(_authStateKey);
  }
}
