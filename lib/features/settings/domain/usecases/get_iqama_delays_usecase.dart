class GetIqamaDelaysUseCase {
  // مؤقتاً هنرجع الخريطة الثابتة دي
  // في التحديث الجاي، الدالة دي هتقرأ من الـ SharedPreferences 
  // وترجع الأرقام اللي اليوزر اختارها
  Map<String, int> execute() {
    return {
      'fajr': 25,
      'dhuhr': 15,
      'asr': 15,
      'maghrib': 10,
      'isha': 15,
    };
  }
}