import 'package:shared_preferences/shared_preferences.dart';

class GetIqamaDelaysUseCase {
  Future<Map<String, int>> execute() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'fajr': prefs.getInt('iqama_fajr') ?? 25,
      'dhuhr': prefs.getInt('iqama_dhuhr') ?? 15,
      'asr': prefs.getInt('iqama_asr') ?? 15,
      'maghrib': prefs.getInt('iqama_maghrib') ?? 10,
      'isha': prefs.getInt('iqama_isha') ?? 15,
    };
  }
}
