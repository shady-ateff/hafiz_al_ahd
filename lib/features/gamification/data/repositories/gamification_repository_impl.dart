import 'package:dartz/dartz.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/gamification/data/models/user_profile_model.dart';
import 'package:hafiz_al_ahd/features/gamification/data/models/badge_model.dart';
import 'package:hafiz_al_ahd/features/gamification/domain/repositories/gamification_repository.dart';

class GamificationRepositoryImpl implements GamificationRepository {
  static const String _boxName = 'gamification_box';
  static const String _profileKey = 'user_profile';

  @override
  Future<Either<Failure, void>> init() async {
    try {
      await Hive.initFlutter();
      Hive.registerAdapter(UserProfileModelAdapter());
      Hive.registerAdapter(BadgeModelAdapter());
      await Hive.openBox<UserProfileModel>(_boxName);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(message: 'فشل في تهيئة نظام التخزين المحلي'));
    }
  }

  @override
  Future<Either<Failure, UserProfileModel>> getUserProfile() async {
    try {
      final box = Hive.box<UserProfileModel>(_boxName);
      UserProfileModel? profile = box.get(_profileKey);
      
      if (profile == null) {
        profile = UserProfileModel();
        await box.put(_profileKey, profile);
      }
      
      return Right(profile);
    } catch (e) {
      return Left(CacheFailure(message: 'فشل في استرجاع بيانات المستخدم'));
    }
  }

  @override
  Future<Either<Failure, void>> saveUserProfile(UserProfileModel profile) async {
    try {
      final box = Hive.box<UserProfileModel>(_boxName);
      await box.put(_profileKey, profile);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(message: 'فشل في حفظ بيانات المستخدم'));
    }
  }

  @override
  Future<Either<Failure, void>> awardBadge(BadgeModel badge) async {
    try {
      final profileResult = await getUserProfile();
      return profileResult.fold(
        (failure) => Left(failure),
        (profile) async {
          // Check if badge already exists
          if (!profile.badges.any((b) => b.id == badge.id)) {
            profile.badges.add(badge);
            await saveUserProfile(profile);
          }
          return const Right(null);
        }
      );
    } catch (e) {
      return Left(CacheFailure(message: 'فشل في إضافة الوسام'));
    }
  }
}
