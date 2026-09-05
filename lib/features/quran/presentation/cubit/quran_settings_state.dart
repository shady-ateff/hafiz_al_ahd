import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class QuranSettingsState extends Equatable {
  final ThemeMode quranThemeMode;

  const QuranSettingsState({
    this.quranThemeMode = ThemeMode.light,
  });

  QuranSettingsState copyWith({
    ThemeMode? quranThemeMode,
  }) {
    return QuranSettingsState(
      quranThemeMode: quranThemeMode ?? this.quranThemeMode,
    );
  }

  @override
  List<Object> get props => [quranThemeMode];
}
