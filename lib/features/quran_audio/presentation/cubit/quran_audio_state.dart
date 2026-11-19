import 'package:equatable/equatable.dart';
import '../../core/audio/quran_audio_player.dart';
import '../../domain/entities/audio_download.dart';
import '../../domain/entities/audio_highlight_state.dart';
import '../../domain/entities/audio_reciter.dart';
import '../../domain/entities/download_progress.dart';
import '../../domain/entities/surah_audio.dart';

/// State representation for the Quran Audio presentation subsystem.
///
/// **ARCHITECTURAL INVARIANTS**:
/// - Strictly decoupled from manual Mushaf text selection (`QuranCubit.selectedAyahId`).
/// - Audio highlighting is managed exclusively through [highlightState].
/// - Audio playback sources (Local vs Online Streaming) are indicated transparently via [isLocal].
class QuranAudioState extends Equatable {
  final List<AudioReciter> reciters;
  final AudioReciter? selectedReciter;
  final int? currentSurahNumber;
  final SurahAudio? currentSurahAudio;
  final QuranPlaybackStatus playbackStatus;
  final Duration currentPosition;
  final Duration totalDuration;
  final AudioHighlightState highlightState;
  final bool isLocal;
  final bool isLoadingReciters;
  final bool isLoadingAudio;
  final String? errorMessage;
  final bool isOfflineError;
  final double playbackSpeed;
  final Map<String, DownloadProgress> downloadProgressMap;

  const QuranAudioState({
    this.reciters = const [],
    this.selectedReciter,
    this.currentSurahNumber,
    this.currentSurahAudio,
    this.playbackStatus = QuranPlaybackStatus.idle,
    this.currentPosition = Duration.zero,
    this.totalDuration = Duration.zero,
    this.highlightState = AudioHighlightState.idle,
    this.isLocal = false,
    this.isLoadingReciters = false,
    this.isLoadingAudio = false,
    this.errorMessage,
    this.isOfflineError = false,
    this.playbackSpeed = 1.0,
    this.downloadProgressMap = const {},
  });

  bool get isPlaying => playbackStatus == QuranPlaybackStatus.playing;
  bool get isPaused => playbackStatus == QuranPlaybackStatus.paused;
  bool get isBuffering => playbackStatus == QuranPlaybackStatus.buffering;
  bool get isLoading => playbackStatus == QuranPlaybackStatus.loading || isLoadingAudio;
  bool get isCompleted => playbackStatus == QuranPlaybackStatus.completed;

  double get progressPercentage {
    if (totalDuration.inMilliseconds <= 0) return 0.0;
    final progress = currentPosition.inMilliseconds / totalDuration.inMilliseconds;
    return progress.clamp(0.0, 1.0);
  }

  DownloadProgress? getDownloadProgress(int surahNumber, String reciterId) {
    return downloadProgressMap['$reciterId:$surahNumber'];
  }

  AudioDownloadDisplayStatus getDownloadDisplayStatus(int surahNumber, String reciterId) {
    final progress = getDownloadProgress(surahNumber, reciterId);
    if (progress == null) return AudioDownloadDisplayStatus.notDownloaded;
    return AudioDownloadDisplayStatus.fromPersisted(progress.status);
  }

  QuranAudioState copyWith({
    List<AudioReciter>? reciters,
    AudioReciter? selectedReciter,
    int? currentSurahNumber,
    SurahAudio? currentSurahAudio,
    QuranPlaybackStatus? playbackStatus,
    Duration? currentPosition,
    Duration? totalDuration,
    AudioHighlightState? highlightState,
    bool? isLocal,
    bool? isLoadingReciters,
    bool? isLoadingAudio,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool clearTrack = false,
    bool? isOfflineError,
    double? playbackSpeed,
    Map<String, DownloadProgress>? downloadProgressMap,
  }) {
    return QuranAudioState(
      reciters: reciters ?? this.reciters,
      selectedReciter: selectedReciter ?? this.selectedReciter,
      currentSurahNumber: clearTrack ? null : (currentSurahNumber ?? this.currentSurahNumber),
      currentSurahAudio: clearTrack ? null : (currentSurahAudio ?? this.currentSurahAudio),
      playbackStatus: playbackStatus ?? this.playbackStatus,
      currentPosition: currentPosition ?? this.currentPosition,
      totalDuration: totalDuration ?? this.totalDuration,
      highlightState: highlightState ?? this.highlightState,
      isLocal: isLocal ?? this.isLocal,
      isLoadingReciters: isLoadingReciters ?? this.isLoadingReciters,
      isLoadingAudio: isLoadingAudio ?? this.isLoadingAudio,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      isOfflineError: isOfflineError ?? this.isOfflineError,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      downloadProgressMap: downloadProgressMap ?? this.downloadProgressMap,
    );
  }

  @override
  List<Object?> get props => [
        reciters,
        selectedReciter,
        currentSurahNumber,
        currentSurahAudio,
        playbackStatus,
        currentPosition,
        totalDuration,
        highlightState,
        isLocal,
        isLoadingReciters,
        isLoadingAudio,
        errorMessage,
        isOfflineError,
        playbackSpeed,
        downloadProgressMap,
      ];
}
