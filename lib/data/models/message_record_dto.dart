import 'package:json_annotation/json_annotation.dart';
import 'business_dto.dart';

part 'message_record_dto.g.dart';

@JsonSerializable()
class MessageRecordDto {
  final int? messageId;
  final String sender;
  final String? message;
  final int messageDate;
  final String? dateText;
  final ItemType itemType;
  final String? filePath;
  final String? mimeType;

  bool get isFileMessage => filePath != null || mimeType != null;

  MessageRecordDto({
    this.messageId,
    required this.sender,
    this.message,
    required this.messageDate,
    this.dateText,
    required this.itemType,
    this.filePath,
    this.mimeType,
  });

  factory MessageRecordDto.fromJson(Map<String, dynamic> json) =>
      _$MessageRecordDtoFromJson(json);

  Map<String, dynamic> toJson() => _$MessageRecordDtoToJson(this);
}
