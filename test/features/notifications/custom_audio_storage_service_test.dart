import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CustomAudioStorageService storageService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('adhan_sounds_test_');
    storageService = CustomAudioStorageService(
      docsDirProvider: () async => tempDir,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('P4.1-C.6 — CustomAudioStorageService File Safety & Validation', () {
    // -------------------------------------------------------------------------
    // TEST-C-28: Extension preservation
    // -------------------------------------------------------------------------
    test('TEST-C-28: Preserves original extensions for .mp3, .m4a, and .wav', () async {
      for (final ext in ['.mp3', '.m4a', '.wav']) {
        final sampleFile = File(p.join(tempDir.path, 'sample$ext'));
        await sampleFile.writeAsBytes(List.filled(1024, 0)); // 1 KB sample

        final source = await storageService.importCustomAudio(
          sourceFile: sampleFile,
          displayName: 'صوت اختباري $ext',
        );

        expect(source.localRelativePath, endsWith(ext));
        expect(p.extension(source.localRelativePath), equals(ext));
        expect(await storageService.audioFileExists(source.localRelativePath), isTrue);
      }
    });

    // -------------------------------------------------------------------------
    // TEST-C-43: Path traversal protection
    // -------------------------------------------------------------------------
    test('TEST-C-43: Directory traversal attempt is blocked with SecurityException', () async {
      final sampleFile = File(p.join(tempDir.path, 'sample.mp3'));
      await sampleFile.writeAsBytes(List.filled(1024, 0));

      // Attempt deletion with path traversal syntax
      expect(
        () => storageService.deleteCustomAudio('../../windows/system32/cmd.exe'),
        throwsA(isA<SecurityException>()),
      );

      // audioFileExists returns false on path traversal attempt
      final exists = await storageService.audioFileExists('../outside.mp3');
      expect(exists, isFalse);
    });

    test('Unsupported file extension is rejected with FormatException', () async {
      final invalidFile = File(p.join(tempDir.path, 'danger.exe'));
      await invalidFile.writeAsBytes(List.filled(1024, 0));

      expect(
        () => storageService.importCustomAudio(
          sourceFile: invalidFile,
          displayName: 'ملف غير مدعوم',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('File exceeding 15MB limit is rejected with FileSystemException', () async {
      final largeFile = File(p.join(tempDir.path, 'large.mp3'));
      // Create a 16MB file (16 * 1024 * 1024 + 1)
      final bytes = List.filled(16 * 1024 * 1024 + 1, 0);
      await largeFile.writeAsBytes(bytes);

      expect(
        () => storageService.importCustomAudio(
          sourceFile: largeFile,
          displayName: 'ملف كبير جداً',
        ),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}

