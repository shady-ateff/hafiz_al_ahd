import 'package:dartz/dartz.dart';
import '../entities/playback_position.dart';
import '../errors/quran_audio_failures.dart';
import '../repositories/base_quran_audio_repository.dart';

class GetPlaybackPositionUseCase {
  final BaseQuranAudioRepository repository;

  GetPlaybackPositionUseCase(this.repository);

  Future<Either<QuranAudioFailure, PlaybackPosition?>> call() {
    return repository.getLastPlaybackPosition();
  }
}
