import 'package:dartz/dartz.dart';
import '../errors/quran_audio_failures.dart';
import '../repositories/base_audio_download_repository.dart';

class DeleteDownloadUseCase {
  final BaseAudioDownloadRepository repository;

  DeleteDownloadUseCase(this.repository);

  Future<Either<QuranAudioFailure, void>> deleteSurah({
    required int surahNumber,
    required String reciterId,
  }) {
    return repository.deleteDownloadRecord(
      surahNumber: surahNumber,
      reciterId: reciterId,
    );
  }

  Future<Either<QuranAudioFailure, void>> deleteReciter({
    required String reciterId,
  }) {
    return repository.deleteReciterDownloads(reciterId: reciterId);
  }

  Future<Either<QuranAudioFailure, void>> deleteAll() {
    return repository.deleteAllDownloads();
  }
}
