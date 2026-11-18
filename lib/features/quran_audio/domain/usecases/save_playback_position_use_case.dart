import 'package:dartz/dartz.dart';
import '../entities/playback_position.dart';
import '../errors/quran_audio_failures.dart';
import '../repositories/base_quran_audio_repository.dart';

class SavePlaybackPositionUseCase {
  final BaseQuranAudioRepository repository;

  SavePlaybackPositionUseCase(this.repository);

  Future<Either<QuranAudioFailure, void>> call(PlaybackPosition position) {
    return repository.savePlaybackPosition(position);
  }
}
