import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

class DesktopWindowService {
  
  // الدالة دي اللي هننادي عليها من الـ main
  static Future<void> initialize(List<String> args) async {
    // لو إحنا على موبايل، اخرج فوراً ومتعملش حاجة
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    // 1. تهيئة مدير النوافذ (Window Manager)
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(400, 800), // مقاس شاشة موبايل بالطول عشان يناسب تصميمك
      center: true,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'Hafiz Al Ahd',
    );

    // 2. فحص "كلمة السر" اللي جاية من الويندوز
    bool startHidden = args.contains('--hidden');

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (startHidden) {
        // لو الويندوز هو اللي فتح التطبيق في الـ Startup -> اخفيه
        await windowManager.hide();
      } else {
        // لو اليوزر فتحه بإيده دبل كليك -> اظهره
        await windowManager.show();
        await windowManager.focus();
      }
    });

    // 3. تهيئة الأيقونة اللي جنب الساعة
    await _setupSystemTray();
  }

  static Future<void> _setupSystemTray() async {
    // تحديد مسار الأيقونة (لازم تكون بصيغة ico للويندوز)
    await trayManager.setIcon('assets/app_icon_transparent.ico');
    
    // إنشاء القائمة اللي بتظهر لما تدوس كليك يمين على الأيقونة
    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show_app',
          label: 'إظهار التطبيق',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: 'إغلاق حافظ العهد',
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
  }
}