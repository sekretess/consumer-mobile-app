import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

part 'message_database.g.dart';

class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text()();
  TextColumn get sender => text()();
  TextColumn get messageBody => text()();
  IntColumn get createdAt => integer()();
}

@DriftDatabase(tables: [Messages])
class MessageDatabase extends _$MessageDatabase {
  MessageDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // Get latest message from each sender for a username
  // This matches the Android Room query: SELECT * FROM sekretes_message_store 
  // WHERE createdAt IN (SELECT MAX(createdAt) FROM sekretes_message_store AS inner_ms 
  // WHERE inner_ms.sender = sekretes_message_store.sender) AND username = :username
  // Using JOIN approach for better reliability
  Future<List<Message>> getMessageBriefs(String username) async {
    final query = customSelect(
      '''
      SELECT m.* FROM messages m
      INNER JOIN (
        SELECT sender, MAX(created_at) AS max_created_at
        FROM messages
        WHERE username = ?
        GROUP BY sender
      ) latest ON m.sender = latest.sender 
        AND m.created_at = latest.max_created_at
        AND m.username = ?
      ORDER BY m.created_at DESC
      ''',
      variables: [
        Variable.withString(username),
        Variable.withString(username),
      ],
      readsFrom: {messages},
    );
    
    final results = await query.get();
    return results.map((row) {
      return Message(
        id: row.read<int>('id'),
        username: row.read<String>('username'),
        sender: row.read<String>('sender'),
        messageBody: row.read<String>('message_body'),
        createdAt: row.read<int>('created_at'),
      );
    }).toList();
  }

  // Get top 4 senders (distinct senders, ordered by most recent)
  Future<List<String>> getTopSenders(String username) async {
    final query = customSelect(
      '''
      SELECT DISTINCT sender FROM messages 
      WHERE username = ?
      ORDER BY created_at DESC 
      LIMIT 4
      ''',
       variables: [
        Variable.withString(username),
      ],
      readsFrom: {messages},
    );
    
    final results = await query.get();
    return results
        .map((row) => row.read<String>('sender'))
        .where((sender) => sender.isNotEmpty)
        .toList();
  }

  // Get messages for a specific sender
  Future<List<Message>> getMessages(String username, String sender) async {
    final query = select(messages)
      ..where((m) => m.username.equals(username) & m.sender.equals(sender))
      ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc)]);
    
    return await query.get();
  }

  // Insert a message
  Future<void> insertMessage(String username, String sender, String messageBody) async {
    await into(messages).insert(
      MessagesCompanion.insert(
        username: username,
        sender: sender,
        messageBody: messageBody,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  // Insert a message with specific timestamp (for test data)
  Future<void> insertMessageWithTimestamp(
    String username,
    String sender,
    String messageBody,
    int timestamp,
  ) async {
    await into(messages).insert(
      MessagesCompanion.insert(
        username: username,
        sender: sender,
        messageBody: messageBody,
        createdAt: timestamp,
      ),
    );
  }

  // Update the body of an existing message (used to flip a failed file
  // download to a successful one after a retry, without changing its position)
  Future<void> updateMessageBody(int messageId, String messageBody) async {
    await (update(messages)..where((m) => m.id.equals(messageId)))
        .write(MessagesCompanion(messageBody: Value(messageBody)));
  }

  // Delete a message
  Future<void> deleteMessage(int messageId) async {
    await (delete(messages)..where((m) => m.id.equals(messageId))).go();
  }

  // Clear all messages
  Future<void> clear() async {
    await delete(messages).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File('${dbFolder.path}/sekretess_messages.db');
    return NativeDatabase(file);
  });
}
