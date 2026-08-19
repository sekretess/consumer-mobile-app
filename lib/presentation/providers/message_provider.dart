import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/injection.dart';
import '../../core/network/websocket_service.dart';
import '../../data/models/message_brief_dto.dart';
import '../../data/services/message_service.dart';
import '../../data/repositories/auth_repository.dart';

final authRepositoryProvider = Provider.autoDispose<IAuthRepository>((ref) {
  return getIt<AuthRepository>();
});

final usernameProvider = FutureProvider.autoDispose<String?>((ref) async {
  final authRepository = ref.watch(authRepositoryProvider);
  return await authRepository.getUsername();
});

final messageServiceProvider = Provider.autoDispose<IMessageService>((ref) {
  return getIt<MessageService>();
});

// Stream provider for WebSocket message events
final messageEventStreamProvider = StreamProvider.autoDispose<String>((ref) {
  final webSocketService = getIt<WebSocketService>();
  return webSocketService.messageEventStream;
});

// Stream provider that fires when a file message is fully stored
final fileStoredStreamProvider = StreamProvider.autoDispose<void>((ref) {
  return getIt<MessageService>().fileStoredStream;
});

final messageBriefsProvider = FutureProvider.autoDispose<List<MessageBriefDto>>((ref) async {
  final messageService = ref.watch(messageServiceProvider);
  final usernameAsyncValue = ref.watch(usernameProvider);

  // Refresh when a new WebSocket message arrives or a file finishes downloading
  ref.watch(messageEventStreamProvider);
  ref.watch(fileStoredStreamProvider);

  final username = usernameAsyncValue.asData?.value;
  if (username == null) {
    return [];
  }

  return await messageService.getMessageBriefs(username);
});

final topSendersProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final messageService = ref.watch(messageServiceProvider);
  final usernameAsyncValue = ref.watch(usernameProvider);

  ref.watch(messageEventStreamProvider);
  ref.watch(fileStoredStreamProvider);

  final username = usernameAsyncValue.asData?.value;
  if (username == null) {
    return [];
  }
  return await messageService.getTopSenders(username);
});

final filteredMessageBriefsProvider = Provider.autoDispose.family<List<MessageBriefDto>, String>((ref, query) {
  final messageBriefsAsync = ref.watch(messageBriefsProvider);
  
  return messageBriefsAsync.when(
    data: (briefs) {
      if (query.isEmpty) return briefs;
      
      final lowerQuery = query.toLowerCase();
      return briefs.where((brief) {
        final displayBody = brief.messageBody.startsWith('{"kind":"file"')
            ? 'file'
            : brief.messageBody;
        return brief.sender.toLowerCase().contains(lowerQuery) ||
            displayBody.toLowerCase().contains(lowerQuery);
      }).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});