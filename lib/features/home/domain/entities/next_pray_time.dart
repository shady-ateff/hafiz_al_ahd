class NextPrayerTime {
  final String name;
  final DateTime? time;
  final Duration remaining;
  final bool isNextPrayer;
  final bool isIqama;

  NextPrayerTime({
    required this.name,
    required this.time,
    required this.remaining,
    required this.isNextPrayer,
    required this.isIqama,
  });
}
