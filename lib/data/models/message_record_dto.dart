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

  /// True when a file message failed to download.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool downloadFailed;

  /// True when a failed download can still be retried (object not yet deleted
  /// from the server). Only meaningful when [downloadFailed] is true.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool retryable;

  /// Serialised [FileMessageDto] retained for retrying a failed download.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final Map<String, dynamic>? fileMessageJson;

  bool get isFileMessage => filePath != null || mimeType != null || downloadFailed;

  MessageRecordDto({
    this.messageId,
    required this.sender,
    this.message,
    required this.messageDate,
    this.dateText,
    required this.itemType,
    this.filePath,
    this.mimeType,
    this.downloadFailed = false,
    this.retryable = false,
    this.fileMessageJson,
  });

  factory MessageRecordDto.fromJson(Map<String, dynamic> json) =>
      _$MessageRecordDtoFromJson(json);

  Map<String, dynamic> toJson() => _$MessageRecordDtoToJson(this);
}
