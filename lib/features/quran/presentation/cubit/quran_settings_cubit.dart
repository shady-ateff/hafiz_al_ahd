import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'quran_settings_state.dart';

const _kQuranThemeModeKey = 'quran_theme_mode';

class QuranSettingsCubit extends Cubit<QuranSettingsState> {
  final SharedPreferences sharedPreferences;

  QuranSettingsCubit({required this.sharedPreferences}) : super(const QuranSettingsState()) {
    _loadSettings();
  }

  void _loadSettings() {
    final savedTheme = sharedPreferences.getString(_kQuranThemeModeKey);
    ThemeMode themeMode = ThemeMode.light;
    
    if (savedTheme == 'light') {
      themeMode = ThemeMode.light;
    } else if (savedTheme == 'dark') {
      themeMode = ThemeMode.dark;
    }

    emit(state.copyWith(quranThemeMode: themeMode));
  }

  Future<void> setQuranTheme(ThemeMode mode) async {
    emit(state.copyWith(quranThemeMode: mode));
    await sharedPreferences.setString(_kQuranThemeModeKey, mode.name);
  }
}
