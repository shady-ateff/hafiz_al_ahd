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
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final saveUseCase = sl<SaveIqamaDelaysUseCase>();
    final prefs = sl<SharedPreferences>();
    
    await saveUseCase.execute(_delays);
    await prefs.setBool('isIqamaEnabled', _isIqamaEnabled);

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
          : Padding(
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

                  // ── Iqama Delays ──────────────────────────────────────────
                  _buildSectionTitle('تأخير الإقامة (بالدقائق)', textColor),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.secondaryGold.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _prayerNames.length,
                        separatorBuilder: (_, __) => Divider(
                          color: dividerColor,
                          indent: 16,
                          endIndent: 16,
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final key = _prayerNames.keys.elementAt(index);
                          final name = _prayerNames[key]!;
                          return ListTile(
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
                                  setState(() => _delays[key] = v);
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Save Button ──────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: AppColors.goldenGradient,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _saveSettings,
                      child: Text(
                        'حفظ الإعدادات',
                        style: GoogleFonts.cairo(
                          color: AppColors.primaryBlack,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.secondaryGold, size: 28),
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
