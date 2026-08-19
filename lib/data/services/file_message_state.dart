import 'dart:convert';

import '../models/file_message_dto.dart';
import 'file_service.dart';

/// Pure (de)serialisation of a file-message row body.
///
/// A file message is persisted as a JSON string in the message store. This
/// keeps the shape of that string in one place so the write path
/// ([encodeFileMessageBody]) and the read path ([decodeFileMessageBody]) can
/// never drift apart, and so the download-state logic is unit-testable without
/// a database, network or crypto.

const _fileBodyPrefix = '{"kind":"file"';

/// Parsed view of a persisted file-message body.
class FileMessageState {
  final String? localPath;
  final String? mimeType;
  final bool downloadFailed;
  final bool retryable;
  final Map<String, dynamic>? fileMessageJson;

  const FileMessageState({
    this.localPath,
    this.mimeType,
    this.downloadFailed = false,
    this.retryable = false,
    this.fileMessageJson,
  });

  bool get isDownloaded => localPath != null;
}

/// Serialises a file message row. On success only the local artefacts are
/// kept; on failure the full [FileMessageDto] (including the one-time file
/// token) is retained so a retryable download can be re-attempted.
String encodeFileMessageBody(
  FileMessageDto fileMessage,
  FileDownloadOutcome outcome,
) {
  if (outcome.isSuccess) {
    return jsonEncode({
      'kind': 'file',
      'status': 'downloaded',
      'localPath': outcome.localPath,
      'mimeType': fileMessage.mimeType,
    });
  }
  return jsonEncode({
    'kind': 'file',
    'status': 'failed',
    'retryable': outcome.isRetryable,
    'mimeType': fileMessage.mimeType,
    'fileMessage': fileMessage.toJson(),
  });
}

/// Parses a persisted message body. Returns null when [body] is not a file
/// message (in which case it is plain text).
FileMessageState? decodeFileMessageBody(String body) {
  if (!body.startsWith(_fileBodyPrefix)) return null;
  try {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final localPath = json['localPath'] as String?;
    // `status` is absent on legacy rows; infer failure from a missing path.
    final status = json['status'] as String?;
    final downloadFailed =
        status == 'failed' || (status == null && localPath == null);
    return FileMessageState(
      localPath: localPath,
      mimeType: json['mimeType'] as String?,
      downloadFailed: downloadFailed,
      retryable: json['retryable'] as bool? ?? false,
      fileMessageJson: json['fileMessage'] as Map<String, dynamic>?,
    );
  } catch (_) {
    // Malformed JSON – treat as plain text.
    return null;
  }
}
