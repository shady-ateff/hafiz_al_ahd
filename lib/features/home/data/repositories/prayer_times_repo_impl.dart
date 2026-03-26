import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/faluire.dart';
import 'package:hafiz_al_ahd/features/home/data/datasources/prayer_times_local_data_source.dart';
import 'package:adhan/adhan.dart'; // مكتبة الحسابات الفلكية
import 'package:hafiz_al_ahd/features/home/domain/entities/prayer_times_entity.dart';
import 'package:hafiz_al_ahd/features/home/domain/repositories/prayer_times_repo.dart';

class PrayerTimesRepoImpl implements PrayerTimesRepo {
  final PrayerTimesLocalDataSource localDataSource;

  PrayerTimesRepoImpl(this.localDataSource);

  @override
  Future<Either<Failure, PrayerTimesEntity>> getPrayerTimes({
    required double latitude,
    required double longitude,
    required DateTime date,
    String? city,
    String? country,
    String? method,
  }) async {
    try {
      final coordinates = Coordinates(latitude, longitude);
      final prayerTimesModel = await localDataSource.getPrayerTimes(
        coordinates: coordinates,
        date: date,
      );
      return Right(prayerTimesModel);
    } catch (e) {
      return Left(LocationFailure(message: e.toString()));
    }
  }
}
