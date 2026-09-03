// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserProfileModelAdapter extends TypeAdapter<UserProfileModel> {
  @override
  final int typeId = 2;

  @override
  UserProfileModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserProfileModel(
      xp: fields[0] as int,
      level: fields[1] as int,
      currentStreak: fields[2] as int,
      bestStreak: fields[3] as int,
      lastZikrDate: fields[4] as DateTime?,
      badges: (fields[5] as List?)?.cast<BadgeModel>(),
      totalMisbaha: fields[6] as int,
    );
  }

  @override
  void write(BinaryWriter writer, UserProfileModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.xp)
      ..writeByte(1)
      ..write(obj.level)
      ..writeByte(2)
      ..write(obj.currentStreak)
      ..writeByte(3)
      ..write(obj.bestStreak)
      ..writeByte(4)
      ..write(obj.lastZikrDate)
      ..writeByte(5)
      ..write(obj.badges)
      ..writeByte(6)
      ..write(obj.totalMisbaha);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfileModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
