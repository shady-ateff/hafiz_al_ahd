import 'package:dartz/dartz.dart';
import '../entities/surah_audio.dart';
import '../errors/quran_audio_failures.dart';
import '../repositories/base_quran_audio_repository.dart';

class GetSurahAudioUseCase {
  final BaseQuranAudioRepository repository;

  GetSurahAudioUseCase(this.repository);

  Future<Either<QuranAudioFailure, SurahAudio>> call({
    required int surahNumber,
    required String reciterId,
  }) {
    return repository.getSurahAudio(
      surahNumber: surahNumber,
      reciterId: reciterId,
    );
  }
}
