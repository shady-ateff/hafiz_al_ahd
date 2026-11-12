import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/widgets/app_loader.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_state.dart';
import 'package:hafiz_al_ahd/features/settings/presentation/screens/adhan_catalog_screen.dart';
import 'package:hafiz_al_ahd/features/settings/presentation/screens/prayer_detail_settings_screen.dart';

class PrayerAlarmSettingsScreen extends StatelessWidget {
  const PrayerAlarmSettingsScreen({super.key});

  static const Map<PrayerId, String> _prayerNames = {
    PrayerId.fajr: 'الفجر',
    PrayerId.dhuhr: 'الظهر',
    PrayerId.asr: 'العصر',
    PrayerId.maghrib: 'المغرب',
    PrayerId.isha: 'العشاء',
  };

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final dividerColor = isDark ? Colors.white12 : Colors.black.withOpacity(0.08);

    return WillPopScope(
      onWillPop: () async {
        context.read<PrayerAlarmSettingsCubit>().stopAudioPreview();
        return true;
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: Text(
            'تنبيهات الصلوات والأذان',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          elevation: 0,
        ),
        body: BlocConsumer<PrayerAlarmSettingsCubit, PrayerAlarmSettingsState>(
          listener: (context, state) {
            if (state.errorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage!, style: GoogleFonts.cairo()),
                  backgroundColor: Colors.red.shade800,
                ),
              );
            }
            if (state.infoMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.infoMessage!, style: GoogleFonts.cairo()),
                  backgroundColor: const Color(0xFF2C2C2E),
                ),
              );
            }
          },
          builder: (context, state) {
            if (state.status == SettingsStatus.loading) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.secondaryGold),
              );
            }

            final cubit = context.read<PrayerAlarmSettingsCubit>();

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                // ══════════════════════════════════════════════════════════════
                // SECTION A: الإعدادات العامة التلقائية (Global Defaults)
                // ══════════════════════════════════════════════════════════════
                _buildSectionHeader(
                  title: 'الإعدادات العامة التلقائية',
                  subtitle:
                      'تُطبق هذه الإعدادات افتراضيًا على جميع الصلوات ما لم يتم تخصيص صلاة معينة أدناه.',
                  icon: Icons.tune_rounded,
                ),
                Card(
                  color: cardColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      // 1. All Prayers Alert Mode Radio Selector (أذان كامل / إشعار بسيط / إيقاف الكل)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'وضع التنبيه لجميع الصلوات',
                                        style: GoogleFonts.cairo(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: textColor,
                                        ),
                                      ),
                                      if (state.hasMixedModes)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            'مخصص (مختلف بين الصلوات)',
                                            style: GoogleFonts.cairo(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber.shade700,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _buildGlobalModeRadioTile(
                                    context: context,
                                    title: 'أذان كامل لجميع الصلوات',
                                    subtitle: 'تشغيل الأذان بصوت المؤذن مع شاشة التنبيه',
                                    mode: PrayerAlarmType.alarm,
                                    selectedMode: state.dominantGlobalMode,
                                    icon: Icons.notifications_active_rounded,
                                    iconColor: AppColors.secondaryGold,
                                    textColor: textColor,
                                    isLoading: state.isUpdatingAllPrayers,
                                    onTap: () => cubit.setAllPrayersMode(PrayerAlarmType.alarm),
                                  ),
                                  const Divider(height: 1, indent: 40),
                                  _buildGlobalModeRadioTile(
                                    context: context,
                                    title: 'إشعار بسيط لجميع الصلوات',
                                    subtitle: 'تنبيه نظام هادئ بدون صوت أذان',
                                    mode: PrayerAlarmType.notification,
                                    selectedMode: state.dominantGlobalMode,
                                    icon: Icons.notifications_none_rounded,
                                    iconColor: textColor.withValues(alpha: 0.7),
                                    textColor: textColor,
                                    isLoading: state.isUpdatingAllPrayers,
                                    onTap: () => cubit.setAllPrayersMode(PrayerAlarmType.notification),
                                  ),
                                  const Divider(height: 1, indent: 40),
                                  _buildGlobalModeRadioTile(
                                    context: context,
                                    title: 'إيقاف التنبيهات لجميع الصلوات (صامت)',
                                    subtitle: 'تعطيل التنبيهات والإشعارات لكافة الصلوات',
                                    mode: PrayerAlarmType.off,
                                    selectedMode: state.dominantGlobalMode,
                                    icon: Icons.notifications_off_outlined,
                                    iconColor: Colors.grey,
                                    textColor: textColor,
                                    isLoading: state.isUpdatingAllPrayers,
                                    onTap: () => cubit.setAllPrayersMode(PrayerAlarmType.off),
                                  ),
                                ],
                              ),
                            ),
                            if (state.isUpdatingAllPrayers)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: cardColor.withValues(alpha: 0.88),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox(
                                          width: 75,
                                          height: 75,
                                          child: AppLoader(),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'جاري تحديث وضع الصلوات...',
                                          style: GoogleFonts.cairo(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.secondaryGold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      Divider(color: dividerColor, height: 1, indent: 16, endIndent: 16),

                      // 2. Default Muadhin Tile
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: IconButton(
                          icon: Icon(
                            state.isPreviewPlaying &&
                                    state.playingPreviewSource?.id ==
                                        state.globalAudioSource.id
                                ? Icons.stop_circle_rounded
                                : Icons.play_circle_fill_rounded,
                            color: AppColors.secondaryGold,
                            size: 36,
                          ),
                          onPressed: () {
                            if (state.isPreviewPlaying &&
                                state.playingPreviewSource?.id ==
                                    state.globalAudioSource.id) {
                              cubit.stopAudioPreview();
                            } else {
                              cubit.playAudioPreview(state.globalAudioSource);
                            }
                          },
                        ),
                        title: Text(
                          'المؤذن الافتراضي العام',
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        subtitle: Text(
                          state.globalAudioSource.displayName,
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.secondaryGold,
                          ),
                        ),
                        trailing: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.secondaryGold),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          onPressed: () async {
                            cubit.stopAudioPreview();
                            final selected = await Navigator.of(context).push<AudioSourceConfig>(
                              MaterialPageRoute(
                                builder: (_) => AdhanCatalogScreen(
                                  currentSelectedSource: state.globalAudioSource,
                                  isFajr: false,
                                ),
                              ),
                            );
                            if (selected != null && context.mounted) {
                              await cubit.updateGlobalAudioSource(selected);
                            }
                          },
                          child: Text(
                            'تغيير',
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.secondaryGold,
                            ),
                          ),
                        ),
                      ),

                      Divider(color: dividerColor, height: 1, indent: 16, endIndent: 16),

                      // 2. Global Adhan Volume
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'مستوى صوت الأذان الافتراضي',
                                  style: GoogleFonts.cairo(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                ),
                                Text(
                                  '${(state.globalAdhanVolume * 100).round()}%',
                                  style: GoogleFonts.cairo(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.secondaryGold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Slider(
                              value: state.globalAdhanVolume,
                              min: 0.1,
                              max: 1.0,
                              divisions: 9,
                              activeColor: AppColors.secondaryGold,
                              inactiveColor: textColor.withOpacity(0.2),
                              onChanged: (val) {
                                cubit.updateGlobalVolume(val);
                              },
                            ),
                          ],
                        ),
                      ),

                      Divider(color: dividerColor, height: 1, indent: 16, endIndent: 16),

                      // 3. Global Vibration Switch
                      SwitchListTile(
                        activeColor: AppColors.secondaryGold,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        title: Text(
                          'الاهتزاز الافتراضي مع الأذان',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        subtitle: Text(
                          'تفعيل الاهتزاز عند إطلاق منبه الأذان',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: textColor.withOpacity(0.6),
                          ),
                        ),
                        value: state.isGlobalAdhanVibrationEnabled,
                        onChanged: (val) {
                          cubit.updateGlobalVibration(val);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ══════════════════════════════════════════════════════════════
                // SECTION B: التحكم المستقل لكل صلاة (Independent Prayer Alarms)
                // ══════════════════════════════════════════════════════════════
                _buildSectionHeader(
                  title: 'التحكم المستقل لكل صلاة',
                  subtitle:
                      'اضغط على أي صلاة لتخصيص طريقة تنبيهها، المؤذن، أو مستوى الصوت الخاص بها.',
                  icon: Icons.access_alarms_rounded,
                ),

                // Five prayer cards
                ...PrayerId.values.map((prayerId) {
                  final prayerName = _prayerNames[prayerId]!;
                  final config = state.configs[prayerId] ??
                      PrayerAlarmConfig.withDefaultAudio(
                        prayerId: prayerId,
                        alarmType: PrayerAlarmType.alarm,
                      );

                  return _buildPrayerSummaryCard(
                    context,
                    prayerId: prayerId,
                    prayerName: prayerName,
                    config: config,
                    state: state,
                    cardColor: cardColor,
                    textColor: textColor,
                  );
                }),

                const SizedBox(height: 20),

                // ══════════════════════════════════════════════════════════════
                // SECTION C: مكتبة أصوات المؤذنين (Adhan Catalog Entry)
                // ══════════════════════════════════════════════════════════════
                _buildSectionHeader(
                  title: 'مكتبة أصوات المؤذنين',
                  subtitle: 'الاستماع لجميع أصوات الأذان المتاحة وإدارتها.',
                  icon: Icons.library_music_rounded,
                ),
                Card(
                  color: cardColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      cubit.stopAudioPreview();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AdhanCatalogScreen(
                            currentSelectedSource: state.globalAudioSource,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.secondaryGold.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.queue_music_rounded,
                              color: AppColors.secondaryGold,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'تصفح وإدارة أصوات الأذان',
                                  style: GoogleFonts.cairo(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'معاينة واختيار أصوات المؤذنين للأذان العام وفجر',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    color: textColor.withOpacity(0.6),
                                  ),
                                ),
                              ],
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
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.secondaryGold, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondaryGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.cairo(
              fontSize: 12,
              color: Colors.grey,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrayerSummaryCard(
    BuildContext context, {
    required PrayerId prayerId,
    required String prayerName,
    required PrayerAlarmConfig config,
    required PrayerAlarmSettingsState state,
    required Color cardColor,
    required Color textColor,
  }) {
    final effectiveMode = state.getEffectiveMode(prayerId);
    final effectiveAudio = state.getEffectiveAudioSource(prayerId);
    final isTransitioning = state.isTransitioning(prayerId);

    final String modeLabel;
    final IconData modeIcon;
    final Color modeColor;

    switch (effectiveMode) {
      case PrayerAlarmType.alarm:
        modeLabel = 'منبه بكامل الشاشة';
        modeIcon = Icons.notifications_active_rounded;
        modeColor = AppColors.secondaryGold;
        break;
      case PrayerAlarmType.notification:
        modeLabel = 'إشعار بسيط';
        modeIcon = Icons.notifications_none_rounded;
        modeColor = textColor.withOpacity(0.7);
        break;
      case PrayerAlarmType.off:
        modeLabel = 'معطل';
        modeIcon = Icons.notifications_off_outlined;
        modeColor = Colors.grey;
        break;
    }

    // Check if this prayer has actual customization that differs from global defaults
    final isAudioCustomized = config.hasAudioOverride &&
        config.audioSource.id != state.globalAudioSource.id;
    final isVolumeCustomized = config.volume != null &&
        (config.volume! - state.globalAdhanVolume).abs() > 0.01;
    final isVibrationCustomized = config.isVibrationEnabled != null &&
        config.isVibrationEnabled != state.isGlobalAdhanVibrationEnabled;
    final isModeCustomized = state.hasMixedModes &&
        state.dominantGlobalMode != null &&
        effectiveMode != state.dominantGlobalMode;

    final hasCustomization =
        isAudioCustomized || isVolumeCustomized || isVibrationCustomized || isModeCustomized;

    return Card(
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          context.read<PrayerAlarmSettingsCubit>().stopAudioPreview();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PrayerDetailSettingsScreen(
                prayerId: prayerId,
                prayerName: prayerName,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: modeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isTransitioning
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.secondaryGold,
                        ),
                      )
                    : Icon(modeIcon, color: modeColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'صلاة $prayerName',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        if (hasCustomization) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryGold.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'مخصص',
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondaryGold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isTransitioning
                          ? 'جاري تحديث الوضع...'
                          : effectiveMode == PrayerAlarmType.alarm
                              ? '$modeLabel • ${effectiveAudio.displayName}'
                              : modeLabel,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: textColor.withOpacity(0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
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
    );
  }

  Widget _buildGlobalModeRadioTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required PrayerAlarmType mode,
    required PrayerAlarmType? selectedMode,
    required IconData icon,
    required Color iconColor,
    required Color textColor,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    final isSelected = selectedMode == mode;

    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.secondaryGold : iconColor,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? AppColors.secondaryGold : textColor,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            Radio<PrayerAlarmType>(
              value: mode,
              groupValue: selectedMode,
              onChanged: isLoading ? null : (_) => onTap(),
              activeColor: AppColors.secondaryGold,
            ),
          ],
        ),
      ),
    );
  }
}
