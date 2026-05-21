import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/utils/app_permission.dart';
import 'package:hafiz_al_ahd/features/main/presentation/screens/main_screen.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:auto_start_flutter/auto_start_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/onboarding/presentation/cubit/onboarding_cubit.dart';
import 'package:hafiz_al_ahd/features/onboarding/presentation/cubit/onboarding_state.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  bool _isRequesting = false;

  static const _gold = AppColors.lightGold;
  static const _darkBg = AppColors.deepBackground;
  static const _surfaceBg = AppColors.primaryBlack;

  List<_OnboardingPageData> _pages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializePages();
  }

  Future<void> _initializePages() async {
    final basePages = <_OnboardingPageData>[
      const _OnboardingPageData(
        permissionType: PermissionType.location,
        icon: Icons.explore,
        title: 'دقة المواقيت',
        body: 'لضمان دقة مواقيت الصلاة أينما كنت، نحتاج لمعرفة موقعك الجغرافي.',
        buttonText: 'السماح بالموقع',
        settingsHint: 'الموقع الجغرافي',
      ),
      const _OnboardingPageData(
        permissionType: PermissionType.notification,
        icon: Icons.notifications_active,
        title: 'التنبيهات والأذان',
        body: 'لا تفوت صلاتك. اسمح لنا بإرسال إشعار لك في وقت الأذان بالضبط.',
        buttonText: 'تفعيل الإشعارات',
        settingsHint: 'الإشعارات',
      ),
      const _OnboardingPageData(
        permissionType: PermissionType.exactAlarm,
        icon: Icons.alarm,
        title: 'دقة الأذان في الخلفية',
        body:
            'لكي يرفع الأذان في وقته بالثانية دون تأخير من نظام أندرويد، نحتاج لصلاحية "المنبه الدقيق".',
        buttonText: 'تفعيل المنبه الدقيق',
        settingsHint: 'المنبه الدقيق',
      ),
      const _OnboardingPageData(
        permissionType: PermissionType.batteryOptimization,
        icon: Icons.battery_saver,
        title: 'التحديث المستمر',
        body:
            'لضمان تحديث العداد والويدجت على الشاشة الرئيسية بشكل مستمر، يرجى استثناء التطبيق من قيود توفير البطارية.',
        buttonText: 'استثناء من البطارية',
        settingsHint: 'استثناء البطارية',
      ),
    ];

    try {
      final available = await isAutoStartAvailable;
      if (available == true) {
        basePages.add(const _OnboardingPageData(
          permissionType: PermissionType.autoStart,
          icon: Icons.rocket_launch,
          title: 'التشغيل التلقائي',
          body: 'يجب تفعيل (التشغيل التلقائي / Auto Start) لضمان عمل الأذان عند إغلاق التطبيق بالكامل.',
          buttonText: 'تفعيل التشغيل التلقائي',
          settingsHint: 'التشغيل التلقائي',
        ));
      }
    } catch (e) {
      // Ignore if error fetching autostart status
    }

    bool isXiaomi = false;
    if (Platform.isAndroid) {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      String manufacturer = androidInfo.manufacturer.toLowerCase();
      if (manufacturer.contains('xiaomi') ||
          manufacturer.contains('poco') ||
          manufacturer.contains('redmi')) {
        isXiaomi = true;
      }
    }

    if (isXiaomi) {
      basePages.add(const _OnboardingPageData(
        permissionType: PermissionType.xiaomiCustom,
        icon: Icons.phonelink_setup,
        title: 'إعدادات شاومي الخاصة',
        body: 'لضمان عمل الأذان وإضاءة الشاشة وقت الصلاة، يرجى تفعيل (الظهور على شاشة القفل) و(فتح نوافذ جديدة في الخلفية).',
        buttonText: 'فتح إعدادات شاومي',
        settingsHint: 'إعدادات شاومي',
      ));
    }

    final prefs = await SharedPreferences.getInstance();
    final List<_OnboardingPageData> pendingPages = [];
    
    for (var page in basePages) {
      if (!(prefs.getBool('onboarding_step_${page.permissionType.name}') ?? false)) {
        pendingPages.add(page);
      }
    }

    if (mounted) {
      setState(() {
        _pages = pendingPages;
        _isLoading = false;
      });
    }
  }

  void _goToMainScreen() {
    ScaffoldMessenger.of(context).clearSnackBars();
    
    // 👈 بعد ما خدنا الصلاحيات، نكلم الكيوبت عشان يجيب المواقيت ويجدول الإشعارات لأنه فشل في أول فتحة للتطبيق بسبب نقص الصلاحيات
    context.read<PrayerTimesCubit>().fetchPrayerTimesByLocation();    
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
  }

  Future<void> _onButtonPressed(OnboardingCubit cubit) async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);

    final result = await cubit.requestCurrentPermission();

    if (!mounted) return;
    setState(() => _isRequesting = false);

    switch (result) {
      case PermissionResult.granted:
        _advancePage(cubit);
        break;

      case PermissionResult.permanentlyDenied:
        // الرفض النهائي - نعرض Dialog شيك بدلاً من الطرد للإعدادات
        if (!mounted) return;
        _showPermanentlyDeniedDialog(cubit);
        break;

      case PermissionResult.denied:
        // الرفض العادي - SnackBar مع زر تخطي
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _surfaceBg,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 120, left: 16, right: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: Text(
              'تم رفض الصلاحية. يمكنك تفعيلها لاحقاً من إعدادات الهاتف.',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
            action: SnackBarAction(
              label: 'تخطي',
              textColor: _gold,
              onPressed: () => _advancePage(cubit),
            ),
            duration: const Duration(seconds: 10),
          ),
        );
        break;
    }
  }

  /// Dialog أنيق يظهر عند الرفض النهائي مع شرح واضح وزرار للإعدادات
  void _showPermanentlyDeniedDialog(OnboardingCubit cubit) {
    final pageData = _pages[cubit.currentPage];

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _surfaceBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: _gold.withValues(alpha: 0.3), width: 1.5),
          ),
          icon: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _gold.withValues(alpha: 0.1),
            ),
            child: Icon(pageData.icon, color: _gold, size: 36),
          ),
          title: Text(
            'صلاحية ${pageData.settingsHint} مطلوبة',
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'يبدو أن الصلاحية تم رفضها نهائياً.\n'
                'لتفعيلها، يرجى الذهاب إلى إعدادات التطبيق وتفعيل "${pageData.settingsHint}" يدوياً.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),

              // زر فتح الإعدادات
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    PermissionManager.openSettings();
                  },
                  icon: const Icon(Icons.settings, size: 20),
                  label: Text(
                    'فتح الإعدادات',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: _darkBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _advancePage(cubit);
                },
                child: Text(
                  'تخطي هذه الخطوة',
                  style: GoogleFonts.cairo(
                    color: _gold.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _advancePage(OnboardingCubit cubit) async {
    // 👈 علم الخطوة دي إنها خلصت
    await cubit.markStepAsComplete(_pages[cubit.currentPage].permissionType);

    ScaffoldMessenger.of(context).clearSnackBars();
    if (cubit.currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      cubit.nextPage();
    } else {
      cubit.completeOnboarding();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _darkBg,
        body: Center(child: CircularProgressIndicator(color: _gold)),
      );
    }
    return BlocProvider(
      create: (_) => OnboardingCubit(
        requiredPermissions: _pages.map((p) => p.permissionType).toList(),
      ),
      child: BlocConsumer<OnboardingCubit, OnboardingState>(
        listener: (context, state) {
          if (state is OnboardingComplete) {
            _goToMainScreen();
          }
        },
        builder: (context, state) {
          final cubit = context.read<OnboardingCubit>();

          return Scaffold(
            backgroundColor: _darkBg,
            body: SafeArea(
              child: Column(
                children: [
                  // شريط العنوان: زر رجوع + تخطي الكل
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // زر رجوع (يظهر فقط في الصفحات بعد الأولى)
                        if (cubit.currentPage > 0)
                          IconButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              cubit.previousPage();
                              _pageController.animateToPage(
                                cubit.currentPage,
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeInOut,
                              );
                            },
                            icon: const Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.white70,
                              size: 20,
                            ),
                          )
                        else
                          const SizedBox(width: 48),
                        // زر تخطي الكل
                        TextButton(
                          onPressed: () => cubit.completeOnboarding(),
                          child: Text(
                            'تخطي الكل',
                            style: GoogleFonts.cairo(
                              color: _gold.withValues(alpha: 0.7),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // المحتوى
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      physics: const BouncingScrollPhysics(),
                      itemCount: _pages.length,
                      onPageChanged: (index) {
                        ScaffoldMessenger.of(context).clearSnackBars();
                        cubit.goToPage(index);
                      },
                      itemBuilder: (context, index) {
                        return _buildPage(_pages[index]);
                      },
                    ),
                  ),

                  // مؤشر الصفحات والزر
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                    child: Column(
                      children: [
                        // النقط
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_pages.length, (i) {
                            final isActive = i == cubit.currentPage;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: isActive ? 24 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isActive ? _gold : Colors.white24,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 32),

                        // الزر الذهبي
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isRequesting
                                ? null
                                : () => _onButtonPressed(cubit),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _gold,
                              disabledBackgroundColor: _gold.withValues(
                                alpha: 0.4,
                              ),
                              foregroundColor: _darkBg,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: _isRequesting
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: _darkBg,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    _pages[cubit.currentPage].buttonText,
                                    style: GoogleFonts.cairo(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPage(_OnboardingPageData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Glow circle حول الأيقونة
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_gold.withValues(alpha: 0.15), Colors.transparent],
              ),
            ),
            child: Center(
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _gold.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Icon(data.icon, size: 44, color: _gold),
              ),
            ),
          ),

          const SizedBox(height: 48),

          // العنوان
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 16),

          // الوصف
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              color: Colors.white70,
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPageData {
  final PermissionType permissionType;
  final IconData icon;
  final String title;
  final String body;
  final String buttonText;
  final String settingsHint;

  const _OnboardingPageData({
    required this.permissionType,
    required this.icon,
    required this.title,
    required this.body,
    required this.buttonText,
    required this.settingsHint,
  });
}
