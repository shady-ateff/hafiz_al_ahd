import 'package:alarm/alarm.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Alarm.init();
  final fln = FlutterLocalNotificationsPlugin();

  const int fajrAlarmId = 999911;
  const int asrNotifId = 999912;
  const int maghribOffId = 999913;

  await Alarm.stop(fajrAlarmId);
  await Alarm.stop(asrNotifId);
  await Alarm.stop(maghribOffId);

  await fln.cancel(id: fajrAlarmId);
  await fln.cancel(id: asrNotifId);
  await fln.cancel(id: maghribOffId);

  // ignore: avoid_print
  print('[PHASE_P4_1_C_CLEANUP_COMPLETE]');

  runApp(
    Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: const Color(0xFF0D1B2A),
      ),
    ),
  );
}

