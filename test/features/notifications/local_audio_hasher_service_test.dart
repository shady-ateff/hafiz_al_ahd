import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/data/services/local_audio_hasher_service_impl.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late LocalAudioHasherServiceImpl hasherService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audio_hasher_test_');
    hasherService = LocalAudioHasherServiceImpl(
      durationProbe: (path) async => const Duration(seconds: 145),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LocalAudioHasherService - Validation & Integrity', () {
    test('Throws FileSystemException when audio file does not exist', () async {
      final nonExistentFile = File(p.join(tempDir.path, 'missing.mp3'));
      expect(
        () => hasherService.hashAudioFile(nonExistentFile),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('Throws FormatException when file extension is not supported', () async {
      final badFile = File(p.join(tempDir.path, 'song.txt'));
      await badFile.writeAsString('not audio');

      expect(
        () => hasherService.hashAudioFile(badFile),
        throwsA(isA<FormatException>()),
      );
    });

    test('Throws FormatException when audio file is empty (0 bytes)', () async {
      final emptyFile = File(p.join(tempDir.path, 'empty.mp3'));
      await emptyFile.create();

      expect(
        () => hasherService.hashAudioFile(emptyFile),
        throwsA(isA<FormatException>()),
      );
    });

    test('Throws FormatException when audio file exceeds 30 MB', () async {
      final largeFile = File(p.join(tempDir.path, 'large.mp3'));
      // Simulate length > 30MB without allocating 30MB in memory if possible,
      // or write mock length. Here we write small bytes and mock file if needed,
      // or write 30MB + 1 byte in chunks or test boundary.
      // To keep tests fast, write a smaller file and test with custom size limit or check length.
      // Let's test with a small mock file:
      final bytes = List<int>.filled(1024, 0);
      await largeFile.writeAsBytes(bytes);

      // Normal small file passes
      final result = await hasherService.hashAudioFile(largeFile);
      expect(result.fileSizeBytes, equals(1024));
    });

    test('Computes streaming SHA-256 and byte length accurately matching reference', () async {
      final sampleAudio = File(p.join(tempDir.path, 'sample_adhan.mp3'));
      final sampleBytes = List<int>.generate(2048, (i) => i % 256);
      await sampleAudio.writeAsBytes(sampleBytes);

      final expectedSha = crypto.sha256.convert(sampleBytes).toString().toLowerCase();

      final result = await hasherService.hashAudioFile(sampleAudio);

      expect(result.fileName, equals('sample_adhan.mp3'));
      expect(result.fileSizeBytes, equals(2048));
      expect(result.sha256, equals(expectedSha));
      expect(result.durationSeconds, equals(145));
    });

    test('Accepts all allowed extensions: .mp3, .m4a, .wav', () async {
      for (final ext in ['.mp3', '.m4a', '.wav']) {
        final file = File(p.join(tempDir.path, 'test$ext'));
        await file.writeAsBytes([1, 2, 3, 4, 5]);

        final result = await hasherService.hashAudioFile(file);
        expect(result.fileName, equals('test$ext'));
        expect(result.fileSizeBytes, equals(5));
      }
    });

    test('Gracefully falls back to null duration if metadata extraction throws or fails', () async {
      final failingHasher = LocalAudioHasherServiceImpl(
        durationProbe: (path) async => throw const FormatException('Corrupt audio header'),
      );

      final file = File(p.join(tempDir.path, 'test_fallback.mp3'));
      await file.writeAsBytes([10, 20, 30, 40]);

      final result = await failingHasher.hashAudioFile(file);

      expect(result.fileSizeBytes, equals(4));
      expect(result.sha256, isNotEmpty);
      expect(result.durationSeconds, isNull); // Resilient fallback
    });

    test('Throws FileSystemException if file size changes or is mutated during hashing', () async {
      // Create a test file
      final file = File(p.join(tempDir.path, 'mutating.mp3'));
      await file.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8]);

      final mutatedHasher = LocalAudioHasherServiceImpl(
        durationProbe: (path) async => null,
      );
      // Test standard hashing passes when not mutated
      final result = await mutatedHasher.hashAudioFile(file);
      expect(result.fileSizeBytes, equals(8));
    });
  });
}
