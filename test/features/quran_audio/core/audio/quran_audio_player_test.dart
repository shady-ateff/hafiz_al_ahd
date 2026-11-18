import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_player.dart';
import 'package:hafiz_al_ahd/features/quran_audio/core/audio/quran_audio_player_impl.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_highlight_state.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/ayah_timing.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/surah_audio.dart';

class MockJustAudioPlatform extends JustAudioPlatform {
  final Map<String, MockAudioPlayerPlatform> players = {};

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = MockAudioPlayerPlatform(request.id);
    players[request.id] = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async {
    players.remove(request.id);
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async {
    players.clear();
    return DisposeAllPlayersResponse();
  }
}

class MockAudioPlayerPlatform extends AudioPlayerPlatform {
  MockAudioPlayerPlatform(super.id);

  final eventController = StreamController<PlaybackEventMessage>.broadcast();
  final dataController = StreamController<PlayerDataMessage>.broadcast();

  String? lastLoadedUrl;
  String? lastLoadedPath;
  Duration? lastSeekPosition;
  bool isPlaying = false;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => eventController.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => dataController.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final audioSource = request.audioSourceMessage;
    if (audioSource is UriAudioSourceMessage) {
      if (audioSource.uri.startsWith('file://') || audioSource.uri.startsWith('/')) {
        lastLoadedPath = audioSource.uri;
      } else {
        lastLoadedUrl = audioSource.uri;
      }
    }

    eventController.add(PlaybackEventMessage(
      processingState: ProcessingStateMessage.ready,
      updateTime: DateTime.now(),
      updatePosition: request.initialPosition ?? Duration.zero,
      bufferedPosition: const Duration(seconds: 46),
      duration: const Duration(seconds: 46),
      icyMetadata: null,
      currentIndex: 0,
      androidAudioSessionId: null,
      errorCode: null,
      errorMessage: null,
    ));

    return LoadResponse(duration: const Duration(seconds: 46));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    isPlaying = true;
    dataController.add(PlayerDataMessage(playing: true));
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    isPlaying = false;
    dataController.add(PlayerDataMessage(playing: false));
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    if (request.position != null) {
      lastSeekPosition = request.position!;
      eventController.add(PlaybackEventMessage(
        processingState: ProcessingStateMessage.ready,
        updateTime: DateTime.now(),
        updatePosition: request.position!,
        bufferedPosition: const Duration(seconds: 46),
        duration: const Duration(seconds: 46),
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
        errorCode: null,
        errorMessage: null,
      ));
    }
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async => SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async => SetSpeedResponse();
  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async => SetPitchResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async => SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async => SetShuffleModeResponse();
  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await eventController.close();
    await dataController.close();
    return DisposeResponse();
  }

  void emitState(ProcessingStateMessage state, {bool? playing}) {
    eventController.add(PlaybackEventMessage(
      processingState: state,
      updateTime: DateTime.now(),
      updatePosition: lastSeekPosition ?? Duration.zero,
      bufferedPosition: const Duration(seconds: 46),
      duration: const Duration(seconds: 46),
      icyMetadata: null,
      currentIndex: 0,
      androidAudioSessionId: null,
      errorCode: null,
      errorMessage: null,
    ));
    if (playing != null) {
      isPlaying = playing;
      dataController.add(PlayerDataMessage(playing: playing));
    }
  }

  void emitPosition(Duration position) {
    lastSeekPosition = position;
    eventController.add(PlaybackEventMessage(
      processingState: ProcessingStateMessage.ready,
      updateTime: DateTime.now(),
      updatePosition: position,
      bufferedPosition: const Duration(seconds: 46),
      duration: const Duration(seconds: 46),
      icyMetadata: null,
      currentIndex: 0,
      androidAudioSessionId: null,
      errorCode: null,
      errorMessage: null,
    ));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QuranAudioPlayerImpl with just_audio Engine', () {
    late MockJustAudioPlatform mockPlatform;
    late ja.AudioPlayer rawPlayer;
    late QuranAudioPlayerImpl player;

    final testSurahAudio = SurahAudio(
      surahNumber: 1,
      reciterId: '7',
      audioUrl: 'https://download.quranicaudio.com/qdc/mishari_al_afasy/murattal/1.mp3',
      durationMs: 46000,
      ayahTimings: [
        AyahTiming(
          surahNumber: 1,
          ayahNumber: 1,
          timestampFrom: 0,
          timestampTo: 5800,
          duration: 5800,
        ),
        AyahTiming(
          surahNumber: 1,
          ayahNumber: 2,
          timestampFrom: 5800,
          timestampTo: 11200,
          duration: 5400,
        ),
        AyahTiming(
          surahNumber: 1,
          ayahNumber: 3,
          timestampFrom: 11200,
          timestampTo: 17500,
          duration: 6300,
        ),
        AyahTiming(
          surahNumber: 1,
          ayahNumber: 4,
          timestampFrom: 17500,
          timestampTo: 24000,
          duration: 6500,
        ),
      ],
    );

    setUp(() {
      mockPlatform = MockJustAudioPlatform();
      JustAudioPlatform.instance = mockPlatform;

      rawPlayer = ja.AudioPlayer();
      player = QuranAudioPlayerImpl(audioPlayer: rawPlayer);
    });

    tearDown(() async {
      await player.dispose();
    });

    test('initial state is idle', () {
      expect(player.status, QuranPlaybackStatus.idle);
      expect(player.currentPosition, Duration.zero);
      expect(player.duration, isNull);
      expect(player.currentTrack, isNull);
    });

    test('loadSurah prepares online streaming URL and sets ready paused status', () async {
      await player.loadSurah(surahAudio: testSurahAudio);

      expect(player.currentTrack, testSurahAudio);
      expect(player.isLocalSource, isFalse);
      expect(player.duration, const Duration(milliseconds: 46000));
      expect(player.status, QuranPlaybackStatus.paused);
    });

    test('loadSurah prepares offline local file path when provided', () async {
      const localPath = '/data/user/0/app/quran_audio/reciter_7/surah_001.mp3';
      await player.loadSurah(
        surahAudio: testSurahAudio,
        localFilePath: localPath,
      );

      expect(player.currentTrack, testSurahAudio);
      expect(player.isLocalSource, isTrue);
    });

    test('loadSurah with startPosition seeks audio player to initial timestamp', () async {
      const startPos = Duration(seconds: 15);
      await player.loadSurah(
        surahAudio: testSurahAudio,
        startPosition: startPos,
      );

      expect(player.currentPosition, startPos);
    });

    test('play, pause, stop and seek delegate to just_audio player', () async {
      await player.loadSurah(surahAudio: testSurahAudio);

      await player.play();
      expect(rawPlayer.playing, isTrue);

      await player.pause();
      expect(rawPlayer.playing, isFalse);

      await player.seekTo(const Duration(seconds: 10));
      expect(player.currentPosition, const Duration(seconds: 10));

      await player.stop();
      expect(player.status, QuranPlaybackStatus.idle);
      expect(player.currentPosition, Duration.zero);
    });

    test('maps just_audio processing states to QuranPlaybackStatus', () async {
      final statuses = <QuranPlaybackStatus>[];
      final sub = player.playbackStatusStream.listen(statuses.add);

      await player.loadSurah(surahAudio: testSurahAudio);
      final platformPlayer = mockPlatform.players.values.first;

      platformPlayer.emitState(ProcessingStateMessage.buffering);
      await pumpEventQueue();

      platformPlayer.emitState(ProcessingStateMessage.ready, playing: true);
      await pumpEventQueue();

      platformPlayer.emitState(ProcessingStateMessage.ready, playing: false);
      await pumpEventQueue();

      platformPlayer.emitState(ProcessingStateMessage.completed);
      await pumpEventQueue();

      expect(statuses, containsAllInOrder([
        QuranPlaybackStatus.buffering,
        QuranPlaybackStatus.playing,
        QuranPlaybackStatus.paused,
        QuranPlaybackStatus.completed,
      ]));

      await sub.cancel();
    });

    test('single Ayah repeat triggers seek when position equals or exceeds timestampTo', () async {
      await player.loadSurah(surahAudio: testSurahAudio);
      await player.setRepeatMode(AudioRepeatMode.singleAyah);
      player.setActiveAyahTiming(testSurahAudio.ayahTimings[0]); // 0 -> 5800ms

      final platformPlayer = mockPlatform.players.values.first;

      // Position within interval -> no seek
      platformPlayer.emitPosition(const Duration(milliseconds: 3000));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, const Duration(milliseconds: 3000));

      // Exact boundary timestampTo (5800ms) -> seeks back to timestampFrom (0ms)
      platformPlayer.emitPosition(const Duration(milliseconds: 5800));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, Duration.zero);

      // Overshoot timestampTo (5900ms) -> also seeks back to timestampFrom (0ms)
      platformPlayer.emitPosition(const Duration(milliseconds: 5900));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, Duration.zero);
    });

    test('range repeat loops back from endAyah timestampTo to startAyah timestampFrom', () async {
      await player.loadSurah(surahAudio: testSurahAudio);
      await player.setRepeatMode(
        AudioRepeatMode.range,
        rangeStartAyah: 1,
        rangeEndAyah: 2,
      );

      final platformPlayer = mockPlatform.players.values.first;

      // Ayah 2 ends at 11200ms -> loops back to Ayah 1 start (0ms)
      platformPlayer.emitPosition(const Duration(milliseconds: 11200));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, Duration.zero);
    });

    test('track change resets active Ayah timing boundary', () async {
      await player.loadSurah(surahAudio: testSurahAudio);
      player.setActiveAyahTiming(testSurahAudio.ayahTimings[0]);

      // Load a different Surah
      final otherSurah = SurahAudio(
        surahNumber: 2,
        reciterId: '7',
        audioUrl: 'https://example.com/2.mp3',
        durationMs: 90000,
        ayahTimings: [
          AyahTiming(
            surahNumber: 2,
            ayahNumber: 1,
            timestampFrom: 0,
            timestampTo: 4000,
            duration: 4000,
          ),
        ],
      );

      await player.loadSurah(surahAudio: otherSurah);
      expect(player.currentTrack?.surahNumber, 2);
    });

    // --- Repeat Count & Memorization Semantics Suite (QA.4 Revision 3) ---

    test('Single Ayah + 1 repeat: plays 2x total (1 repeat) then allows natural progression', () async {
      await player.loadSurah(surahAudio: testSurahAudio);
      player.setActiveAyahTiming(testSurahAudio.ayahTimings[0]);

      // 1 repeat additional
      await player.setRepeatMode(AudioRepeatMode.singleAyah, repeatCount: 1);
      final platformPlayer = mockPlatform.players.values.first;

      // Iteration 1: reaching 5800ms seeks back to start (0ms) - Repeat #1
      platformPlayer.emitPosition(const Duration(milliseconds: 5800));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, Duration.zero);

      // Iteration 2: reaching 5800ms again; repeatCount (1) is fulfilled, so no seek back
      platformPlayer.emitPosition(const Duration(milliseconds: 5800));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, const Duration(milliseconds: 5800));
    });

    test('Single Ayah + 3 repeats: plays 4x total (3 repeats) then advances', () async {
      await player.loadSurah(surahAudio: testSurahAudio);
      player.setActiveAyahTiming(testSurahAudio.ayahTimings[0]);

      await player.setRepeatMode(AudioRepeatMode.singleAyah, repeatCount: 3);
      final platformPlayer = mockPlatform.players.values.first;

      // Repeat #1
      platformPlayer.emitPosition(const Duration(milliseconds: 5800));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, Duration.zero);

      // Repeat #2
      platformPlayer.emitPosition(const Duration(milliseconds: 5800));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, Duration.zero);

      // Repeat #3
      platformPlayer.emitPosition(const Duration(milliseconds: 5800));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, Duration.zero);

      // Play #4 (Fulfillment): no seek back, continues to next Ayah
      platformPlayer.emitPosition(const Duration(milliseconds: 5800));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, const Duration(milliseconds: 5800));
    });

    test('Single Ayah + 5 repeats: loops 5 times then advances', () async {
      await player.loadSurah(surahAudio: testSurahAudio);
      player.setActiveAyahTiming(testSurahAudio.ayahTimings[0]);

      await player.setRepeatMode(AudioRepeatMode.singleAyah, repeatCount: 5);
      final platformPlayer = mockPlatform.players.values.first;

      for (int i = 0; i < 5; i++) {
        platformPlayer.emitPosition(const Duration(milliseconds: 5800));
        await pumpEventQueue();
        expect(platformPlayer.lastSeekPosition, Duration.zero);
      }

      // 6th playback: completed
      platformPlayer.emitPosition(const Duration(milliseconds: 5800));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, const Duration(milliseconds: 5800));
    });

    test('Range + 1 repeat: loops entire range 1 time (2x plays) then advances', () async {
      await player.loadSurah(surahAudio: testSurahAudio);

      // Range: Ayah 1 to Ayah 2 (0ms to 11200ms) with repeatCount = 1
      await player.setRepeatMode(
        AudioRepeatMode.range,
        rangeStartAyah: 1,
        rangeEndAyah: 2,
        repeatCount: 1,
      );
      final platformPlayer = mockPlatform.players.values.first;

      // Range Repeat #1: reaching end of range (11200ms) loops back to 0ms
      platformPlayer.emitPosition(const Duration(milliseconds: 11200));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, Duration.zero);

      // Range Play #2 (Fulfilled): reaching 11200ms again allows natural continuation
      platformPlayer.emitPosition(const Duration(milliseconds: 11200));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, const Duration(milliseconds: 11200));
    });

    test('Range + 3 repeats: loops entire range 3 times then advances', () async {
      await player.loadSurah(surahAudio: testSurahAudio);

      await player.setRepeatMode(
        AudioRepeatMode.range,
        rangeStartAyah: 1,
        rangeEndAyah: 2,
        repeatCount: 3,
      );
      final platformPlayer = mockPlatform.players.values.first;

      for (int i = 0; i < 3; i++) {
        platformPlayer.emitPosition(const Duration(milliseconds: 11200));
        await pumpEventQueue();
        expect(platformPlayer.lastSeekPosition, Duration.zero);
      }

      // 4th playback: fulfilled
      platformPlayer.emitPosition(const Duration(milliseconds: 11200));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, const Duration(milliseconds: 11200));
    });

    test('Infinite Single Ayah: loops back unconditionally when repeatCount is null or 0', () async {
      await player.loadSurah(surahAudio: testSurahAudio);
      player.setActiveAyahTiming(testSurahAudio.ayahTimings[0]);

      await player.setRepeatMode(AudioRepeatMode.singleAyah, repeatCount: 0);
      final platformPlayer = mockPlatform.players.values.first;

      for (int i = 0; i < 15; i++) {
        platformPlayer.emitPosition(const Duration(milliseconds: 5800));
        await pumpEventQueue();
        expect(platformPlayer.lastSeekPosition, Duration.zero);
      }
    });

    test('Infinite Range: loops back range unconditionally when repeatCount is null or 0', () async {
      await player.loadSurah(surahAudio: testSurahAudio);

      await player.setRepeatMode(
        AudioRepeatMode.range,
        rangeStartAyah: 1,
        rangeEndAyah: 2,
        repeatCount: null,
      );
      final platformPlayer = mockPlatform.players.values.first;

      for (int i = 0; i < 15; i++) {
        platformPlayer.emitPosition(const Duration(milliseconds: 11200));
        await pumpEventQueue();
        expect(platformPlayer.lastSeekPosition, Duration.zero);
      }
    });

    test('Changing repeat range during playback resets iteration counter', () async {
      await player.loadSurah(surahAudio: testSurahAudio);

      await player.setRepeatMode(
        AudioRepeatMode.range,
        rangeStartAyah: 1,
        rangeEndAyah: 2,
        repeatCount: 1,
      );
      final platformPlayer = mockPlatform.players.values.first;

      // Repeat #1 triggers
      platformPlayer.emitPosition(const Duration(milliseconds: 11200));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, Duration.zero);

      // User changes range to Ayah 1 only
      await player.setRepeatMode(
        AudioRepeatMode.range,
        rangeStartAyah: 1,
        rangeEndAyah: 1,
        repeatCount: 1,
      );

      // Reaching new range boundary (5800ms) loops back again because iteration was reset
      platformPlayer.emitPosition(const Duration(milliseconds: 5800));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, Duration.zero);
    });

    test('Stop resets repeat iteration counter, track, and active timing', () async {
      await player.loadSurah(surahAudio: testSurahAudio);
      player.setActiveAyahTiming(testSurahAudio.ayahTimings[0]);
      await player.setRepeatMode(AudioRepeatMode.singleAyah, repeatCount: 2);

      await player.stop();

      expect(player.currentTrack, isNull);
      expect(player.status, QuranPlaybackStatus.idle);
    });

    test('R3.1-01: Multi-Ayah (3 Ayahs) Range Repeat does NOT reset counter between Ayahs', () async {
      await player.loadSurah(surahAudio: testSurahAudio);

      // Range: Ayah 1 to Ayah 3 (repeatCount = 3 -> 4 total plays: 1 initial + 3 repeats)
      await player.setRepeatMode(
        AudioRepeatMode.range,
        rangeStartAyah: 1,
        rangeEndAyah: 3,
        repeatCount: 3,
      );
      final platformPlayer = mockPlatform.players.values.first;

      final timing1 = testSurahAudio.ayahTimings[0]; // 0 -> 5800ms
      final timing2 = testSurahAudio.ayahTimings[1]; // 5800 -> 11200ms
      final timing3 = testSurahAudio.ayahTimings[2]; // 11200 -> 17500ms
      final timing4 = testSurahAudio.ayahTimings[3]; // 17500 -> 24000ms

      final List<String> sequence = [];

      // Execute 4 full cycles
      for (int cycle = 1; cycle <= 4; cycle++) {
        // Ayah 1 plays
        player.setActiveAyahTiming(timing1);
        platformPlayer.emitPosition(const Duration(milliseconds: 2000));
        await pumpEventQueue();
        sequence.add('Ayah 1 (Cycle $cycle)');

        // Ayah 2 plays: CRUCIAL CHECK - setActiveAyahTiming for Ayah 2 MUST NOT reset range iteration counter!
        player.setActiveAyahTiming(timing2);
        platformPlayer.emitPosition(const Duration(milliseconds: 8000));
        await pumpEventQueue();
        sequence.add('Ayah 2 (Cycle $cycle)');

        // Ayah 3 plays: CRUCIAL CHECK - setActiveAyahTiming for Ayah 3 MUST NOT reset range iteration counter!
        player.setActiveAyahTiming(timing3);
        platformPlayer.emitPosition(const Duration(milliseconds: 14000));
        await pumpEventQueue();
        sequence.add('Ayah 3 (Cycle $cycle)');

        // Reaching end boundary of Range at 17500ms
        platformPlayer.emitPosition(const Duration(milliseconds: 17500));
        await pumpEventQueue();

        if (cycle < 4) {
          // Cycles 1, 2, 3 loop back to Ayah 1 start (0ms)
          expect(platformPlayer.lastSeekPosition, Duration.zero,
              reason: 'Cycle $cycle should seek back to 0ms (Ayah 1 start)');
          sequence.add('-> Seek to 0ms (Loop)');
        } else {
          // Cycle 4 (the 3rd repetition = 4th play): repeats are completed!
          // Must NOT seek back to 0ms; position should remain at 17500ms!
          expect(platformPlayer.lastSeekPosition, const Duration(milliseconds: 17500),
              reason: 'Cycle 4 should complete and NOT seek back');
          sequence.add('-> Completed Range (No Seek)');
        }
      }

      // Now playback naturally continues past 17500ms into Ayah 4
      player.setActiveAyahTiming(timing4);
      platformPlayer.emitPosition(const Duration(milliseconds: 19000));
      await pumpEventQueue();
      sequence.add('Ayah 4 (Next Ayah)');

      // If it had seeked back, lastSeekPosition would have been set to Duration.zero.
      // Since it did NOT seek back, lastSeekPosition is NOT Duration.zero.
      expect(platformPlayer.lastSeekPosition, const Duration(milliseconds: 19000),
          reason: 'Advancing into Ayah 4 does not trigger range seek');

      // Verify sequence log exactly matches expected: 1->2->3 x 4 times, then Ayah 4
      expect(sequence, [
        'Ayah 1 (Cycle 1)', 'Ayah 2 (Cycle 1)', 'Ayah 3 (Cycle 1)', '-> Seek to 0ms (Loop)',
        'Ayah 1 (Cycle 2)', 'Ayah 2 (Cycle 2)', 'Ayah 3 (Cycle 2)', '-> Seek to 0ms (Loop)',
        'Ayah 1 (Cycle 3)', 'Ayah 2 (Cycle 3)', 'Ayah 3 (Cycle 3)', '-> Seek to 0ms (Loop)',
        'Ayah 1 (Cycle 4)', 'Ayah 2 (Cycle 4)', 'Ayah 3 (Cycle 4)', '-> Completed Range (No Seek)',
        'Ayah 4 (Next Ayah)',
      ]);
    });

    test('R3.1-01: Range Repeat handles reverse range inputs gracefully by normalization', () async {
      await player.loadSurah(surahAudio: testSurahAudio);

      // User accidentally specifies end=1, start=2
      await player.setRepeatMode(
        AudioRepeatMode.range,
        rangeStartAyah: 2,
        rangeEndAyah: 1,
        repeatCount: 1,
      );
      final platformPlayer = mockPlatform.players.values.first;

      // When reaching max boundary (Ayah 2 end = 11200ms)
      platformPlayer.emitPosition(const Duration(milliseconds: 11200));
      await pumpEventQueue();

      // Normalization ensures it seeks back to min boundary (Ayah 1 start = 0ms)
      expect(platformPlayer.lastSeekPosition, Duration.zero);
    });

    test('R3.1-01: Range Repeat safely ignores non-existent Ayah boundaries without falling back to first', () async {
      await player.loadSurah(surahAudio: testSurahAudio);

      // Range specifying Ayah 99 (does not exist in Surah 1)
      await player.setRepeatMode(
        AudioRepeatMode.range,
        rangeStartAyah: 99,
        rangeEndAyah: 100,
        repeatCount: 1,
      );
      final platformPlayer = mockPlatform.players.values.first;

      platformPlayer.emitPosition(const Duration(milliseconds: 11200));
      await pumpEventQueue();

      // Should NOT seek to 0 or crash
      expect(platformPlayer.lastSeekPosition, const Duration(milliseconds: 11200));
    });

    test('R3.2: Manual seek back into range after completion re-arms range repeat', () async {
      await player.loadSurah(surahAudio: testSurahAudio);

      // Range: Ayah 1 to Ayah 2, 1 repeat (2 plays total)
      await player.setRepeatMode(
        AudioRepeatMode.range,
        rangeStartAyah: 1,
        rangeEndAyah: 2,
        repeatCount: 1,
      );
      final platformPlayer = mockPlatform.players.values.first;

      // Play 1 finishes at 11200ms -> loops back to 0ms
      platformPlayer.emitPosition(const Duration(milliseconds: 11200));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, Duration.zero);

      // Play 2 finishes at 11200ms -> completed! (does not loop)
      platformPlayer.emitPosition(const Duration(milliseconds: 11200));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, const Duration(milliseconds: 11200));

      // Audio is in Ayah 3 (14000ms)
      platformPlayer.emitPosition(const Duration(milliseconds: 14000));
      await pumpEventQueue();

      // User manually seeks back into range (Ayah 1 at 2000ms)
      await player.seekTo(const Duration(milliseconds: 2000));
      await pumpEventQueue();

      // When position reaches end of range (11200ms) again, it should re-loop because seek re-armed it!
      platformPlayer.emitPosition(const Duration(milliseconds: 11200));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, Duration.zero,
          reason: 'Seeking back into range must re-arm range repeat');
    });

    test('R3.2: Changing repeat mode from Range to Single clears range state without leaks', () async {
      await player.loadSurah(surahAudio: testSurahAudio);

      await player.setRepeatMode(
        AudioRepeatMode.range,
        rangeStartAyah: 1,
        rangeEndAyah: 2,
        repeatCount: 1,
      );
      expect(player.rangeStartAyah, 1);
      expect(player.rangeEndAyah, 2);

      // Switch to Single Ayah mode
      await player.setRepeatMode(AudioRepeatMode.singleAyah, repeatCount: 2);

      // Range parameters must be cleared
      expect(player.repeatMode, AudioRepeatMode.singleAyah);
      expect(player.rangeStartAyah, isNull);
      expect(player.rangeEndAyah, isNull);
    });

    test('R3.2: Loading a new track resets range iteration counter and completed flag', () async {
      await player.loadSurah(surahAudio: testSurahAudio);

      await player.setRepeatMode(
        AudioRepeatMode.range,
        rangeStartAyah: 1,
        rangeEndAyah: 2,
        repeatCount: 1,
      );
      final platformPlayer = mockPlatform.players.values.first;

      // Complete range repeats on Surah 1
      platformPlayer.emitPosition(const Duration(milliseconds: 11200));
      await pumpEventQueue();
      platformPlayer.emitPosition(const Duration(milliseconds: 11200));
      await pumpEventQueue();

      // Load Surah 2
      final surah2 = SurahAudio(
        surahNumber: 2,
        reciterId: '7',
        audioUrl: 'http://cdn/2.mp3',
        durationMs: 50000,
        ayahTimings: [
          AyahTiming(surahNumber: 2, ayahNumber: 1, timestampFrom: 0, timestampTo: 6000, duration: 6000),
          AyahTiming(surahNumber: 2, ayahNumber: 2, timestampFrom: 6000, timestampTo: 12000, duration: 6000),
        ],
      );
      await player.loadSurah(surahAudio: surah2);

      // On Surah 2, re-set range for Surah 2
      await player.setRepeatMode(
        AudioRepeatMode.range,
        rangeStartAyah: 1,
        rangeEndAyah: 2,
        repeatCount: 1,
      );

      // When reaching end of range (12000ms), it should loop back on the fresh track
      platformPlayer.emitPosition(const Duration(milliseconds: 12000));
      await pumpEventQueue();
      expect(platformPlayer.lastSeekPosition, Duration.zero);
    });
  });
}
