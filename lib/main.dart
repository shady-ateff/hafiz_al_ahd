import 'package:flutter/material.dart';
import 'package:hafiz_al_ahd/app/view/app.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

late SharedPreferences pref;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WakelockPlus.enable(); // Keep the screen awake
  HijriCalendar.setLocal("ar"); // Set Hijri calendar locale to Arabic
  pref = await SharedPreferences.getInstance();
  runApp(App(sharedPreferences: pref));
}
