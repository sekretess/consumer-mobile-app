import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';
import 'package:logger/logger.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

import '../../core/network/api_client.dart';
import '../models/file_message_dto.dart';

@lazySingleton
class FileService {
  final ApiClient _apiClient;
  final Logger _logger = Logger();

  FileService(this._apiClient);

  /// Downloads, decrypts and saves the file described by [fileMessage].
  /// Returns the absolute local path on success, or null on failure.
  Future<String?> downloadAndSaveFile(FileMessageDto fileMessage) async {
    try {
      final encryptedBytes = await _apiClient.downloadEncryptedFile(
        fileMessage.fileId,
        fileMessage.fileToken,
      );
      if (encryptedBytes == null || encryptedBytes.isEmpty) {
        _logger.e('FileService: empty response for file ${fileMessage.fileId}');
        return null;
      }

      final key = base64.decode(fileMessage.fileKey);
      final iv = base64.decode(fileMessage.iv);

      final plainBytes = _decryptAesGcm(encryptedBytes, key, iv);
      if (plainBytes == null) return null;

      final ext = _extensionForMimeType(fileMessage.mimeType);
      final dir = await getApplicationDocumentsDirectory();
      final filesDir = Directory('${dir.path}/sekretess_files');
      await filesDir.create(recursive: true);

      final file = File('${filesDir.path}/${fileMessage.fileId}$ext');
      await file.writeAsBytes(plainBytes);

      _logger.i('FileService: saved ${file.path}');
      return file.path;
    } catch (e) {
      _logger.e('FileService: failed to download/save file', error: e);
      return null;
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
