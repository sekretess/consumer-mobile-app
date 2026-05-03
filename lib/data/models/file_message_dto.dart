import 'package:json_annotation/json_annotation.dart';

part 'file_message_dto.g.dart';

@JsonSerializable()
class FileMessageDto {
  final String kind;
  final String algorithm;
  final String digestAlgorithm;
  final String fileId;
  final String fileToken;
  final String fileKey;
  final String iv;
  final String ciphertextSha256;
  final int plaintextSize;
  final int ciphertextSize;
  final String mimeType;

  const FileMessageDto({
    required this.kind,
    required this.algorithm,
    required this.digestAlgorithm,
    required this.fileId,
    required this.fileToken,
    required this.fileKey,
    required this.iv,
    required this.ciphertextSha256,
    required this.plaintextSize,
    required this.ciphertextSize,
    required this.mimeType,
  });

  factory FileMessageDto.fromJson(Map<String, dynamic> json) =>
      _$FileMessageDtoFromJson(json);

  Map<String, dynamic> toJson() => _$FileMessageDtoToJson(this);
}
