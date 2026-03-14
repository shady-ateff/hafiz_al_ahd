import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_state.dart';

const _kThemeModeKey = 'theme_mode';

class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit() : super(const ThemeState(ThemeMode.dark));

  /// Load persisted theme from SharedPreferences on app start
  Future<void> loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kThemeModeKey);
    if (saved == 'light') {
      emit(const ThemeState(ThemeMode.light));
    } else if (saved == 'system') {
      emit(const ThemeState(ThemeMode.system));
    } else {
      emit(const ThemeState(ThemeMode.dark));
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    emit(ThemeState(mode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, mode.name);
  }

  Future<void> toggleTheme() async {
    final newMode = state.themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    await setTheme(newMode);
  }
}
