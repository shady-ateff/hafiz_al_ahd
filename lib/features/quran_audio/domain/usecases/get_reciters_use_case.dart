import 'package:dartz/dartz.dart';
import '../entities/audio_reciter.dart';
import '../errors/quran_audio_failures.dart';
import '../repositories/base_quran_audio_repository.dart';

class GetRecitersUseCase {
  final BaseQuranAudioRepository repository;

  GetRecitersUseCase(this.repository);

  Future<Either<QuranAudioFailure, List<AudioReciter>>> call({
    bool forceRefresh = false,
  }) {
    return repository.getReciters(forceRefresh: forceRefresh);
  }
}
