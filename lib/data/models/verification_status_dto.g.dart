// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'verification_status_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VerificationStatusDto _$VerificationStatusDtoFromJson(
        Map<String, dynamic> json) =>
    VerificationStatusDto(
      username: json['username'] as String?,
      verified: json['verified'] as bool? ?? false,
      message: json['message'] as String?,
    );

Map<String, dynamic> _$VerificationStatusDtoToJson(
        VerificationStatusDto instance) =>
    <String, dynamic>{
      'username': instance.username,
      'verified': instance.verified,
      'message': instance.message,
    };
