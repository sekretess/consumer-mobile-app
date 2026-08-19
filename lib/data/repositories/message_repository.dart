
import 'package:injectable/injectable.dart';
import 'package:logger/logger.dart';

import '../models/message_brief_dto.dart';
import '../database/message_database.dart';
import '../../core/di/injection.dart';
import 'auth_repository.dart';

// Import the generated Message class
import '../database/message_database.dart' as db;

abstract class IMessageRepository {
  Future<List<MessageBriefDto>> getMessageBriefs(String username);
  Future<List<String>> getTopSenders(String username);
  Future<void> storeDecryptedMessage(String sender, String message, String username);
  Future<void> updateMessageBody(int messageId, String message);
  Future<List<Message>> getMessages(String username, String sender);
  Future<void> deleteMessage(int messageId);
}

@lazySingleton
class MessageRepository implements IMessageRepository {
  final MessageDatabase _database;
  final Logger _logger = Logger();

  MessageRepository() : _database = MessageDatabase();

  @override
  Future<List<MessageBriefDto>> getMessageBriefs(String username) async {
    try {
      final messages = await _database.getMessageBriefs(username);
      return messages.map((msg) {
        return MessageBriefDto(
          sender: msg.sender,
          messageBody: msg.messageBody,
          timestamp: msg.createdAt,
        );
      }).toList();
    } catch (e) {
      _logger.e('Failed to get message briefs', error: e);
      return [];
    }
  }

  @override
  Future<List<String>> getTopSenders(String username) async {
    try {
      return await _database.getTopSenders(username);
    } catch (e) {
      _logger.e('Failed to get top senders', error: e);
      return [];
    }
  }

  @override
  Future<void> storeDecryptedMessage(
    String sender,
    String message,
    String username,
  ) async {
    try {
      await _database.insertMessage(username, sender, message);
      _logger.i('Stored decrypted message from $sender');
    } catch (e) {
      _logger.e('Failed to store decrypted message', error: e);
    }
  }

  @override
  Future<void> updateMessageBody(int messageId, String message) async {
    try {
      await _database.updateMessageBody(messageId, message);
      _logger.i('Updated message body for id=$messageId');
    } catch (e) {
      _logger.e('Failed to update message body', error: e);
    }
  }

  @override
  Future<List<db.Message>> getMessages(String username, String sender) async {
    try {
      return await _database.getMessages(username, sender);
    } catch (e) {
      _logger.e('Failed to get messages', error: e);
      return [];
    }
  }

  @override
  Future<void> deleteMessage(int messageId) async {
    try {
      await _database.deleteMessage(messageId);
    } catch (e) {
      _logger.e('Failed to delete message', error: e);
    }
  }
}
