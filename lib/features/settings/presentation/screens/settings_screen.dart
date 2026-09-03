import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/core/theme/cubit/theme_cubit.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_text.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/prayer_times_cubit/prayer_times_cubit.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/get_iqama_delays_usecase.dart';
import 'package:hafiz_al_ahd/features/settings/domain/usecases/save_iqama_delays_usecase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<String, int> _delays = {
    'fajr': 25,
    'dhuhr': 15,
    'asr': 15,
    'maghrib': 10,
    'isha': 15,
  };

  final Map<String, String> _prayerNames = {
    'fajr': 'الفجر',
    'dhuhr': 'الظهر',
    'asr': 'العصر',
    'maghrib': 'المغرب',
    'isha': 'العشاء',
  };

  bool _isLoading = true;
  bool _isIqamaEnabled = true;
  bool _isDstEnabled = false;
  double _adhanVolume = 1.0;
  bool _isAdhanVibrationEnabled = true;
  bool _isAzkarReminderEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final getUseCase = sl<GetIqamaDelaysUseCase>();
    final prefs = sl<SharedPreferences>();
    final savedDelays = await getUseCase.execute();

    setState(() {
      _delays.addAll(savedDelays);
      _isIqamaEnabled = prefs.getBool('isIqamaEnabled') ?? true;
      _isDstEnabled = (prefs.getInt('dst_offset_minutes') ?? 0) > 0;
      _adhanVolume = prefs.getDouble('adhan_volume') ?? 1.0;
      _isAdhanVibrationEnabled = prefs.getBool('isAdhanVibrationEnabled') ?? true;
      _isAzkarReminderEnabled = prefs.getBool('isAzkarReminderEnabled') ?? true;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final saveUseCase = sl<SaveIqamaDelaysUseCase>();
    final prefs = sl<SharedPreferences>();

    await saveUseCase.execute(_delays);
    await prefs.setBool('isIqamaEnabled', _isIqamaEnabled);
    await prefs.setDouble('adhan_volume', _adhanVolume);
    await prefs.setBool('isAdhanVibrationEnabled', _isAdhanVibrationEnabled);
    await prefs.setBool('isAzkarReminderEnabled', _isAzkarReminderEnabled);

    // مسح الكاش ده هيخلي الـ Cubit يعتبر إنه مفيش إشعارات متجدولة، فيمسح القديم ويـ schedule من الأول
    await prefs.remove('scheduled_until_date');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حفظ الإعدادات وسيتم إعادة جدولة الإشعارات!',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: AppColors.secondaryGold,
        ),
      );
      // نستدعي الدالة الصريحة اللي بتمسح وتجدول من الكاش فوراً بذكاء
      context.read<PrayerTimesCubit>().forceReschedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeCubit>().state.isDark;
    final textColor = isDark ? AppColors.silverMarble : const Color(0xFF1A1208);
    final cardColor = isDark
        ? AppColors.deepBackground
        : const Color(0xFFFFF8EC);
    final dividerColor = isDark ? Colors.white12 : const Color(0xFFE8D9B5);

    return Scaffold(
      appBar: AppBar(
        title: GradientText(
          'الإعدادات',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.secondaryGold),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.secondaryGold),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Theme Toggle ──────────────────────────────────────────
                    _buildSectionTitle('المظهر', textColor),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.secondaryGold.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            // Dark icon
                            const Icon(
                              Icons.dark_mode_rounded,
                              color: AppColors.secondaryGold,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                isDark ? 'الوضع الليلي' : 'الوضع النهاري',
                                style: GoogleFonts.cairo(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            // Toggle switch — styled gold
                            Transform.scale(
                              scale: 0.85,
                              child: Switch(
                                value: isDark,
                                activeColor: AppColors.secondaryGold,
                                activeTrackColor: AppColors.secondaryGold
                                    .withOpacity(0.3),
                                inactiveThumbColor: const Color(0xFF7A6840),
                                inactiveTrackColor: const Color(0xFFE8D9B5),
                                onChanged: (_) {
                                  context.read<ThemeCubit>().toggleTheme();
                                },
                              ),
                            ),
                            // Light icon
                            Icon(
                              isDark
                                  ? Icons.nights_stay_rounded
                                  : Icons.wb_sunny_rounded,
                              color: isDark
                                  ? AppColors.silverMarble.withOpacity(0.4)
                                  : AppColors.secondaryGold,
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── DST Toggle ──────────────────────────────────────────
                    _buildSectionTitle('التوقيت الصيفي', textColor),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.secondaryGold.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              color: AppColors.secondaryGold,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'تقديم ساعة (التوقيت الصيفي)',
                                    style: GoogleFonts.cairo(
                                      color: textColor,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'فعّله إذا كانت المواقيت متأخرة ساعة',
                                    style: GoogleFonts.cairo(
                                      color: textColor.withOpacity(0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Transform.scale(
                              scale: 0.85,
                              child: Switch(
                                value: _isDstEnabled,
                                activeColor: AppColors.secondaryGold,
                                activeTrackColor: AppColors.secondaryGold
                                    .withOpacity(0.3),
                                inactiveThumbColor: const Color(0xFF7A6840),
                                inactiveTrackColor: const Color(0xFFE8D9B5),
                                onChanged: (val) => _handleDstToggle(val),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Azkar Reminders Toggle ──────────────────────────────────────────
                    _buildSectionTitle('تذكير الأذكار', textColor),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.secondaryGold.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.notifications_active_rounded,
                              color: AppColors.secondaryGold,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'تفعيل إشعارات الأذكار',
                                    style: GoogleFonts.cairo(
                                      color: textColor,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'أذكار الصباح والمساء وبعد الصلاة',
                                    style: GoogleFonts.cairo(
                                      color: textColor.withOpacity(0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Transform.scale(
                              scale: 0.85,
                              child: Switch(
                                value: _isAzkarReminderEnabled,
                                activeColor: AppColors.secondaryGold,
                                activeTrackColor: AppColors.secondaryGold
                                    .withOpacity(0.3),
                                inactiveThumbColor: const Color(0xFF7A6840),
                                inactiveTrackColor: const Color(0xFFE8D9B5),
                                onChanged: (val) {
                                  setState(() {
                                    _isAzkarReminderEnabled = val;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Adhan Volume Slider ──────────────────────────────────────────
                    _buildSectionTitle('مستوى صوت الأذان', textColor),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.secondaryGold.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _adhanVolume == 0
                                  ? Icons.volume_off_rounded
                                  : _adhanVolume < 0.5
                                  ? Icons.volume_down_rounded
                                  : Icons.volume_up_rounded,
                              color: AppColors.secondaryGold,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: AppColors.secondaryGold,
                                  inactiveTrackColor: AppColors.secondaryGold
                                      .withOpacity(0.3),
                                  thumbColor: AppColors.secondaryGold,
                                  overlayColor: AppColors.secondaryGold
                                      .withOpacity(0.1),
                                  trackHeight: 4.0,
                                ),
                                child: Slider(
                                  value: _adhanVolume,
                                  min: 0.0,
                                  max: 1.0,
                                  divisions: 10,
                                  label: '${(_adhanVolume * 100).round()}%',
                                  onChanged: (val) {
                                    setState(() => _adhanVolume = val);
                                  },
                                  onChangeEnd: (val) async {
                                    // final prefs = sl<SharedPreferences>();
                                    _saveSettings(); // حفظ وإعادة جدولة فوراً
                                    // await prefs.setDouble('adhan_volume', val);
                                  },
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                '${(_adhanVolume * 100).round()}%',
                                textAlign: TextAlign.end,
                                style: GoogleFonts.cairo(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Adhan Vibration Toggle ──────────────────────────────────────────
                    _buildSectionTitle('الاهتزاز (Vibration)', textColor),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.secondaryGold.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.vibration_rounded,
                              color: AppColors.secondaryGold,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'الاهتزاز مع الأذان',
                                style: GoogleFonts.cairo(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Transform.scale(
                              scale: 0.85,
                              child: Switch(
                                value: _isAdhanVibrationEnabled,
                                activeColor: AppColors.secondaryGold,
                                activeTrackColor: AppColors.secondaryGold
                                    .withOpacity(0.3),
                                inactiveThumbColor: const Color(0xFF7A6840),
                                inactiveTrackColor: const Color(0xFFE8D9B5),
                                onChanged: (val) {
                                  setState(() => _isAdhanVibrationEnabled = val);
                                  _saveSettings(); // حفظ وإعادة جدولة فوراً
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Iqama Toggle ──────────────────────────────────────────
                    _buildSectionTitle('تفعيل الإقامة', textColor),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.secondaryGold.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.notifications_active_rounded,
                              color: AppColors.secondaryGold,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'تنبيهات الإقامة',
                                style: GoogleFonts.cairo(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Transform.scale(
                              scale: 0.85,
                              child: Switch(
                                value: _isIqamaEnabled,
                                activeColor: AppColors.secondaryGold,
                                activeTrackColor: AppColors.secondaryGold
                                    .withOpacity(0.3),
                                inactiveThumbColor: const Color(0xFF7A6840),
                                inactiveTrackColor: const Color(0xFFE8D9B5),
                                onChanged: (val) {
                                  setState(() => _isIqamaEnabled = val);
                                  _saveSettings(); // حفظ وإعادة جدولة فوراً
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Iqama Delays Tile ──────────────────────────────────────────
                    _buildSectionTitle('تأخير الإقامة', textColor),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _showIqamaDelaysDialog,
                      child: Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.secondaryGold.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.edit_calendar_rounded,
                                color: AppColors.secondaryGold,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'تعديل أوقات تأخير الإقامة',
                                  style: GoogleFonts.cairo(
                                    color: textColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
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
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  /// عرض ديالوج تعديل أوقات الإقامة
  void _showIqamaDelaysDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = context.watch<ThemeCubit>().state.isDark;
            final textColor = isDark
                ? AppColors.silverMarble
                : const Color(0xFF1A1208);
            final cardColor = isDark
                ? AppColors.deepBackground
                : const Color(0xFFFFF8EC);
            final dividerColor = isDark
                ? Colors.white12
                : const Color(0xFFE8D9B5);

            return AlertDialog(
              backgroundColor: cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Center(
                child: Text(
                  'تأخير الإقامة (بالدقائق)',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondaryGold,
                    fontSize: 20,
                  ),
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _prayerNames.entries.map((entry) {
                    final key = entry.key;
                    final name = entry.value;
                    return Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.access_time_filled_rounded,
                            color: AppColors.secondaryGold,
                            size: 22,
                          ),
                          title: Text(
                            name,
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              color: textColor,
                            ),
                          ),
                          trailing: DropdownButton<int>(
                            value: _delays[key],
                            dropdownColor: isDark
                                ? AppColors.deepBackground
                                : const Color(0xFFFFF8EC),
                            underline: const SizedBox.shrink(),
                            style: GoogleFonts.cairo(
                              color: AppColors.secondaryGold,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            items: [5, 10, 15, 20, 25, 30]
                                .map(
                                  (v) => DropdownMenuItem<int>(
                                    value: v,
                                    child: Text('$v دقيقة'),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => _delays[key] = v);
                                setState(() => _delays[key] = v);
                              }
                            },
                          ),
                        ),
                        if (key != 'isha') Divider(color: dividerColor),
                      ],
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'إلغاء',
                    style: GoogleFonts.cairo(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    _saveSettings();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondaryGold,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'حفظ',
                    style: GoogleFonts.cairo(
                      color: AppColors.primaryBlack,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// معالجة تبديل التوقيت الصيفي مع AlertDialog تحذيري عند التفعيل
  void _handleDstToggle(bool newValue) {
    if (newValue) {
      // عند التفعيل: نعرض تحذير الـ Double DST
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.secondaryGold,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                'تنبيه',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondaryGold,
                ),
              ),
            ],
          ),
          content: Text(
            'لا تقم بتفعيل هذا الخيار إلا إذا كانت مواقيت الصلاة متأخرة بساعة كاملة عن توقيتك المحلي.\n\nتفعيله مع التحديث التلقائي لهاتفك قد يؤدي لزيادة الوقت بساعتين.',
            style: GoogleFonts.cairo(height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'إلغاء',
                style: GoogleFonts.cairo(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondaryGold,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _applyDstChange(true);
              },
              child: Text(
                'تأكيد',
                style: GoogleFonts.cairo(
                  color: AppColors.primaryBlack,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // عند الإيقاف: نطبق مباشرة بدون تحذير
      _applyDstChange(false);
    }
  }

  /// تطبيق تغيير التوقيت الصيفي وحفظه وإعادة جدولة الإشعارات
  Future<void> _applyDstChange(bool enabled) async {
    final prefs = sl<SharedPreferences>();
    setState(() => _isDstEnabled = enabled);
    await prefs.setInt('dst_offset_minutes', enabled ? 60 : 0);
    await prefs.remove('scheduled_until_date');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'تم تفعيل التوقيت الصيفي (+60 دقيقة)'
                : 'تم إيقاف التوقيت الصيفي',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: AppColors.secondaryGold,
        ),
      );
      context.read<PrayerTimesCubit>().forceReschedule();
    }
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Text(
      title,
      style: GoogleFonts.cairo(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.secondaryGold,
      ),
    );
  }
}
