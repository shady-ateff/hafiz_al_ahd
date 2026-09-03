import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:hafiz_al_ahd/features/gamification/data/models/user_profile_model.dart';
import 'package:hafiz_al_ahd/features/gamification/data/models/badge_model.dart';
import 'package:hafiz_al_ahd/features/gamification/presentation/cubit/gamification_state.dart';

class GamificationCubit extends Cubit<GamificationState> {
  final GamificationRepository repository;

  GamificationCubit({required this.repository}) : super(GamificationInitial());

  Future<void> init() async {
    emit(GamificationLoading());
    final initResult = await repository.init();
    
    initResult.fold(
      (failure) => emit(GamificationError(message: failure.message)),
      (_) async {
        await _loadProfile();
      },
    );
  }

  Future<void> _loadProfile() async {
    final result = await repository.getUserProfile();
    result.fold(
      (failure) => emit(GamificationError(message: failure.message)),
      (profile) {
        _checkAndResetStreak(profile);
      },
    );
  }

  void _checkAndResetStreak(UserProfileModel profile) {
    if (profile.lastZikrDate != null) {
      final now = DateTime.now();
      final lastDate = profile.lastZikrDate!;
      final difference = DateTime(now.year, now.month, now.day).difference(DateTime(lastDate.year, lastDate.month, lastDate.day)).inDays;
      
      // If user missed a day
      if (difference > 1) {
        profile.currentStreak = 0;
        repository.saveUserProfile(profile);
      }
    }
    emit(GamificationLoaded(profile: profile));
  }

  Future<void> completeAzkarCategory(String categoryName) async {
    final currentState = state;
    if (currentState is GamificationLoaded || currentState is AchievementUnlockedState || currentState is LevelUpState) {
      UserProfileModel profile = _getProfileFromState();
      
      final now = DateTime.now();
      bool isNewDayForStreak = false;

      // Logic to increase streak only once per day when completing morning/evening azkar
      if (categoryName.contains('الصباح') || categoryName.contains('المساء')) {
        if (profile.lastZikrDate == null) {
          isNewDayForStreak = true;
        } else {
          final lastDate = profile.lastZikrDate!;
          final difference = DateTime(now.year, now.month, now.day).difference(DateTime(lastDate.year, lastDate.month, lastDate.day)).inDays;
          if (difference == 1) {
            isNewDayForStreak = true;
          } else if (difference > 1) {
            profile.currentStreak = 0;
            isNewDayForStreak = true;
          }
        }
      }

      if (isNewDayForStreak) {
        profile.currentStreak++;
        if (profile.currentStreak > profile.bestStreak) {
          profile.bestStreak = profile.currentStreak;
        }
        profile.lastZikrDate = now;
      }

      // Add XP for completing a category
      int previousLevel = profile.level;
      profile.addXp(50); // 50 XP per category

      await repository.saveUserProfile(profile);
      
      if (profile.level > previousLevel) {
        emit(LevelUpState(newLevel: profile.level, profile: profile));
        // Reset back to loaded after small delay to let UI handle it if needed
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      emit(GamificationLoaded(profile: profile));

      // Check Badges
      _checkBadges(profile, categoryName);
    }
  }

  Future<void> incrementMisbaha() async {
    final currentState = state;
    if (currentState is GamificationLoaded || currentState is AchievementUnlockedState || currentState is LevelUpState) {
      UserProfileModel profile = _getProfileFromState();
      
      profile.totalMisbaha++;

      // Give small XP for tasbeeh periodically
      if (profile.totalMisbaha % 100 == 0) {
        int prevLevel = profile.level;
        profile.addXp(10);
        await repository.saveUserProfile(profile);
        
        if (profile.level > prevLevel) {
          emit(LevelUpState(newLevel: profile.level, profile: profile));
          await Future.delayed(const Duration(milliseconds: 100));
        }
        emit(GamificationLoaded(profile: profile));
      }

      // Badge: 50,000 tasbeeh
      if (profile.totalMisbaha >= 50000 && !profile.badges.any((b) => b.id == 'misbaha_50k')) {
        _awardBadge(BadgeModel(
          id: 'misbaha_50k',
          name: 'الذاكرين والذاكرات',
          description: 'تجاوز 50,000 تسبيحة في المسبحة الإلكترونية',
          earnedAt: DateTime.now(),
        ), profile);
      }
    }
  }

  Future<void> _checkBadges(UserProfileModel profile, String categoryName) async {
    final now = DateTime.now();
    
    // Badge: "أهل الفجر" (Between Fajr and Sunrise, roughly 4 AM to 7 AM as an approximation or just morning azkar early)
    if (categoryName.contains('الصباح') && now.hour >= 4 && now.hour <= 7) {
      if (!profile.badges.any((b) => b.id == 'fajr_azkar')) {
        _awardBadge(BadgeModel(
          id: 'fajr_azkar',
          name: 'أهل الفجر',
          description: 'قراءة أذكار الصباح في وقت مبكر',
          earnedAt: now,
        ), profile);
      }
    }

    // Badge: "حافظ العهد" (30 Days streak)
    if (profile.currentStreak >= 30) {
      if (!profile.badges.any((b) => b.id == 'hafiz_30_days')) {
        _awardBadge(BadgeModel(
          id: 'hafiz_30_days',
          name: 'حافظ العهد',
          description: 'الالتزام بالأذكار لمدة 30 يوماً متتالية',
          earnedAt: now,
        ), profile);
      }
    }
    
    // Badge: "حصن الليل" (Sleeping azkar) - We'll assume a local counter or simple logic. For now, award it if read late night.
    if (categoryName.contains('النوم')) {
       // Ideally we need a counter for 7 days sleep azkar. For simplicity, let's say if streak > 7 and read sleep azkar.
       if (profile.currentStreak >= 7 && !profile.badges.any((b) => b.id == 'night_fortress')) {
         _awardBadge(BadgeModel(
          id: 'night_fortress',
          name: 'حصن الليل',
          description: 'المواظبة على أذكار النوم',
          earnedAt: now,
        ), profile);
       }
    }
  }

  Future<void> _awardBadge(BadgeModel badge, UserProfileModel profile) async {
    final result = await repository.awardBadge(badge);
    result.fold(
      (failure) => null,
      (_) {
        profile.badges.add(badge);
        emit(AchievementUnlockedState(badge: badge, profile: profile));
        // Return to normal loaded state after emission
        Future.delayed(const Duration(milliseconds: 100), () {
          emit(GamificationLoaded(profile: profile));
        });
      },
    );
  }

  UserProfileModel _getProfileFromState() {
    if (state is GamificationLoaded) {
      return (state as GamificationLoaded).profile;
    } else if (state is AchievementUnlockedState) {
      return (state as AchievementUnlockedState).profile;
    } else if (state is LevelUpState) {
      return (state as LevelUpState).profile;
    }
    return UserProfileModel();
  }
}
