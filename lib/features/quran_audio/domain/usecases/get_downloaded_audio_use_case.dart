import '../entities/audio_download.dart';
import '../repositories/base_audio_download_repository.dart';

class GetDownloadedAudioUseCase {
  final BaseAudioDownloadRepository repository;

  GetDownloadedAudioUseCase(this.repository);

  Future<List<AudioDownload>> call({String? reciterId}) {
    if (reciterId != null && reciterId.isNotEmpty) {
      return repository.getDownloadedSurahs(reciterId: reciterId);
    }
    return repository.getAllDownloadedRecords();
  }
}
