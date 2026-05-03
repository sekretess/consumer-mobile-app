// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_record_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MessageRecordDto _$MessageRecordDtoFromJson(Map<String, dynamic> json) =>
    MessageRecordDto(
      messageId: (json['messageId'] as num?)?.toInt(),
      sender: json['sender'] as String,
      message: json['message'] as String?,
      messageDate: (json['messageDate'] as num).toInt(),
      dateText: json['dateText'] as String?,
      itemType: $enumDecode(_$ItemTypeEnumMap, json['itemType']),
      filePath: json['filePath'] as String?,
      mimeType: json['mimeType'] as String?,
    );

Map<String, dynamic> _$MessageRecordDtoToJson(MessageRecordDto instance) =>
    <String, dynamic>{
      'messageId': instance.messageId,
      'sender': instance.sender,
      'message': instance.message,
      'messageDate': instance.messageDate,
      'dateText': instance.dateText,
      'itemType': _$ItemTypeEnumMap[instance.itemType]!,
      'filePath': instance.filePath,
      'mimeType': instance.mimeType,
    };

const _$ItemTypeEnumMap = {
  ItemType.item: 'ITEM',
  ItemType.header: 'HEADER',
};
