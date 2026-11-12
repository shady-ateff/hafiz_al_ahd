import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';

class CustomAudioStorageService {
  static const int maxFileSizeBytes = 15 * 1024 * 1024; // 15 MB
  static const Set<String> allowedExtensions = {'.mp3', '.m4a', '.wav'};

  final Future<Directory> Function()? _docsDirProvider;

  CustomAudioStorageService({Future<Directory> Function()? docsDirProvider})
      : _docsDirProvider = docsDirProvider ?? getApplicationDocumentsDirectory;

  Future<Directory> getStorageDirectory() async {
    final docsDir = await _docsDirProvider!();
    final storageDir = Directory(p.join(docsDir.path, 'adhan_sounds'));
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }
    return storageDir;
  }

  /// Imports an audio file into private application storage with extension preservation
  /// and path traversal protection.
  Future<CustomAudioSource> importCustomAudio({
    required File sourceFile,
    required String displayName,
  }) async {
    if (!await sourceFile.exists()) {
      throw const FileSystemException('Source file does not exist');
    }

    // 1. Extension validation
    final ext = p.extension(sourceFile.path).toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      throw FormatException('Unsupported audio format $ext. Allowed: .mp3, .m4a, .wav');
    }

    // 2. File size validation (<= 15MB)
    final fileSize = await sourceFile.length();
    if (fileSize > maxFileSizeBytes) {
      throw const FileSystemException('File exceeds maximum allowed size of 15 MB');
    }

    final storageDir = await getStorageDirectory();
    final uniqueId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final targetFileName = '$uniqueId$ext';

    // 3. Path traversal guard
    final targetPath = p.normalize(p.join(storageDir.path, targetFileName));
    if (!targetPath.startsWith(storageDir.path)) {
      throw const SecurityException('Path traversal detected');
    }

    await sourceFile.copy(targetPath);
    final relativePath = p.join('adhan_sounds', targetFileName);

    return CustomAudioSource(
      id: 'custom:$uniqueId',
      displayName: displayName.trim().isEmpty ? p.basenameWithoutExtension(sourceFile.path) : displayName.trim(),
      localRelativePath: relativePath,
      originalFileName: p.basename(sourceFile.path),
      fileSize: fileSize,
    );
  }

  /// Deletes a custom audio file with path traversal protection.
  Future<void> deleteCustomAudio(String localRelativePath) async {
    final storageDir = await getStorageDirectory();
    final resolvedPath = p.normalize(p.join(storageDir.parent.path, localRelativePath));

    // Path traversal check
    if (!resolvedPath.startsWith(storageDir.path)) {
      throw const SecurityException('Invalid path: Directory traversal attempt detected');
    }

    final file = File(resolvedPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Checks if the custom audio file exists on disk.
  Future<bool> audioFileExists(String localRelativePath) async {
    final storageDir = await getStorageDirectory();
    final resolvedPath = p.normalize(p.join(storageDir.parent.path, localRelativePath));
    if (!resolvedPath.startsWith(storageDir.path)) {
      return false;
    }
    return File(resolvedPath).exists();
  }
}

class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);
  @override
  String toString() => 'SecurityException: $message';
}

