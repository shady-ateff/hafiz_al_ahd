import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import '../entities/quran_page.dart';

abstract class BaseQuranRepository {
  /// جلب بيانات صفحة معينة (تتضمن الأسطر والنصوص)
  Future<Either<Failure, QuranPage>> getQuranPage(int pageNumber);
}
