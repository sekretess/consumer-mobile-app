import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:injectable/injectable.dart';
import 'package:logger/logger.dart';

import '../constants/app_constants.dart';
import '../../data/models/auth_request.dart';
import '../../data/models/auth_response.dart';
import '../../data/models/business_dto.dart';
import '../../data/models/user_dto.dart';
import '../../data/models/key_bundle_dto.dart';
import '../../data/repositories/auth_repository.dart';
import 'interceptors/auth_interceptor.dart';

@lazySingleton
class ApiClient {
  late final Dio _dio;
  final Logger _logger = Logger();

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.consumerApiUrl,
        connectTimeout: const Duration(seconds: AppConstants.connectionTimeout),
        receiveTimeout: const Duration(seconds: AppConstants.receiveTimeout),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.addAll([
      LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: true,
        responseHeader: true,
        responseBody: true,
        error: true,
        logPrint: (object) {
          // Print to console with proper formatting
          print(object);
        },
      ),
    ]);
  }

  void setAuthRepository(AuthRepository authRepository) {
    _dio.interceptors.insert(0, AuthInterceptor(authRepository));
  }

  // Auth endpoints
  Future<AuthResponse> login(String username, String password) async {
    try {
      final request = AuthRequest(username: username, password: password);
      // Explicitly serialize to JSON string to ensure proper JSON payload
      final jsonString = jsonEncode(request.toJson());
      final response = await _dio.post(
        '/auth/login',
        data: jsonString,
        options: Options(
          contentType: 'application/json',
          headers: {
            'Authorization': null, // No auth needed for login
            'Content-Type': 'application/json',
          },
        ),
      );
      return AuthResponse.fromJson(response.data);
    } catch (e) {
      _logger.e('Login failed', error: e);
      rethrow;
    }
  }

  Future<AuthResponse> refreshToken(String refreshToken) async {
    try {
      // Explicitly serialize to JSON string to ensure proper JSON payload
      final jsonString = jsonEncode({'refresh_token': refreshToken});
      final response = await _dio.post(
        '/auth/refresh',
        data: jsonString,
        options: Options(
          contentType: 'application/json',
          headers: {
            'Authorization': null,
            'Content-Type': 'application/json',
          },
        ),
      );
      return AuthResponse.fromJson(response.data);
    } catch (e) {
      _logger.e('Token refresh failed', error: e);
      rethrow;
    }
  }

  // Business endpoints
  Future<List<BusinessDto>> getBusinesses() async {
    try {
      final response = await _dio.get(AppConstants.businessApiUrl);
      if (response.data is List) {
        return (response.data as List)
            .map((json) => BusinessDto.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      _logger.e('Get businesses failed', error: e);
      return [];
    }
  }

  Future<List<String>> getSubscribedBusinesses() async {
    try {
      final response = await _dio.get('/businesses/subscriptions');
      return (response.data as List).cast<String>();
    } catch (e) {
      _logger.e('Get subscribed businesses failed', error: e);
      return [];
    }
  }

  Future<bool> subscribeToBusiness(String businessId) async {
    try {
      await _dio.post('/businesses/$businessId/subscriptions');
      return true;
    } catch (e) {
      _logger.e('Subscribe to business failed', error: e);
      return false;
    }
  }

  Future<bool> unsubscribeFromBusiness(String businessId) async {
    try {
      await _dio.delete('/businesses/$businessId/subscriptions');
      return true;
    } catch (e) {
      _logger.e('Unsubscribe from business failed', error: e);
      return false;
    }
  }

  // User endpoints
  Future<bool> createUser(String username, String email, String password, Map<String, dynamic> keyBundle) async {
    try {
      // Convert keyBundle to KeyBundleDto to merge with user data
      final keyBundleDto = KeyBundleDto.fromJson(keyBundle);
      
      // Get Firebase messaging token
      String? deviceToken;
      try {
        deviceToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        _logger.w('Failed to get Firebase token for signup', error: e);
      }

      // Create UserDto with key bundle data
      final userDto = UserDto(
        username: username,
        email: email,
        password: password,
        regId: keyBundleDto.regId,
        ik: keyBundleDto.ik,
        spk: keyBundleDto.spk,
        opk: keyBundleDto.opk,
        spkSignature: keyBundleDto.spkSignature,
        spkId: keyBundleDto.spkId,
        pqspk: keyBundleDto.pqspk,
        pqspkId: keyBundleDto.pqspkId,
        pqspkSignature: keyBundleDto.pqspkSignature,
        opqk: keyBundleDto.opqk,
        deviceRegistrationToken: deviceToken,
      );

      // Explicitly serialize to JSON string
      final jsonString = jsonEncode(userDto.toJson());
      final response = await _dio.post('',
        data: jsonString,
        options: Options(
          contentType: 'application/json',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': null, // No auth needed for signup
          },
          validateStatus: (status) {
            return status != null && status >= 200 && status < 300;
          },
        ),
      );
      _logger.i('Create user success: HTTP ${response.statusCode}');
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } on DioException catch (e) {
      _logger.e('Create user failed', error: e, stackTrace: e.stackTrace);
      return false;
    } catch (e) {
      _logger.e('Create user failed', error: e);
      return false;
    }
  }

  Future<bool> deleteUser() async {
    try {
      final response = await _dio.delete(
        '',
        options: Options(
          validateStatus: (status) {
            return status != null && status >= 200 && status < 300;
          },
        ),
      );
      _logger.i('Delete user success: HTTP ${response.statusCode}');
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } on DioException catch (e) {
      _logger.e('Delete user failed', error: e, stackTrace: e.stackTrace);
      return false;
    } catch (e) {
      _logger.e('Delete user failed', error: e);
      return false;
    }
  }

  // Key store endpoints
  Future<bool> upsertKeyStore(Map<String, dynamic> keyBundle) async {
    try {
      // Explicitly serialize to JSON string to ensure proper JSON payload
      final jsonString = jsonEncode(keyBundle);
      final response = await _dio.put(
        '/keystores',
        data: jsonString,
        options: Options(
          contentType: 'application/json',
          headers: {
            'Content-Type': 'application/json',
          },
          validateStatus: (status) {
            // Accept 200-299 as success (including 202 Accepted)
            return status != null && status >= 200 && status < 300;
          },
        ),
      );
      
      // Log success with status code
      _logger.i('Upsert keystore success: HTTP ${response.statusCode}');
      return true;
    } on DioException catch (e) {
      // Log detailed error information
      _logger.e('Upsert keystore failed: ${e.response?.statusCode ?? "No status"} - ${e.message}');
      if (e.response != null) {
        _logger.e('Response data: ${e.response?.data}');
      }
      return false;
    } catch (e) {
      _logger.e('Upsert keystore failed with unexpected error', error: e);
      return false;
    }
  }

  Future<bool> updateOneTimeKeys(Map<String, dynamic> oneTimeKeys) async {
    try {
      // Explicitly serialize to JSON string to ensure proper JSON payload
      final jsonString = jsonEncode(oneTimeKeys);
      final response = await _dio.post(
        '/onetimekeystores',
        data: jsonString,
        options: Options(
          contentType: 'application/json',
          headers: {
            'Content-Type': 'application/json',
          },
          validateStatus: (status) {
            // Accept 200-299 as success (including 202 Accepted)
            return status != null && status >= 200 && status < 300;
          },
        ),
      );
      
      // Log success with status code
      _logger.i('Update one time keys success: HTTP ${response.statusCode}');
      return true;
    } on DioException catch (e) {
      // Log detailed error information
      _logger.e('Update one time keys failed: ${e.response?.statusCode ?? "No status"} - ${e.message}');
      if (e.response != null) {
        _logger.e('Response data: ${e.response?.data}');
      }
      return false;
    } catch (e) {
      _logger.e('Update one time keys failed with unexpected error', error: e);
      return false;
    }
  }

  Future<Uint8List?> downloadEncryptedFile(String fileId, String fileToken) async {
    try {
      final response = await _dio.post(
        '/files',
        data: jsonEncode({'fileId': fileId, 'fileToken': fileToken}),
        options: Options(
          contentType: 'application/json',
          responseType: ResponseType.bytes,
        ),
      );
      return response.data as Uint8List?;
    } catch (e) {
      _logger.e('Download encrypted file failed', error: e);
      return null;
    }
  }
}
