import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';

import '../models/message_brief_dto.dart';
import '../models/message_dto.dart';
import '../models/message_record_dto.dart';
import '../models/business_dto.dart';
import '../models/file_message_dto.dart';
import '../repositories/message_repository.dart';
import '../repositories/auth_repository.dart';
import '../../core/enums/message_type.dart';
import 'cryptographic_service.dart';
import 'file_service.dart';
import 'file_message_state.dart';
import '../database/message_database.dart' as db;

abstract class IMessageService {
  Future<List<MessageBriefDto>> getMessageBriefs(String username);
  Future<List<String>> getTopSenders(String username);
  Future<void> handleMessage(MessageDto message);
  Future<List<MessageRecordDto>> loadMessages(String sender);
  Future<bool> retryFileDownload(int messageId, Map<String, dynamic> fileMessageJson);
  Stream<void> get fileStoredStream;
}

@lazySingleton
class MessageService implements IMessageService {
  final MessageRepository _messageRepository;
  final AuthRepository _authRepository;
  final CryptographicService _cryptographicService;
  final FileService _fileService;
  final Logger _logger = Logger();

  final _fileStoredController = StreamController<void>.broadcast();

  @override
  Stream<void> get fileStoredStream => _fileStoredController.stream;

  MessageService(
    this._messageRepository,
    this._authRepository,
    this._cryptographicService,
    this._fileService,
  );

  @override
  Future<List<MessageBriefDto>> getMessageBriefs(String username) async {
    return await _messageRepository.getMessageBriefs(username);
  }

  @override
  Future<List<String>> getTopSenders(String username) async {
    return await _messageRepository.getTopSenders(username);
  }

  @override
  Future<void> handleMessage(MessageDto message) async {
    try {
      final messageType = MessageType.fromString(message.type);
      final encryptedText = message.text;
      final sender = message.sender;

      _logger.i('Handling message type: ${message.type} from $sender');

      switch (messageType) {
        case MessageType.advertisement:
          await _processAdvertisementMessage(encryptedText, sender);
          break;
        case MessageType.keyDistribution:
          await _processKeyDistributionMessage(encryptedText, sender);
          break;
        case MessageType.private:
          await _processPrivateMessage(encryptedText, sender);
          break;
        case MessageType.file:
          await _processFileMessage(encryptedText, sender);
          break;
        case MessageType.unknown:
          _logger.w('Unknown message type: ${message.type}');
          break;
      }
    } catch (e) {
      _logger.e('Error handling message', error: e);
    }
  }

  Future<void> _processAdvertisementMessage(
    String base64Message,
    String sender,
  ) async {
    try {
      final decryptedMessage =
          await _cryptographicService.decryptGroupChatMessage(sender, base64Message);
      if (decryptedMessage != null) {
        final username = await _authRepository.getUsername();
        await _messageRepository.storeDecryptedMessage(
          sender,
          decryptedMessage,
          username ?? 'unknown',
        );
        _logger.i('Stored decrypted advertisement message from $sender');
      }
    } catch (e) {
      _logger.e('Error processing advertisement message', error: e);
    }
  }

  Future<void> _processPrivateMessage(
    String encryptedText,
    String sender,
  ) async {
    try {
      final decryptedMessage =
          await _cryptographicService.decryptPrivateMessage(sender, encryptedText);
      if (decryptedMessage != null) {
        final username = await _authRepository.getUsername();
        await _messageRepository.storeDecryptedMessage(
          sender,
          decryptedMessage,
          username ?? 'unknown',
        );
        _logger.i('Stored decrypted private message from $sender');
      }
    } catch (e) {
      _logger.e('Error processing private message', error: e);
    }
  }

  Future<void> _processKeyDistributionMessage(
    String encryptedText,
    String sender,
  ) async {
    try {
      final decryptedMessage =
          await _cryptographicService.decryptPrivateMessage(sender, encryptedText);
      if (decryptedMessage != null) {
        await _cryptographicService.processKeyDistributionMessage(sender, decryptedMessage);
        _logger.i('Processed key distribution message from $sender');
      }
    } catch (e) {
      _logger.e('Error processing key distribution message', error: e);
    }
  }

  Future<void> _processFileMessage(
    String encryptedText,
    String sender,
  ) async {
    try {
      // File messages are targeted 1:1 (the fileToken names a single consumer),
      // so the envelope is a pairwise Signal message — decrypt it like a private
      // message (SessionCipher), not a group/sender-key message.
      final decryptedJson =
          await _cryptographicService.decryptPrivateMessage(sender, encryptedText);
      if (decryptedJson == null) {
        _logger.e('Failed to decrypt file message from $sender');
        return;
      }

      final fileMessage = FileMessageDto.fromJson(
        jsonDecode(decryptedJson) as Map<String, dynamic>,
      );

      // Download and decrypt the file; store even on failure so the message
      // appears in the list (with a retry affordance when recoverable).
      final outcome = await _fileService.downloadAndSaveFile(fileMessage);

      final username = await _authRepository.getUsername();
      await _messageRepository.storeDecryptedMessage(
        sender,
        encodeFileMessageBody(fileMessage, outcome),
        username ?? 'unknown',
      );

      _logger.i('Stored file message from $sender, status=${outcome.status}');
      _fileStoredController.add(null);
    } catch (e) {
      _logger.e('Error processing file message', error: e);
    }
  }

  @override
  Future<bool> retryFileDownload(
    int messageId,
    Map<String, dynamic> fileMessageJson,
  ) async {
    try {
      final fileMessage = FileMessageDto.fromJson(fileMessageJson);
      final outcome = await _fileService.downloadAndSaveFile(fileMessage);
      await _messageRepository.updateMessageBody(
        messageId,
        encodeFileMessageBody(fileMessage, outcome),
      );
      _fileStoredController.add(null);
      return outcome.isSuccess;
    } catch (e) {
      _logger.e('Failed to retry file download for id=$messageId', error: e);
      return false;
    }
  }

  @override
  Future<List<MessageRecordDto>> loadMessages(String sender) async {
    try {
      final username = await _authRepository.getUsername();
      if (username == null) return [];

      final messages = await _messageRepository.getMessages(username, sender);
      final List<MessageRecordDto> messageRecords = [];
      String? lastDateText;

      for (final message in messages) {
        final messageDate = DateTime.fromMillisecondsSinceEpoch(message.createdAt);
        final dateText = _formatDateText(messageDate);

        if (lastDateText != dateText) {
          messageRecords.add(MessageRecordDto(
            sender: message.sender,
            message: null,
            messageDate: message.createdAt,
            dateText: dateText,
            itemType: ItemType.header,
          ));
          lastDateText = dateText;
        }

        // Detect file messages stored as JSON
        final fileState = decodeFileMessageBody(message.messageBody);

        messageRecords.add(MessageRecordDto(
          messageId: message.id,
          sender: message.sender,
          // Plain-text rows show their body; file rows use the file fields.
          message: fileState == null ? message.messageBody : null,
          messageDate: message.createdAt,
          dateText: dateText,
          itemType: ItemType.item,
          filePath: fileState?.localPath,
          mimeType: fileState?.mimeType,
          downloadFailed: fileState?.downloadFailed ?? false,
          retryable: fileState?.retryable ?? false,
          fileMessageJson: fileState?.fileMessageJson,
        ));
      }

      return messageRecords;
    } catch (e) {
      _logger.e('Failed to load messages', error: e);
      return [];
    }
  }

  String _formatDateText(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final daysDifference = today.difference(messageDate).inDays;

    if (daysDifference == 0) {
      return 'Today';
    } else if (daysDifference <= 7) {
      return DateFormat('EEEE').format(dateTime);
    } else {
      final monthsDifference =
          (now.year - dateTime.year) * 12 + (now.month - dateTime.month);
      if (monthsDifference >= 12) {
        return DateFormat('dd MMMM yyyy').format(dateTime);
      } else {
        return DateFormat('dd MMMM').format(dateTime);
      }
    }
  }

  // Helper method to insert message with specific timestamp
  Future<void> _insertMessageWithTimestamp(
    String sender,
    String message,
    String username,
    DateTime timestamp,
  ) async {
    try {
      final messageDatabase = db.MessageDatabase();
      await messageDatabase.insertMessageWithTimestamp(
        username,
        sender,
        message,
        timestamp.millisecondsSinceEpoch,
      );
    } catch (e) {
      _logger.e('Failed to insert message with timestamp', error: e);
    }
  }
}
