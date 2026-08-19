import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:injectable/injectable.dart';
import 'package:logger/logger.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

import '../../core/network/api_client.dart';
import '../models/file_message_dto.dart';

/// Result of an encrypted-file download attempt.
///
/// The consumer-server deletes the object from storage the moment it has
/// finished streaming it to the client (one-time download). This means the
/// distinction between "the HTTP download itself failed" and "we received the
/// bytes but could not decrypt/save them" is important:
///
/// * [downloadFailed] — no complete stream reached us, so the server did NOT
///   delete the object. The download can be safely retried.
/// * [decryptFailed] — the bytes arrived (server already deleted the object),
///   but decryption/writing failed. Retrying will 4xx; the file is lost.
enum FileDownloadStatus { success, downloadFailed, decryptFailed }

class FileDownloadOutcome {
  final FileDownloadStatus status;
  final String? localPath;

  const FileDownloadOutcome(this.status, {this.localPath});

  bool get isSuccess => status == FileDownloadStatus.success;

  /// True only when the object is still retrievable from the server.
  bool get isRetryable => status == FileDownloadStatus.downloadFailed;
}

@lazySingleton
class FileService {
  final ApiClient _apiClient;
  final Logger _logger = Logger();

  FileService(this._apiClient);

  /// Downloads, decrypts and saves the file described by [fileMessage].
  ///
  /// Returns a [FileDownloadOutcome] describing whether it succeeded and, if
  /// not, whether the failure is retryable (see [FileDownloadStatus]).
  Future<FileDownloadOutcome> downloadAndSaveFile(
      FileMessageDto fileMessage) async {
    // Stage 1: fetch the ciphertext. A failure here leaves the object on the
    // server, so it is retryable.
    Uint8List? encryptedBytes;
    try {
      encryptedBytes = await _apiClient.downloadEncryptedFile(
        fileMessage.fileId,
        fileMessage.fileToken,
      );
    } catch (e) {
      _logger.e('FileService: download failed for ${fileMessage.fileId}',
          error: e);
      return const FileDownloadOutcome(FileDownloadStatus.downloadFailed);
    }
    if (encryptedBytes == null || encryptedBytes.isEmpty) {
      _logger.e('FileService: empty response for file ${fileMessage.fileId}');
      return const FileDownloadOutcome(FileDownloadStatus.downloadFailed);
    }

    // Stage 2: the bytes are now in hand; the server has deleted the object.
    // Any failure from here on is permanent for this file.
    try {
      _verifyCiphertextIntegrity(encryptedBytes, fileMessage);

      final key = base64.decode(fileMessage.fileKey);
      final iv = base64.decode(fileMessage.iv);

      final plainBytes = _decryptAesGcm(encryptedBytes, key, iv);
      if (plainBytes == null) {
        return const FileDownloadOutcome(FileDownloadStatus.decryptFailed);
      }

      if (fileMessage.plaintextSize > 0 &&
          plainBytes.length != fileMessage.plaintextSize) {
        _logger.w(
            'FileService: plaintext size mismatch for ${fileMessage.fileId} '
            '(expected ${fileMessage.plaintextSize}, got ${plainBytes.length})');
      }

      final ext = _extensionForMimeType(fileMessage.mimeType);
      final dir = await getApplicationDocumentsDirectory();
      final filesDir = Directory('${dir.path}/sekretess_files');
      await filesDir.create(recursive: true);

      final file = File('${filesDir.path}/${fileMessage.fileId}$ext');
      await file.writeAsBytes(plainBytes);

      _logger.i('FileService: saved ${file.path}');
      return FileDownloadOutcome(FileDownloadStatus.success,
          localPath: file.path);
    } catch (e) {
      _logger.e('FileService: failed to decrypt/save file ${fileMessage.fileId}',
          error: e);
      return const FileDownloadOutcome(FileDownloadStatus.decryptFailed);
    }
  }

  /// Logs a warning if the received ciphertext does not match the digest or
  /// size advertised in [fileMessage]. This is observability only: the
  /// AES-GCM auth tag is the real integrity guarantee, so we do not reject on
  /// mismatch (the digest encoding is producer-defined).
  void _verifyCiphertextIntegrity(
      Uint8List ciphertext, FileMessageDto fileMessage) {
    if (fileMessage.ciphertextSize > 0 &&
        ciphertext.length != fileMessage.ciphertextSize) {
      _logger.w(
          'FileService: ciphertext size mismatch for ${fileMessage.fileId} '
          '(expected ${fileMessage.ciphertextSize}, got ${ciphertext.length})');
    }

    final expected = fileMessage.ciphertextSha256.trim();
    if (expected.isEmpty) return;

    final digest = crypto.sha256.convert(ciphertext);
    final digestHex = digest.toString();
    final digestB64 = base64.encode(digest.bytes);
    final matches = digestHex.toLowerCase() == expected.toLowerCase() ||
        digestB64 == expected;
    if (!matches) {
      _logger.w(
          'FileService: ciphertext SHA-256 mismatch for ${fileMessage.fileId}');
    }
  }

  /// Opens a file at [localPath] using the platform's default viewer.
  Future<void> openFile(String localPath) async {
    final result = await OpenFilex.open(localPath);
    if (result.type != ResultType.done) {
      _logger.w('FileService: could not open file – ${result.message}');
    }
  }

  Uint8List? _decryptAesGcm(Uint8List ciphertext, Uint8List key, Uint8List iv) {
    try {
      final cipher = GCMBlockCipher(AESEngine());
      // 128-bit (16-byte) authentication tag
      cipher.init(
        false,
        AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
      );
      return cipher.process(ciphertext);
    } catch (e) {
      _logger.e('FileService: AES-GCM decryption failed', error: e);
      return null;
    }
  }

  String _extensionForMimeType(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'application/pdf':
        return '.pdf';
      case 'image/jpeg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/gif':
        return '.gif';
      case 'image/webp':
        return '.webp';
      case 'video/mp4':
        return '.mp4';
      case 'audio/mpeg':
        return '.mp3';
      case 'application/zip':
        return '.zip';
      case 'text/plain':
        return '.txt';
      case 'application/msword':
        return '.doc';
      case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        return '.docx';
      default:
        // Derive extension from the subtype (e.g. "application/pdf" → "pdf")
        final parts = mimeType.split('/');
        return parts.length == 2 ? '.${parts[1]}' : '.bin';
    }
  }
}
