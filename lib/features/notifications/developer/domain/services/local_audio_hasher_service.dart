import 'dart:io';

/// Result of local audio hashing and metadata extraction.
class LocalAudioHashResult {
  final String filePath;
  final String fileName;
  final int fileSizeBytes;
  final String sha256;
  final int? durationSeconds;

  const LocalAudioHashResult({
    required this.filePath,
    required this.fileName,
    required this.fileSizeBytes,
    required this.sha256,
    this.durationSeconds,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalAudioHashResult &&
          runtimeType == other.runtimeType &&
          filePath == other.filePath &&
          fileSizeBytes == other.fileSizeBytes &&
          sha256 == other.sha256 &&
          durationSeconds == other.durationSeconds;

  @override
  int get hashCode => Object.hash(filePath, fileSizeBytes, sha256, durationSeconds);

  @override
  String toString() =>
      'LocalAudioHashResult($fileName, $fileSizeBytes bytes, sha256: ${sha256.substring(0, 8)}..., duration: ${durationSeconds ?? "unknown"}s)';
}

/// Contract for hashing and inspecting local audio files for catalog draft composition.
abstract interface class LocalAudioHasherService {
  /// Analyzes a local audio file:
  /// - Enforces allowed audio extensions (.mp3, .m4a, .wav).
  /// - Computes cryptographic SHA-256 checksum via streaming.
  /// - Determines exact byte size.
  /// - Extracts audio duration metadata with graceful fallback to null if unavailable.
  Future<LocalAudioHashResult> hashAudioFile(File file);
}

