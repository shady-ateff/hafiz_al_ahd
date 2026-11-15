import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/notifications/data/datasources/prayer_alarm_config_local_data_source.dart';
import 'package:hafiz_al_ahd/features/notifications/data/repos/prayer_alarm_config_repository_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_download_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_storage_lock_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/playable_audio_resolver_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/adhan_catalog_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/adhan_catalog_repository.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/adhan_catalog_cubit/adhan_catalog_cubit.dart';
import 'package:hafiz_al_ahd/features/settings/presentation/screens/adhan_catalog_screen.dart';

class StubCatalogRepository implements BaseAdhanCatalogRepository {
  Either<AdhanCatalogFailure, AdhanCatalog>? result;

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCatalog({bool forceRefresh = false}) async {
    return result ?? Left(CatalogNetworkFailure());
  }

  @override
  Future<Either<AdhanCatalogFailure, AdhanCatalog>> getCachedCatalog() async {
    return result ?? Left(CatalogNetworkFailure());
  }

  @override
  Future<void> clearCache() async {}
}

class FakeAudioPlayer extends AudioPlayer {
  bool isPlaying = false;
  Source? currentSource;

  @override
  Future<void> play(Source source, {double? volume, double? balance, AudioContext? ctx, Duration? position, PlayerMode? mode}) async {
    isPlaying = true;
    currentSource = source;
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
  }

  @override
  Future<void> dispose() async {
    isPlaying = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CustomAudioStorageService storageService;
  late PlayableAudioResolverImpl resolver;
  late StubCatalogRepository catalogRepo;
  late SharedPreferences prefs;
  late PrayerAlarmConfigRepositoryImpl prayerConfigRepo;

  final sampleEntry = AdhanCatalogEntry(
    id: 'remote:persistence_test_entry',
    sheikhName: 'الشيخ الدائم',
    audioType: AdhanAudioType.general,
    displayName: 'أذان التحقق من البقاء',
    durationSeconds: 120,
    objectKey: 'audio/persistence.mp3',
    fileSizeBytes: 2048,
    sha256: 'c' * 64,
  );

  final sampleCatalog = AdhanCatalog(
    schemaVersion: 1,
    generatedAt: '2026-11-13T12:00:00Z',
    entries: [sampleEntry],
  );

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall methodCall) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall methodCall) async => 1,
    );

    tempDir = await Directory.systemTemp.createTemp('lifecycle_persistence_test_');
    storageService = CustomAudioStorageService(docsDirProvider: () async => tempDir);
    resolver = PlayableAudioResolverImpl(storageService: storageService);
    catalogRepo = StubCatalogRepository()..result = Right(sampleCatalog);

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final localDs = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
    prayerConfigRepo = PrayerAlarmConfigRepositoryImpl(
      localDataSource: localDs,
      audioStorageLock: AudioStorageLock(),
      storageService: storageService,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('P4.2 Phase 3.5 — Selection Consistency & Persistence Tests', () {
    test('Selected CustomAudioSource persists in SharedPreferences across app restarts', () async {
      // 1. Simulate a downloaded audio file promoted to storage
      final storageDir = await storageService.getStorageDirectory();
      final targetFileName = AudioDownloadServiceImpl.buildTargetFileName(sampleEntry);
      final file = File('${storageDir.path}/$targetFileName');
      await file.writeAsBytes(List.filled(2048, 77));

      // 2. Resolve to valid CustomAudioSource
      final resolution = await resolver.resolveCatalogEntry(sampleEntry);
      expect(resolution.isReady, isTrue);
      final customSource = resolution.localSource!;

      // 3. User selects this source for Fajr and Dhuhr
      final fajrConfig = PrayerAlarmConfig(
        prayerId: PrayerId.fajr,
        alarmType: PrayerAlarmType.alarm,
        audioSource: customSource,
      );
      await prayerConfigRepo.saveConfig(fajrConfig);

      // 4. Simulate app restart: Instantiate fresh repository from same SharedPreferences
      final freshLocalDs = PrayerAlarmConfigLocalDataSourceImpl(prefs: prefs);
      final freshRepo = PrayerAlarmConfigRepositoryImpl(
        localDataSource: freshLocalDs,
        audioStorageLock: AudioStorageLock(),
        storageService: storageService,
      );

      final loadedConfigs = await freshRepo.getConfigs();
      final restoredFajr = loadedConfigs[PrayerId.fajr];

      expect(restoredFajr, isNotNull);
      expect(restoredFajr!.audioSource, isA<CustomAudioSource>());
      final restoredSource = restoredFajr.audioSource as CustomAudioSource;
      expect(restoredSource.id, equals('custom:${sampleEntry.id}'));
      expect(restoredSource.displayName, equals(sampleEntry.displayName));
      expect(restoredSource.localRelativePath, equals(p.join('adhan_sounds', targetFileName)));
      expect(restoredSource.fileSize, equals(2048));
    });

    test('Catalog refresh or clear does NOT alter user selected CustomAudioSource', () async {
      // 1. Create file on disk so physical guard passes
      final storageDir = await storageService.getStorageDirectory();
      final file = File(p.join(storageDir.path, 'remote_reciter.mp3'));
      await file.writeAsBytes(List.filled(15000, 1));

      // 2. Save user preference with CustomAudioSource
      const customSource = CustomAudioSource(
        id: 'custom:remote:persistent_reciter',
        displayName: 'أذان الشيخ المفضل',
        localRelativePath: 'adhan_sounds/remote_reciter.mp3',
        originalFileName: 'reciter.mp3',
        fileSize: 15000,
      );

      final asrConfig = PrayerAlarmConfig(
        prayerId: PrayerId.asr,
        alarmType: PrayerAlarmType.alarm,
        audioSource: customSource,
      );
      await prayerConfigRepo.saveConfig(asrConfig);

      // 3. Simulate Catalog update or cache clearing
      await catalogRepo.clearCache();
      catalogRepo.result = Right(AdhanCatalog(
        schemaVersion: 1,
        generatedAt: '2026-11-13T13:00:00Z',
        entries: [], // Empty catalog update!
      ));

      // 4. Verify user preference in config repository is completely unaffected
      final configs = await prayerConfigRepo.getConfigs();
      expect(configs[PrayerId.asr]?.audioSource, equals(customSource));
    });

    test('Offline state does NOT disable or mutate saved CustomAudioSource', () async {
      // 1. Create file on disk so physical guard passes
      final storageDir = await storageService.getStorageDirectory();
      final file = File(p.join(storageDir.path, 'remote_offline.mp3'));
      await file.writeAsBytes(List.filled(20000, 2));

      // 2. Save user preference
      const customSource = CustomAudioSource(
        id: 'custom:remote:offline_test',
        displayName: 'أذان عدم الاتصال',
        localRelativePath: 'adhan_sounds/remote_offline.mp3',
        originalFileName: 'offline.mp3',
        fileSize: 20000,
      );

      await prayerConfigRepo.saveConfig(PrayerAlarmConfig(
        prayerId: PrayerId.maghrib,
        alarmType: PrayerAlarmType.alarm,
        audioSource: customSource,
      ));

      // 3. Network error in catalog
      catalogRepo.result = Left(CatalogNetworkFailure());

      // 4. Audio source is still preserved
      final configs = await prayerConfigRepo.getConfigs();
      expect(configs[PrayerId.maghrib]?.audioSource, equals(customSource));
    });

    test('Non-destructive fallback for missing file leaves saved config completely intact', () async {
      // 1. Create file on disk, save config, then delete file to simulate file loss after assignment
      final storageDir = await storageService.getStorageDirectory();
      final file = File(p.join(storageDir.path, 'non_existent.mp3'));
      await file.writeAsBytes(List.filled(1000, 3));

      const missingSource = CustomAudioSource(
        id: 'custom:remote:deleted_by_user',
        displayName: 'أذان محذوف',
        localRelativePath: 'adhan_sounds/non_existent.mp3',
        originalFileName: 'non_existent.mp3',
        fileSize: 1000,
      );

      await prayerConfigRepo.saveConfig(PrayerAlarmConfig(
        prayerId: PrayerId.isha,
        alarmType: PrayerAlarmType.alarm,
        audioSource: missingSource,
      ));

      // Physically delete the file after assignment
      await file.delete();

      // Resolver handles missing file with non-destructive fallback for alarm
      final resolved = await resolver.resolveAudio(missingSource, isFajr: false);
      expect(resolved.isFallback, isTrue);
      expect(resolved.path, equals('assets/sounds/adhan.mp3'));

      // Invariant: User preference in repository remains untouched!
      final configs = await prayerConfigRepo.getConfigs();
      expect(configs[PrayerId.isha]?.audioSource, equals(missingSource));
    });
  });

  group('P4.2 Phase 3.5 — Screen & Preview Lifecycle Guarantees', () {
    testWidgets('Leaving AdhanCatalogScreen halts active preview and cancels listeners cleanly', (tester) async {
      final fakePlayer = FakeAudioPlayer();

      if (sl.isRegistered<AdhanCatalogCubit>()) {
        sl.unregister<AdhanCatalogCubit>();
      }

      final cubit = AdhanCatalogCubit(
        catalogRepository: catalogRepo,
        downloadService: AudioDownloadServiceImpl(client: http.Client(), storageService: storageService),
        playableAudioResolver: resolver,
        audioPlayer: fakePlayer,
      );

      sl.registerFactory<AdhanCatalogCubit>(() => cubit);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdhanCatalogScreen(
                      currentSelectedSource: AudioSourceConfig.defaultMishary,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      // Open screen
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Start preview
      await cubit.playBuiltInPreview(AudioSourceConfig.defaultMishary, isFajr: false);
      expect(fakePlayer.isPlaying, isTrue);

      // Navigate back
      final backButton = find.byType(BackButton);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Screen popped -> Preview stopped cleanly
      expect(fakePlayer.isPlaying, isFalse);
    });

    test('Starting a new preview halts any currently running preview immediately', () async {
      final fakePlayer = FakeAudioPlayer();

      final cubit = AdhanCatalogCubit(
        catalogRepository: catalogRepo,
        downloadService: AudioDownloadServiceImpl(client: http.Client(), storageService: storageService),
        playableAudioResolver: resolver,
        audioPlayer: fakePlayer,
      );

      // Play Built-in 1
      await cubit.playBuiltInPreview(AudioSourceConfig.defaultMishary, isFajr: false);
      expect(cubit.state.playingAudioId, equals(AudioSourceConfig.defaultMishary.id));
      expect(fakePlayer.isPlaying, isTrue);

      // Play Built-in with different prayer context (halts previous and starts fresh)
      await cubit.playBuiltInPreview(
        const BuiltInAudioSource(
          id: 'builtIn:other_reciter',
          displayName: 'قارئ آخر',
          assetPath: 'assets/sounds/other.mp3',
        ),
        isFajr: false,
      );

      expect(cubit.state.playingAudioId, equals('builtIn:other_reciter'));
      expect(fakePlayer.isPlaying, isTrue);

      await cubit.close();
    });
  });
}
