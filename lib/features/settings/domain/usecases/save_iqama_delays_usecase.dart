import 'package:shared_preferences/shared_preferences.dart';

class SaveIqamaDelaysUseCase {
  Future<void> execute(Map<String, int> delays) async {
    final prefs = await SharedPreferences.getInstance();
    for (var entry in delays.entries) {
      await prefs.setInt('iqama_${entry.key}', entry.value);
    }
  }
}
