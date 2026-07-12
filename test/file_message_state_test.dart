import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:consumer_flutter_app/data/models/file_message_dto.dart';
import 'package:consumer_flutter_app/data/services/file_message_state.dart';
import 'package:consumer_flutter_app/data/services/file_service.dart';

FileMessageDto _sampleFileMessage() => const FileMessageDto(
      kind: 'file',
      algorithm: 'AES-256-GCM',
      digestAlgorithm: 'SHA-256',
      fileId: 'file-123',
      fileToken: 'token-abc',
      fileKey: 'a2V5',
      iv: 'aXY=',
      ciphertextSha256: 'deadbeef',
      plaintextSize: 100,
      ciphertextSize: 116,
      mimeType: 'application/pdf',
    );

void main() {
  group('encodeFileMessageBody', () {
    test('success keeps only the local artefacts, not the file token', () {
      final body = encodeFileMessageBody(
        _sampleFileMessage(),
        const FileDownloadOutcome(FileDownloadStatus.success,
            localPath: '/docs/file-123.pdf'),
      );
      final json = jsonDecode(body) as Map<String, dynamic>;

      expect(json['kind'], 'file');
      expect(json['status'], 'downloaded');
      expect(json['localPath'], '/docs/file-123.pdf');
      expect(json['mimeType'], 'application/pdf');
      // The one-time token must not be persisted once consumed.
      expect(json.containsKey('fileMessage'), isFalse);
    });

    test('retryable failure retains the file metadata for retry', () {
      final body = encodeFileMessageBody(
        _sampleFileMessage(),
        const FileDownloadOutcome(FileDownloadStatus.downloadFailed),
      );
      final json = jsonDecode(body) as Map<String, dynamic>;

      expect(json['status'], 'failed');
      expect(json['retryable'], isTrue);
      expect(json['fileMessage'], isA<Map<String, dynamic>>());
      expect((json['fileMessage'] as Map)['fileToken'], 'token-abc');
    });

    test('permanent failure is marked non-retryable', () {
      final body = encodeFileMessageBody(
        _sampleFileMessage(),
        const FileDownloadOutcome(FileDownloadStatus.decryptFailed),
      );
      final json = jsonDecode(body) as Map<String, dynamic>;

      expect(json['status'], 'failed');
      expect(json['retryable'], isFalse);
    });
  });

  group('decodeFileMessageBody', () {
    test('returns null for a plain-text message', () {
      expect(decodeFileMessageBody('hello world'), isNull);
    });

    test('round-trips a successful download', () {
      final body = encodeFileMessageBody(
        _sampleFileMessage(),
        const FileDownloadOutcome(FileDownloadStatus.success,
            localPath: '/docs/file-123.pdf'),
      );
      final state = decodeFileMessageBody(body)!;

      expect(state.isDownloaded, isTrue);
      expect(state.localPath, '/docs/file-123.pdf');
      expect(state.downloadFailed, isFalse);
    });

    test('round-trips a retryable failure with recoverable metadata', () {
      final body = encodeFileMessageBody(
        _sampleFileMessage(),
        const FileDownloadOutcome(FileDownloadStatus.downloadFailed),
      );
      final state = decodeFileMessageBody(body)!;

      expect(state.downloadFailed, isTrue);
      expect(state.retryable, isTrue);
      expect(state.isDownloaded, isFalse);
      // The retained metadata must reconstruct a valid FileMessageDto.
      final restored = FileMessageDto.fromJson(state.fileMessageJson!);
      expect(restored.fileId, 'file-123');
      expect(restored.fileToken, 'token-abc');
    });

    test('permanent failure has no retry affordance', () {
      final body = encodeFileMessageBody(
        _sampleFileMessage(),
        const FileDownloadOutcome(FileDownloadStatus.decryptFailed),
      );
      final state = decodeFileMessageBody(body)!;

      expect(state.downloadFailed, isTrue);
      expect(state.retryable, isFalse);
    });

    test('legacy row without status is inferred: path present = downloaded',
        () {
      const legacy =
          '{"kind":"file","localPath":"/docs/x.pdf","mimeType":"application/pdf"}';
      final state = decodeFileMessageBody(legacy)!;

      expect(state.isDownloaded, isTrue);
      expect(state.downloadFailed, isFalse);
    });

    test('legacy row without status and no path = failed (not retryable)', () {
      const legacy =
          '{"kind":"file","localPath":null,"mimeType":"application/pdf"}';
      final state = decodeFileMessageBody(legacy)!;

      expect(state.downloadFailed, isTrue);
      expect(state.retryable, isFalse);
      expect(state.fileMessageJson, isNull);
    });
  });
}
