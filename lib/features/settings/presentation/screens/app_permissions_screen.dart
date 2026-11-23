import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/theme/cubit/theme_cubit.dart';
import '../../../../core/utils/app_colors.dart';
import '../../../../core/widgets/gradient_text.dart';
import '../../../focus_mode/presentation/widgets/focus_oem_guide_sheet.dart';
import '../../../focus_mode_poc/data/focus_poc_channel.dart';

/// Representation of an app permission item with diagnostic and impact data.
class _PermissionItemData {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final bool isGranted;
  final bool isRequired;
  final String impactIfNotGranted;
  final List<String> affectedFeatures;
  final Future<void> Function() onRequest;

  const _PermissionItemData({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.isGranted,
    this.isRequired = true,
    required this.impactIfNotGranted,
    required this.affectedFeatures,
    required this.onRequest,
  });
}

/// Screen that checks, displays, and assists the user in resolving all app permissions.
/// Explains the exact consequence and impact if any permission is disabled.
class AppPermissionsScreen extends StatefulWidget {
  const AppPermissionsScreen({super.key});

  @override
  State<AppPermissionsScreen> createState() => _AppPermissionsScreenState();
}

class _AppPermissionsScreenState extends State<AppPermissionsScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;

  bool _hasNotification = false;
  bool _hasExactAlarm = false;
  bool _hasBatteryOptimizationIgnored = false;
  bool _hasLocation = false;
  bool _hasOverlay = false;
  bool _hasUsageAccess = false;
  bool _hasNotificationPolicy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllPermissions();
    }
  }

  Future<void> _checkAllPermissions() async {
    setState(() => _isLoading = true);

    try {
      final notifStatus = await Permission.notification.status;
      final locationStatus = await Permission.location.status;
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      final dndStatus = await Permission.accessNotificationPolicy.status;

      final nativePoc = await FocusPoCChannel.checkPermissions();

      if (mounted) {
        setState(() {
          _hasNotification = notifStatus.isGranted;
          _hasLocation = locationStatus.isGranted;
          _hasBatteryOptimizationIgnored = batteryStatus.isGranted;
          _hasNotificationPolicy = dndStatus.isGranted;

          _hasOverlay = nativePoc.hasOverlayPermission;
          _hasUsageAccess = nativePoc.hasUsageAccess;
          _hasExactAlarm = nativePoc.canScheduleExactAlarms;

          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<_PermissionItemData> _getPrayerPermissions() {
    return [
      _PermissionItemData(
        id: 'notification',
        title: 'إشعارات الأذان والتنبيهات',
        description: 'إرسال تنبيهات أوقات الصلاة، الأذكار اليومية، ومتابعة تحميل التلاوات.',
        icon: Icons.notifications_active_rounded,
        isGranted: _hasNotification,
        isRequired: true,
        impactIfNotGranted:
            'لن تتلقى أي تنبيه صوتي أو بصري عند دخول موعد الصلاة، ولن تظهر تذكيرات الأذكار اليومية عند إغلاق التطبيق.',
        affectedFeatures: [
          'تنبيهات أذان الصلوات الخمس ومواقيتها',
          'تذكيرات أذكار الصباح والمساء والاستغفار',
          'إشعار سير تقدم تحميل المصحف الصوتي',
        ],
        onRequest: () async {
          final res = await Permission.notification.request();
          if (res.isPermanentlyDenied) {
            await openAppSettings();
          }
          await _checkAllPermissions();
        },
      ),
      _PermissionItemData(
        id: 'exact_alarm',
        title: 'المنبهات الدقيقة (Exact Alarms)',
        description: 'إيقاظ الهاتف وتشغيل صوت الأذان في الثانية المحددة بدقة لكل صلاة.',
        icon: Icons.alarm_on_rounded,
        isGranted: _hasExactAlarm,
        isRequired: true,
        impactIfNotGranted:
            'بدون هذه الصلاحية، قد يؤخر نظام أندرويد رنين الأذان لعدة دقائق حتى تنشط الشاشة، أو قد لا يرن نهائياً في وضع السكون.',
        affectedFeatures: [
          'دقة رنين الأذان في موعده الشرعي بالثانية',
          'بدء جلسات وضع التركيز في موعدها الدقيق',
        ],
        onRequest: () async {
          await FocusPoCChannel.openExactAlarmSettings();
          await _checkAllPermissions();
        },
      ),
      _PermissionItemData(
        id: 'battery_optimization',
        title: 'تجاهل تحسين البطارية',
        description: 'حماية التطبيق من الإيقاف الإجباري بواسطة نظام أندرويد في الخلفية.',
        icon: Icons.battery_charging_full_rounded,
        isGranted: _hasBatteryOptimizationIgnored,
        isRequired: true,
        impactIfNotGranted:
            'يقوم نظام أندرويد بقتل التطبيق في الخلفية لتوفير الشحن، مما يتسبب في تفويت أذان الفجر والصلوات الأخرى عند نوم الجهاز.',
        affectedFeatures: [
          'ضمان استمرار رنين الأذان طوال اليوم بدون انقطاع',
          'حماية أذان الفجر من الإغلاق في وضع السكون الليلي',
        ],
        onRequest: () async {
          await Permission.ignoreBatteryOptimizations.request();
          await _checkAllPermissions();
        },
      ),
      _PermissionItemData(
        id: 'location',
        title: 'تحديد الموقع الجغرافي',
        description: 'حساب مواقيت الصلاة واتجاه القبلة بدقة بحسب إحداثيات مدينتك.',
        icon: Icons.location_on_rounded,
        isGranted: _hasLocation,
        isRequired: true,
        impactIfNotGranted:
            'لن يستطيع التطبيق تحديث مواقيت الصلاة تلقائياً عند السفر أو تغيير المدينة، ولن تعمل بوصلة القبلة بدقة.',
        affectedFeatures: [
          'الحساب التلقائي لمواقيت الصلاة حسب موقعك الحالي',
          'بوصلة القبلة الدقيقة',
        ],
        onRequest: () async {
          final res = await Permission.location.request();
          if (res.isPermanentlyDenied) {
            await openAppSettings();
          }
          await _checkAllPermissions();
        },
      ),
    ];
  }

  List<_PermissionItemData> _getFocusModePermissions() {
    return [
      _PermissionItemData(
        id: 'overlay',
        title: 'الظهور فوق التطبيقات (Overlay)',
        description: 'عرض شاشة حماية الورد القرآني والأذكار فوق التطبيقات المشتتة.',
        icon: Icons.layers_rounded,
        isGranted: _hasOverlay,
        isRequired: false,
        impactIfNotGranted:
            'لن يتمكن "وضع التركيز" من منعك من فتح التطبيقات المشتتة أو إظهار شاشة الحماية أثناء وقت الورد.',
        affectedFeatures: [
          'حجب التطبيقات المشتتة في وضع التركيز',
          'إظهار شاشة التذكير بالورد فوق أي تطبيق',
        ],
        onRequest: () async {
          await FocusPoCChannel.openOverlaySettings();
          await _checkAllPermissions();
        },
      ),
      _PermissionItemData(
        id: 'usage_access',
        title: 'الوصول لبيانات الاستخدام (Usage Access)',
        description: 'معرفة التطبيق المشغل في الواجهة أثناء وضع التركيز فقط لتمييز المشتتات.',
        icon: Icons.bar_chart_rounded,
        isGranted: _hasUsageAccess,
        isRequired: false,
        impactIfNotGranted:
            'لن يستطيع وضع التركيز التعرف على التطبيقات التي تفتحها لحمايتك من التشتت واستثناء التطبيقات الهامة.',
        affectedFeatures: [
          'اكتشاف التطبيقات المفتوحة أثناء وضع التركيز فقط',
          'استثناء تطبيقات المكالمات والخرائط الضرورية',
        ],
        onRequest: () async {
          await FocusPoCChannel.openUsageAccessSettings();
          await _checkAllPermissions();
        },
      ),
    ];
  }

  List<_PermissionItemData> _getOptionalPermissions() {
    return [
      _PermissionItemData(
        id: 'notification_policy',
        title: 'تجاوز وضع عدم الإزعاج (اختياري)',
        description: 'إسماع صوت الأذان حتى لو كان الهاتف مضبوطاً على الوضع الصامت.',
        icon: Icons.do_not_disturb_on_total_silence_rounded,
        isGranted: _hasNotificationPolicy,
        isRequired: false,
        impactIfNotGranted:
            'إذا كان الهاتف في وضع الصامت أو عدم الإزعاج وقت الأذان، فلن يصدر صوت الأذان لحين إلغاء الصامت يدوياً.',
        affectedFeatures: [
          'إسماع صوت الأذان في الوضع الصامت أو وضع عدم الإزعاج',
        ],
        onRequest: () async {
          final res = await Permission.accessNotificationPolicy.request();
          if (res.isPermanentlyDenied) {
            await openAppSettings();
          }
          await _checkAllPermissions();
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeCubit>().state.isDark;
    final textColor = isDark ? AppColors.silverMarble : const Color(0xFF1A1208);
    final cardColor = isDark ? AppColors.deepBackground : const Color(0xFFFFF8EC);
    final dividerColor = isDark ? Colors.white12 : const Color(0xFFE8D9B5);

    final prayerPermissions = _getPrayerPermissions();
    final focusPermissions = _getFocusModePermissions();
    final optionalPermissions = _getOptionalPermissions();

    final allPermissions = [
      ...prayerPermissions,
      ...focusPermissions,
      ...optionalPermissions,
    ];

    final missingRequired = prayerPermissions.where((p) => !p.isGranted).length;
    final missingTotal = allPermissions.where((p) => !p.isGranted).length;
    final totalCount = allPermissions.length;
    final grantedCount = totalCount - missingTotal;

    return Scaffold(
      appBar: AppBar(
        title: GradientText(
          'فحص صلاحيات التطبيق',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.secondaryGold),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'إعادة الفحص',
            onPressed: _checkAllPermissions,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.secondaryGold),
            )
          : RefreshIndicator(
              color: AppColors.secondaryGold,
              onRefresh: _checkAllPermissions,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Summary Status Card ────────────────────────────────
                    _buildSummaryCard(
                      isDark: isDark,
                      missingRequired: missingRequired,
                      missingTotal: missingTotal,
                      grantedCount: grantedCount,
                      totalCount: totalCount,
                    ),
                    const SizedBox(height: 20),

                    // ── Section 1: Core Prayer & Adhan Permissions ─────────
                    _buildSectionHeader(
                      title: 'صلاحيات الأذان ومواقيت الصلاة الأساسية',
                      subtitle: 'ضرورية لضمان رنين الأذان ودقة المواقيت في موعدها',
                      textColor: textColor,
                    ),
                    const SizedBox(height: 10),
                    ...prayerPermissions.map(
                      (item) => _buildPermissionCard(
                        item: item,
                        isDark: isDark,
                        cardColor: cardColor,
                        dividerColor: dividerColor,
                        textColor: textColor,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Section 2: Focus Mode Permissions ──────────────────
                    _buildSectionHeader(
                      title: 'صلاحيات وضع التركيز وحماية الأوراد',
                      subtitle: 'مطلوبة لحجب التطبيقات المشتتة وعرض شاشة الورد',
                      textColor: textColor,
                    ),
                    const SizedBox(height: 10),
                    ...focusPermissions.map(
                      (item) => _buildPermissionCard(
                        item: item,
                        isDark: isDark,
                        cardColor: cardColor,
                        dividerColor: dividerColor,
                        textColor: textColor,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Section 3: Optional Advanced Permissions ───────────
                    _buildSectionHeader(
                      title: 'صلاحيات إضافية متقدمة',
                      subtitle: 'ميزات تكميلية لتحسين تجربة المستخدم',
                      textColor: textColor,
                    ),
                    const SizedBox(height: 10),
                    ...optionalPermissions.map(
                      (item) => _buildPermissionCard(
                        item: item,
                        isDark: isDark,
                        cardColor: cardColor,
                        dividerColor: dividerColor,
                        textColor: textColor,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── OEM Guide Card ─────────────────────────────────────
                    _buildOemGuideCard(
                      isDark: isDark,
                      cardColor: cardColor,
                      textColor: textColor,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummaryCard({
    required bool isDark,
    required int missingRequired,
    required int missingTotal,
    required int grantedCount,
    required int totalCount,
  }) {
    final bool allGood = missingTotal == 0;
    final bool hasCriticalMissing = missingRequired > 0;

    final gradientColors = allGood
        ? [const Color(0xFF065F46), const Color(0xFF047857)]
        : hasCriticalMissing
            ? [const Color(0xFF7F1D1D), const Color(0xFF991B1B)]
            : [const Color(0xFF78350F), const Color(0xFF92400E)];

    final iconData = allGood
        ? Icons.verified_user_rounded
        : hasCriticalMissing
            ? Icons.error_outline_rounded
            : Icons.warning_amber_rounded;

    final title = allGood
        ? 'جميع الصلاحيات مكتملة ومفعّلة بنجاح'
        : hasCriticalMissing
            ? 'تنبيه: هناك صلاحيات هامة للأذان غير مفعّلة ($missingRequired مفقودة)'
            : 'يوجد $missingTotal صلاحيات إضافية غير مفعّلة';

    final subtitle = allGood
        ? 'يعمل التطبيق الآن بكامل طاقته ومميزاته دون أي قيود، والتنبيهات مضمونة بإذن الله.'
        : hasCriticalMissing
            ? 'قد يتوقف رنين الأذان في موعده أو يُقتل التطبيق في الخلفية إذا لم تمنح الصلاحيات الأساسية.'
            : 'الصلاحيات الأساسية للأذان مفعّلة، لكن بعض ميزات وضع التركيز أو عدم الإزعاج غير مكتملة.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconData, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.cairo(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'المفعّل: $grantedCount من $totalCount',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _checkAllPermissions,
                icon: const Icon(Icons.sync_rounded, color: Colors.white, size: 16),
                label: Text(
                  'تحديث الحالة',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required Color textColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.cairo(
            color: textColor,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: GoogleFonts.cairo(
            color: textColor.withValues(alpha: 0.65),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionCard({
    required _PermissionItemData item,
    required bool isDark,
    required Color cardColor,
    required Color dividerColor,
    required Color textColor,
  }) {
    final isGranted = item.isGranted;
    final statusColor = isGranted ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final statusText = isGranted ? 'مفعّلة' : 'غير مفعّلة';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGranted
              ? AppColors.secondaryGold.withValues(alpha: 0.25)
              : const Color(0xFFEF4444).withValues(alpha: 0.4),
          width: isGranted ? 1 : 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & Status Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (isGranted ? AppColors.secondaryGold : const Color(0xFFEF4444))
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    item.icon,
                    color: isGranted ? AppColors.secondaryGold : const Color(0xFFEF4444),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: GoogleFonts.cairo(
                          color: textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.description,
                        style: GoogleFonts.cairo(
                          color: textColor.withValues(alpha: 0.65),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isGranted ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: statusColor,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: GoogleFonts.cairo(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Warning Box if not granted: What will be affected!
            if (!isGranted) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A1010)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_rounded,
                          color: Color(0xFFDC2626),
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'ما الذي سيتأثر عند إغلاق هذه الصلاحية؟',
                            style: GoogleFonts.cairo(
                              color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.impactIfNotGranted,
                      style: GoogleFonts.cairo(
                        color: isDark ? const Color(0xFFE5E7EB) : const Color(0xFF374151),
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: item.affectedFeatures.map((feat) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 3),
                                child: Icon(
                                  Icons.remove_circle_outline_rounded,
                                  color: Color(0xFFEF4444),
                                  size: 13,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  feat,
                                  style: GoogleFonts.cairo(
                                    color: isDark
                                        ? const Color(0xFFD1D5DB)
                                        : const Color(0xFF4B5563),
                                    fontSize: 11.5,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Action Button to grant
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: item.onRequest,
                  icon: const Icon(Icons.touch_app_rounded, size: 18),
                  label: Text(
                    'تفعيل الصلاحية الآن',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondaryGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOemGuideCard({
    required bool isDark,
    required Color cardColor,
    required Color textColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.secondaryGold.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => FocusOEMGuideSheet.show(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.phone_android_rounded,
                    color: AppColors.secondaryGold,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إرشادات مصنّعي الهواتف (شاومي / سامسونج / هواوي)',
                        style: GoogleFonts.cairo(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'خطوات حماية التطبيق من الإغلاق في الخلفية وتثبيت التشغيل التلقائي',
                        style: GoogleFonts.cairo(
                          color: textColor.withValues(alpha: 0.65),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppColors.secondaryGold,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
