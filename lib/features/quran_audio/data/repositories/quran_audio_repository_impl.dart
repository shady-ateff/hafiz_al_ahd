import 'dart:io';
import 'package:dartz/dartz.dart';
import '../../domain/entities/audio_reciter.dart';
import '../../domain/entities/ayah_timing.dart';
import '../../domain/entities/playback_position.dart';
import '../../domain/entities/surah_audio.dart';
import '../../domain/errors/quran_audio_failures.dart';
import '../../domain/repositories/base_quran_audio_repository.dart';
import '../datasources/quran_audio_local_data_source.dart';
import '../datasources/quran_audio_remote_data_source.dart';
import '../models/playback_position_model.dart';

class QuranAudioRepositoryImpl implements BaseQuranAudioRepository {
  static AudioReciter get kDefaultFallbackReciter => AudioReciter.kDefaultReciter;
  static List<AudioReciter> get kDefaultFallbackReciters => AudioReciter.kDefaultReciters;

  final BaseQuranAudioRemoteDataSource remoteDataSource;
  final BaseQuranAudioLocalDataSource localDataSource;

  QuranAudioRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<Either<QuranAudioFailure, List<AudioReciter>>> getReciters({
    bool forceRefresh = false,
  }) async {
    // 1. Return cached reciters unless forced to refresh
    if (!forceRefresh) {
      final cached = await localDataSource.getCachedReciters();
      if (cached != null && cached.isNotEmpty) {
        return Right(List<AudioReciter>.from(cached));
      }
    }

    // 2. Fetch from remote
    try {
      final remoteReciters = await remoteDataSource.getChapterReciters();
      if (remoteReciters.isNotEmpty) {
        await localDataSource.cacheReciters(remoteReciters);
        return Right(List<AudioReciter>.from(remoteReciters));
      }

      // If remote returned empty but cache exists, fallback to cache
      final cached = await localDataSource.getCachedReciters();
      if (cached != null && cached.isNotEmpty) {
        return Right(List<AudioReciter>.from(cached));
      }

      return Right([kDefaultFallbackReciter]);
    } on SocketException {
      final cached = await localDataSource.getCachedReciters();
      if (cached != null && cached.isNotEmpty) {
        return Right(List<AudioReciter>.from(cached));
      }
      return Left(QuranAudioNetworkFailure());
    } catch (e) {
      final cached = await localDataSource.getCachedReciters();
      if (cached != null && cached.isNotEmpty) {
        return Right(List<AudioReciter>.from(cached));
      }
      return Left(QuranAudioNetworkFailure(message: 'فشل تحميل قائمة القراء: $e'));
    }
  }

  @override
  Future<Either<QuranAudioFailure, AudioReciter>> getSelectedReciter() async {
    final selectedId = await localDataSource.getSelectedReciterId();
    final recitersResult = await getReciters();

    return recitersResult.fold(
      (failure) => Right(kDefaultFallbackReciter),
      (reciters) {
        if (selectedId != null) {
          final match = reciters.where((r) => r.id == selectedId).toList();
          if (match.isNotEmpty) {
            return Right(match.first);
          }
        }
        return Right(reciters.isNotEmpty ? reciters.first : kDefaultFallbackReciter);
      },
    );
  }

  @override
  Future<Either<QuranAudioFailure, void>> setSelectedReciter(String reciterId) async {
    try {
      await localDataSource.setSelectedReciterId(reciterId);
      return const Right(null);
    } catch (e) {
      return Left(QuranAudioStorageFailure(message: 'فشل حفظ القارئ المختار: $e'));
    }
  }

  @override
  Future<Either<QuranAudioFailure, SurahAudio>> getSurahAudio({
    required int surahNumber,
    required String reciterId,
  }) async {
    // 1. Check local cache first
    final cached = await localDataSource.getCachedSurahAudio(surahNumber, reciterId);
    if (cached != null) {
      return Right(cached);
    }

    // 2. Query remote
    try {
      final remoteAudio = await remoteDataSource.getSurahAudio(
        surahNumber: surahNumber,
        reciterId: reciterId,
      );

      // Cache metadata & timings locally for future offline tracking
      await localDataSource.cacheSurahAudio(remoteAudio);
      return Right(remoteAudio);
    } on SocketException {
      return Left(QuranAudioNetworkFailure());
    } catch (e) {
      if (e.toString().contains('404')) {
        return Left(QuranAudioNotFoundFailure());
      }
      return Left(QuranAudioNetworkFailure(message: 'فشل تحميل بيانات صوت السورة: $e'));
    }
  }

  @override
  Future<Either<QuranAudioFailure, List<AyahTiming>>> getCachedAyahTimings({
    required int surahNumber,
    required String reciterId,
  }) async {
    final cached = await localDataSource.getCachedSurahAudio(surahNumber, reciterId);
    if (cached != null && cached.hasTimings) {
      return Right(cached.ayahTimings);
    }
    return Left(QuranAudioNotFoundFailure(message: 'توقيتات الآيات غير متوفرة محلياً'));
  }

  @override
  Future<Either<QuranAudioFailure, void>> savePlaybackPosition(
    PlaybackPosition position,
  ) async {
    try {
      final model = position is PlaybackPositionModel
          ? position
          : PlaybackPositionModel.fromEntity(position);
      await localDataSource.savePlaybackPosition(model);
      return const Right(null);
    } catch (e) {
      return Left(QuranAudioStorageFailure(message: 'فشل حفظ موضع التلاوة: $e'));
    }
  }

  @override
  Future<Either<QuranAudioFailure, PlaybackPosition?>> getLastPlaybackPosition() async {
    try {
      final pos = await localDataSource.getLastPlaybackPosition();
      return Right(pos);
    } catch (e) {
      return Left(QuranAudioStorageFailure(message: 'فشل استرجاع موضع التلاوة الأخير: $e'));
    }
  }
}
