import 'package:hive/hive.dart';

part 'badge_model.g.dart';

@HiveType(typeId: 1)
class BadgeModel {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String description;

  @HiveField(3)
  final DateTime earnedAt;

  BadgeModel({
    required this.id,
    required this.name,
    required this.description,
    required this.earnedAt,
  });
}
