import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import '../entities/quran_page.dart';
import '../repositories/base_quran_repository.dart';

class GetQuranPageUseCase {
  final BaseQuranRepository repository;

  GetQuranPageUseCase(this.repository);

  Future<Either<Failure, QuranPage>> call(int pageNumber) async {
    return await repository.getQuranPage(pageNumber);
  }
}
