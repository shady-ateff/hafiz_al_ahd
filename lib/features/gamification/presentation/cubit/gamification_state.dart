import 'package:equatable/equatable.dart';
import 'package:hafiz_al_ahd/features/gamification/data/models/user_profile_model.dart';
import 'package:hafiz_al_ahd/features/gamification/data/models/badge_model.dart';

abstract class GamificationState extends Equatable {
  const GamificationState();

  @override
  List<Object?> get props => [];
}

class GamificationInitial extends GamificationState {}

class GamificationLoading extends GamificationState {}

class GamificationLoaded extends GamificationState {
  final UserProfileModel profile;

  const GamificationLoaded({required this.profile});

  @override
  List<Object?> get props => [profile, profile.xp, profile.level, profile.badges.length, profile.currentStreak];
}

class GamificationError extends GamificationState {
  final String message;

  const GamificationError({required this.message});

  @override
  List<Object?> get props => [message];
}

class AchievementUnlockedState extends GamificationState {
  final BadgeModel badge;
  // We also pass the updated profile so UI can rebuild immediately after showing dialog
  final UserProfileModel profile;

  const AchievementUnlockedState({required this.badge, required this.profile});

  @override
  List<Object?> get props => [badge.id, profile];
}

class LevelUpState extends GamificationState {
  final int newLevel;
  final UserProfileModel profile;

  const LevelUpState({required this.newLevel, required this.profile});

  @override
  List<Object?> get props => [newLevel, profile];
}
