// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'business_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BusinessDto _$BusinessDtoFromJson(Map<String, dynamic> json) => BusinessDto(
      displayName: json['displayName'] as String,
      name: json['businessName'] as String,
      businessId: json['businessId'] as String?,
      passedSekretessVerification:
          json['passedSekretessVerification'] as bool? ?? false,
      icon: json['icon'] as String?,
      subscribed: json['subscribed'] as bool? ?? false,
    );

Map<String, dynamic> _$BusinessDtoToJson(BusinessDto instance) =>
    <String, dynamic>{
      'displayName': instance.displayName,
      'businessName': instance.name,
      'businessId': instance.businessId,
      'passedSekretessVerification': instance.passedSekretessVerification,
      'icon': instance.icon,
      'subscribed': instance.subscribed,
    };
