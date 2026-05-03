// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_message_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FileMessageDto _$FileMessageDtoFromJson(Map<String, dynamic> json) =>
    FileMessageDto(
      kind: json['kind'] as String,
      algorithm: json['algorithm'] as String,
      digestAlgorithm: json['digestAlgorithm'] as String,
      fileId: json['fileId'] as String,
      fileToken: json['fileToken'] as String,
      fileKey: json['fileKey'] as String,
      iv: json['iv'] as String,
      ciphertextSha256: json['ciphertextSha256'] as String,
      plaintextSize: (json['plaintextSize'] as num).toInt(),
      ciphertextSize: (json['ciphertextSize'] as num).toInt(),
      mimeType: json['mimeType'] as String,
    );

Map<String, dynamic> _$FileMessageDtoToJson(FileMessageDto instance) =>
    <String, dynamic>{
      'kind': instance.kind,
      'algorithm': instance.algorithm,
      'digestAlgorithm': instance.digestAlgorithm,
      'fileId': instance.fileId,
      'fileToken': instance.fileToken,
      'fileKey': instance.fileKey,
      'iv': instance.iv,
      'ciphertextSha256': instance.ciphertextSha256,
      'plaintextSize': instance.plaintextSize,
      'ciphertextSize': instance.ciphertextSize,
      'mimeType': instance.mimeType,
    };
