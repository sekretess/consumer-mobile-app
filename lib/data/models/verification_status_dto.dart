import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

part 'verification_status_dto.g.dart';

/// Body returned by `POST /consumers/auth/login` with HTTP 403 when the
/// consumer exists but has not verified their email address yet.
///
/// Mirrors `model.VerificationStatus` in consumer-server. The `verified` flag
/// is what the app branches on — a 403 without it is an ordinary auth failure.
@JsonSerializable()
class VerificationStatusDto {
  final String? username;
  @JsonKey(defaultValue: false)
  final bool verified;
  final String? message;

  VerificationStatusDto({
    this.username,
    this.verified = false,
    this.message,
  });

  factory VerificationStatusDto.fromJson(Map<String, dynamic> json) =>
      _$VerificationStatusDtoFromJson(json);

  Map<String, dynamic> toJson() => _$VerificationStatusDtoToJson(this);

  /// Parses a response body into a status, or returns null when the body is
  /// not a verification status. Accepts both a decoded map and a raw JSON
  /// string, since Dio only decodes when the server sets a JSON content type.
  static VerificationStatusDto? tryParse(dynamic data) {
    Map<String, dynamic>? json;
    if (data is Map<String, dynamic>) {
      json = data;
    } else if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {
        return null;
      }
    }
    if (json == null || !json.containsKey('verified')) return null;

    try {
      return VerificationStatusDto.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
