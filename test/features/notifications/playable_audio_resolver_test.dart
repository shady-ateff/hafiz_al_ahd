import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_download_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/playable_audio_resolver_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/playable_audio_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CustomAudioStorageService storageService;
  late PlayableAudioResolverImpl resolver;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('playable_audio_resolver_test_');
    storageService = CustomAudioStorageService(
      docsDirProvider: () async => tempDir,
    );
    resolver = PlayableAudioResolverImpl(storageService: storageService);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PlayableAudioResolverImpl — Built-in Sources', () {
    test('Resolves default Mishary source for non-Fajr prayer cleanly', () async {
      const source = AudioSourceConfig.defaultMishary;

      final resolved = await resolver.resolveAudio(source, isFajr: false);

      expect(resolved.isAsset, isTrue);
      expect(resolved.path, equals('assets/sounds/adhan.mp3'));
      expect(resolved.isFallback, isFalse);
      expect(resolved.fallbackReason, isNull);
    });

    test('Resolves default Mishary source for Fajr prayer with fajr asset', () async {
      const source = AudioSourceConfig.defaultMishary;

      final resolved = await resolver.resolveAudio(source, isFajr: true);

      expect(resolved.isAsset, isTrue);
      expect(resolved.path, equals('assets/sounds/fajr_azan.mp3'));
      expect(resolved.isFallback, isFalse);
      expect(resolved.fallbackReason, isNull);
    });

    test('BuiltInAudioSource with empty asset path falls back to default Mishary', () async {
      const invalidBuiltIn = BuiltInAudioSource(
        id: 'builtIn:custom_empty',
        displayName: 'صوت فارغ',
        assetPath: '',
      );

      final resolved = await resolver.resolveAudio(invalidBuiltIn, isFajr: false);

      expect(resolved.isAsset, isTrue);
      expect(resolved.path, equals('assets/sounds/adhan.mp3'));
      expect(resolved.isFallback, isTrue);
      expect(resolved.fallbackReason, isNotNull);
    });

    test('isAudioPlayableLocally returns true for any BuiltInAudioSource', () async {
      const source = AudioSourceConfig.defaultMishary;
      final isPlayable = await resolver.isAudioPlayableLocally(source);
      expect(isPlayable, isTrue);
    });
  });

  group('PlayableAudioResolverImpl — Local CustomAudioSource & Missing Audio Fallback', () {
    test('Resolves physically existing custom audio file with absolute path', () async {
      final storageDir = await storageService.getStorageDirectory();
      final testFile = File(p.join(storageDir.path, 'custom_valid.mp3'));
      await testFile.writeAsBytes(List.filled(2048, 42)); // 2 KB

      final customSource = CustomAudioSource(
        id: 'custom:valid_1',
        displayName: 'أذان مخصص صحيح',
        localRelativePath: 'adhan_sounds/custom_valid.mp3',
        originalFileName: 'valid.mp3',
        fileSize: 2048,
      );

      final resolved = await resolver.resolveAudio(customSource, isFajr: false);

      expect(resolved.isAsset, isFalse);
      expect(resolved.path, equals(testFile.path));
      expect(resolved.isFallback, isFalse);
      expect(resolved.fallbackReason, isNull);

      final isPlayable = await resolver.isAudioPlayableLocally(customSource);
      expect(isPlayable, isTrue);
    });

    test('Missing custom audio triggers non-destructive fallback for Fajr (Fajr asset)', () async {
      final customSource = CustomAudioSource(
        id: 'custom:missing_fajr',
        displayName: 'أذان فجر مفقود',
        localRelativePath: 'adhan_sounds/non_existent_file.mp3',
        originalFileName: 'non_existent.mp3',
        fileSize: 50000,
      );

      final resolved = await resolver.resolveAudio(customSource, isFajr: true);

      expect(resolved.isAsset, isTrue);
      expect(resolved.path, equals('assets/sounds/fajr_azan.mp3'));
      expect(resolved.isFallback, isTrue);
      expect(resolved.fallbackReason, contains('غير موجود'));

      // isAudioPlayableLocally reports false
      final isPlayable = await resolver.isAudioPlayableLocally(customSource);
      expect(isPlayable, isFalse);
    });

    test('Missing custom audio triggers non-destructive fallback for General (General asset)', () async {
      final customSource = CustomAudioSource(
        id: 'custom:missing_general',
        displayName: 'أذان مفقود عام',
        localRelativePath: 'adhan_sounds/missing.mp3',
        originalFileName: 'missing.mp3',
        fileSize: 100000,
      );

      final resolved = await resolver.resolveAudio(customSource, isFajr: false);

      expect(resolved.isAsset, isTrue);
      expect(resolved.path, equals('assets/sounds/adhan.mp3'));
      expect(resolved.isFallback, isTrue);
      expect(resolved.fallbackReason, contains('غير موجود'));
    });

    test('Empty (0-byte) custom audio file triggers non-destructive fallback', () async {
      final storageDir = await storageService.getStorageDirectory();
      final emptyFile = File(p.join(storageDir.path, 'custom_empty.mp3'));
      await emptyFile.writeAsBytes([]); // 0 bytes

      final customSource = CustomAudioSource(
        id: 'custom:empty_1',
        displayName: 'أذان فارغ 0 بايت',
        localRelativePath: 'adhan_sounds/custom_empty.mp3',
        originalFileName: 'empty.mp3',
        fileSize: 0,
      );

      final resolved = await resolver.resolveAudio(customSource, isFajr: false);

      expect(resolved.isAsset, isTrue);
      expect(resolved.path, equals('assets/sounds/adhan.mp3'));
      expect(resolved.isFallback, isTrue);

      final isPlayable = await resolver.isAudioPlayableLocally(customSource);
      expect(isPlayable, isFalse);
    });

    test('Path traversal in localRelativePath is blocked and falls back safely', () async {
      final maliciousSource = CustomAudioSource(
        id: 'custom:traversal_attack',
        displayName: 'محاولة اختراق مسار',
        localRelativePath: '../../system32/cmd.exe',
        originalFileName: 'cmd.exe',
        fileSize: 1000,
      );

      final resolved = await resolver.resolveAudio(maliciousSource, isFajr: false);

      expect(resolved.isAsset, isTrue);
      expect(resolved.path, equals('assets/sounds/adhan.mp3'));
      expect(resolved.isFallback, isTrue);
      expect(resolved.fallbackReason, contains('غير آمن'));

      final isPlayable = await resolver.isAudioPlayableLocally(maliciousSource);
      expect(isPlayable, isFalse);
    });
  });

  group('PlayableAudioResolverImpl — Remote Catalog Entry Resolution', () {
    final testEntry = AdhanCatalogEntry(
      id: 'remote:mishary_general_test',
      sheikhName: 'مشاري العفاسي',
      audioType: AdhanAudioType.general,
      displayName: 'أذان العفاسي التجريبي',
      durationSeconds: 120,
      objectKey: 'audio/mishary_general.mp3',
      fileSizeBytes: 500000,
      sha256: 'a' * 64,
    );

    test('resolveCatalogEntry returns requiresDownload when file is not yet downloaded', () async {
      final resolution = await resolver.resolveCatalogEntry(testEntry);

      expect(resolution.status, equals(AudioPlayableStatus.requiresDownload));
      expect(resolution.requiresDownload, isTrue);
      expect(resolution.isReady, isFalse);
      expect(resolution.localSource, isNull);
      expect(resolution.physicalPath, isNull);

      final localSource = await resolver.resolveLocalCustomSource(testEntry);
      expect(localSource, isNull);
    });

    test('resolveCatalogEntry returns ready and localSource when file exists locally', () async {
      final storageDir = await storageService.getStorageDirectory();
      final targetFileName = AudioDownloadServiceImpl.buildTargetFileName(testEntry);
      final physicalFile = File(p.join(storageDir.path, targetFileName));
      await physicalFile.writeAsBytes(List.filled(testEntry.fileSizeBytes, 1));

      final resolution = await resolver.resolveCatalogEntry(testEntry);

      expect(resolution.status, equals(AudioPlayableStatus.ready));
      expect(resolution.isReady, isTrue);
      expect(resolution.requiresDownload, isFalse);
      expect(resolution.physicalPath, equals(physicalFile.path));

      final localSource = resolution.localSource;
      expect(localSource, isNotNull);
      expect(localSource!.id, equals('custom:${testEntry.id}'));
      expect(localSource.displayName, equals(testEntry.displayName));
      expect(localSource.localRelativePath, equals(p.join('adhan_sounds', targetFileName)));
      expect(localSource.originalFileName, equals('mishary_general.mp3'));
      expect(localSource.fileSize, equals(testEntry.fileSizeBytes));

      // resolveLocalCustomSource also returns the valid source
      final helperSource = await resolver.resolveLocalCustomSource(testEntry);
      expect(helperSource, equals(localSource));

      // The resolved source can immediately be resolved for audio playback
      final resolvedAudio = await resolver.resolveAudio(localSource, isFajr: false);
      expect(resolvedAudio.isAsset, isFalse);
      expect(resolvedAudio.path, equals(physicalFile.path));
      expect(resolvedAudio.isFallback, isFalse);
    });

    test('resolveCatalogEntry returns missingOrInvalid when entry is invalid', () async {
      // Create invalid entry (e.g. invalid SHA-256 length)
      final invalidEntry = AdhanCatalogEntry(
        id: 'remote:invalid_hash',
        sheikhName: 'شيخ',
        audioType: AdhanAudioType.general,
        displayName: 'أذان غير صالح',
        durationSeconds: 60,
        objectKey: 'audio/invalid.mp3',
        fileSizeBytes: 100,
        sha256: 'short_hash', // Invalid
      );

      final resolution = await resolver.resolveCatalogEntry(invalidEntry);

      expect(resolution.status, equals(AudioPlayableStatus.missingOrInvalid));
      expect(resolution.isMissingOrInvalid, isTrue);
      expect(resolution.isReady, isFalse);
      expect(resolution.localSource, isNull);
    });

    test('resolveCatalogEntry returns requiresDownload if local file is 0 bytes', () async {
      final storageDir = await storageService.getStorageDirectory();
      final targetFileName = AudioDownloadServiceImpl.buildTargetFileName(testEntry);
      final physicalFile = File(p.join(storageDir.path, targetFileName));
      await physicalFile.writeAsBytes([]); // 0 bytes

      final resolution = await resolver.resolveCatalogEntry(testEntry);

      expect(resolution.status, equals(AudioPlayableStatus.requiresDownload));
      expect(resolution.isReady, isFalse);
    });
  });

  group('PlayableAudioResolverImpl — Non-destructive Safety Invariant', () {
    test('Resolving a missing custom audio does not mutate or throw', () async {
      final missingSource = CustomAudioSource(
        id: 'custom:unmodified_user_pref',
        displayName: 'الصوت المختار من المستخدم',
        localRelativePath: 'adhan_sounds/deleted_by_cleaner.mp3',
        originalFileName: 'deleted.mp3',
        fileSize: 12345,
      );

      // Multiple successive resolutions
      final res1 = await resolver.resolveAudio(missingSource, isFajr: false);
      final res2 = await resolver.resolveAudio(missingSource, isFajr: true);

      // Safe fallbacks returned
      expect(res1.isFallback, isTrue);
      expect(res1.path, equals('assets/sounds/adhan.mp3'));
      expect(res2.isFallback, isTrue);
      expect(res2.path, equals('assets/sounds/fajr_azan.mp3'));

      // The original source object remains completely untouched
      expect(missingSource.id, equals('custom:unmodified_user_pref'));
      expect(missingSource.localRelativePath, equals('adhan_sounds/deleted_by_cleaner.mp3'));
    });
  });
}
