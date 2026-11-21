import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import '../../domain/usecases/get_surah_audio_use_case.dart';
import '../../domain/usecases/save_playback_position_use_case.dart';
import 'quran_audio_handler.dart';
import 'quran_audio_player.dart';

/// Manages the one-time, lifecycle-safe initialization of [AudioService] and [QuranAudioHandler].
///
/// **ARCHITECTURAL GUARANTEES**:
/// - Singleton & Concurrency Safety: All concurrent requests share the exact same [Future].
/// - Resilient Error Handling: On initialization failure, the cached Future is cleared,
///   enabling clean retries without permanent lockouts.
/// - DI Compatibility: Returns the exact [QuranAudioHandler] registered into the Service Locator.
/// - Test Isolation: In headless test environments, bypasses platform channels via `isTestMode: true`.
class QuranAudioServiceInitializer {
  static QuranAudioHandler? _handler;
  static Future<QuranAudioHandler>? _initializationFuture;

  @visibleForTesting
  static Future<QuranAudioHandler> Function()? customInitializer;

  /// Initializes the system-wide [AudioService] and returns the singleton [QuranAudioHandler].
  static Future<QuranAudioHandler> initialize({
    required QuranAudioPlayer player,
    GetSurahAudioUseCase? getSurahAudioUseCase,
    SavePlaybackPositionUseCase? savePlaybackPositionUseCase,
    AudioSession? audioSession,
    bool isTestMode = false,
  }) async {
    if (_handler != null) {
      return _handler!;
    }

    final future = _initializationFuture ??= _initializeInternal(
      player: player,
      getSurahAudioUseCase: getSurahAudioUseCase,
      savePlaybackPositionUseCase: savePlaybackPositionUseCase,
      audioSession: audioSession,
      isTestMode: isTestMode,
    );

    try {
      final handler = await future;
      _handler = handler;
      return handler;
    } catch (_) {
      // Concurrency guard: Only nullify if _initializationFuture is still identical
      // to this failed future. Prevents wiping a newer retry attempt initiated by
      // a concurrent caller.
      if (identical(_initializationFuture, future)) {
        _initializationFuture = null;
      }
      rethrow;
    }
  }

  static Future<QuranAudioHandler> _initializeInternal({
    required QuranAudioPlayer player,
    GetSurahAudioUseCase? getSurahAudioUseCase,
    SavePlaybackPositionUseCase? savePlaybackPositionUseCase,
    AudioSession? audioSession,
    required bool isTestMode,
  }) async {
    if (customInitializer != null) {
      return await customInitializer!();
    }

    if (isTestMode) {
      return QuranAudioHandler(
        player: player,
        getSurahAudioUseCase: getSurahAudioUseCase,
        savePlaybackPositionUseCase: savePlaybackPositionUseCase,
        audioSession: audioSession,
      );
    } else {
      return await AudioService.init(
        builder: () => QuranAudioHandler(
          player: player,
          getSurahAudioUseCase: getSurahAudioUseCase,
          savePlaybackPositionUseCase: savePlaybackPositionUseCase,
          audioSession: audioSession,
        ),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.shadyatef.hafiz_alahd.audio',
          androidNotificationChannelName: 'تلاوة القرآن الكريم',
          androidNotificationChannelDescription:
              'تشغيل تلاوات القرآن الكريم وإشعارات التحكم بالصوت',
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: true,
        ),
      );
    }
  }

  /// Gets the currently initialized handler if available.
  static QuranAudioHandler? get currentHandler => _handler;

  @visibleForTesting
  static void resetForTesting() {
    _handler = null;
    _initializationFuture = null;
    customInitializer = null;
  }
}
