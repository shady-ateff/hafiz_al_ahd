import 'package:hive/hive.dart';
import 'badge_model.dart';

part 'user_profile_model.g.dart';

@HiveType(typeId: 2)
class UserProfileModel {
  @HiveField(0)
  int xp;

  @HiveField(1)
  int level;

  @HiveField(2)
  int currentStreak;

  @HiveField(3)
  int bestStreak;

  @HiveField(4)
  DateTime? lastZikrDate;

  @HiveField(5)
  List<BadgeModel> badges;

  @HiveField(6)
  int totalMisbaha;

  UserProfileModel({
    this.xp = 0,
    this.level = 1,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.lastZikrDate,
    List<BadgeModel>? badges,
    this.totalMisbaha = 0,
  }) : badges = badges ?? [];

  // Helper method to level up
  void addXp(int points) {
    xp += points;
    // Simple leveling logic: every 100 XP = 1 level
    level = (xp ~/ 100) + 1;
  }
}
