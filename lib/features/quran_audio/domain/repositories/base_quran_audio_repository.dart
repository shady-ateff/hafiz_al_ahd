import 'package:dartz/dartz.dart';
import '../entities/audio_reciter.dart';
import '../entities/ayah_timing.dart';
import '../entities/playback_position.dart';
import '../entities/surah_audio.dart';
import '../errors/quran_audio_failures.dart';

/// Contract for managing Quran Audio remote metadata, reciters catalog,
/// Ayah timing lookups, and persistent user playback state.
abstract class BaseQuranAudioRepository {
  /// Fetches the list of available reciters, using local cache first unless [forceRefresh] is true.
  Future<Either<QuranAudioFailure, List<AudioReciter>>> getReciters({
    bool forceRefresh = false,
  });

  /// Retrieves the currently selected reciter, or a default fallback if none was chosen yet.
  Future<Either<QuranAudioFailure, AudioReciter>> getSelectedReciter();

  /// Persists the user's active reciter preference.
  Future<Either<QuranAudioFailure, void>> setSelectedReciter(String reciterId);

  /// Retrieves the complete audio track metadata (including Ayah timing intervals)
  /// for a specific Surah and reciter.
  Future<Either<QuranAudioFailure, SurahAudio>> getSurahAudio({
    required int surahNumber,
    required String reciterId,
  });

  /// Retrieves locally cached Ayah timing intervals for offline synchronization.
  Future<Either<QuranAudioFailure, List<AyahTiming>>> getCachedAyahTimings({
    required int surahNumber,
    required String reciterId,
  });

  /// Saves the user's current playback position for later restoration.
  Future<Either<QuranAudioFailure, void>> savePlaybackPosition(
    PlaybackPosition position,
  );

  /// Retrieves the last recorded playback position across application sessions.
  Future<Either<QuranAudioFailure, PlaybackPosition?>> getLastPlaybackPosition();
}
