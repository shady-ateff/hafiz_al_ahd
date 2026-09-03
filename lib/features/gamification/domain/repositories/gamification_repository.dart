import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/gamification/data/models/user_profile_model.dart';
import 'package:hafiz_al_ahd/features/gamification/data/models/badge_model.dart';

abstract class GamificationRepository {
  Future<Either<Failure, void>> init();
  Future<Either<Failure, UserProfileModel>> getUserProfile();
  Future<Either<Failure, void>> saveUserProfile(UserProfileModel profile);
  Future<Either<Failure, void>> awardBadge(BadgeModel badge);
}
