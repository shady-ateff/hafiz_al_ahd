import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_state.dart';
import 'package:hafiz_al_ahd/features/settings/presentation/screens/adhan_catalog_screen.dart';

class PrayerDetailSettingsScreen extends StatelessWidget {
  final PrayerId prayerId;
  final String prayerName;

  const PrayerDetailSettingsScreen({
    super.key,
    required this.prayerId,
    required this.prayerName,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return WillPopScope(
      onWillPop: () async {
        context.read<PrayerAlarmSettingsCubit>().stopAudioPreview();
        return true;
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: Text(
            'تنبيه صلاة $prayerName',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          elevation: 0,
        ),
        body: BlocBuilder<PrayerAlarmSettingsCubit, PrayerAlarmSettingsState>(
          builder: (context, state) {
            final config = state.configs[prayerId] ??
                PrayerAlarmConfig.withDefaultAudio(
                  prayerId: prayerId,
                  alarmType: PrayerAlarmType.alarm,
                );

            final effectiveMode = state.getEffectiveMode(prayerId);
            final isAlarmMode = effectiveMode == PrayerAlarmType.alarm;
            final effectiveAudio = state.getEffectiveAudioSource(prayerId);
            final effectiveDisplayVolume = state.getEffectiveVolume(prayerId);
            final isVolumeCustomized = config.volume != null;
            final isAudioCustomized = config.hasAudioOverride;

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                // 1. Alert Mode Selector
                _buildSectionHeader('طريقة التنبيه', textColor),
                Card(
                  color: cardColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        _buildModeRadio(
                          context,
                          title: 'منبه بكامل الشاشة',
                          subtitle: 'تشغيل صوت الأذان وشاشة المنبه الكاملة',
                          mode: PrayerAlarmType.alarm,
                          currentMode: effectiveMode,
                          icon: Icons.notifications_active_rounded,
                          textColor: textColor,
                        ),
                        const Divider(height: 1, indent: 56),
                        _buildModeRadio(
                          context,
                          title: 'إشعار بسيط',
                          subtitle: 'إشعار نظام مع نغمة التنبيه الافتراضية',
                          mode: PrayerAlarmType.notification,
                          currentMode: effectiveMode,
                          icon: Icons.notifications_none_rounded,
                          textColor: textColor,
                        ),
                        const Divider(height: 1, indent: 56),
                        _buildModeRadio(
                          context,
                          title: 'إيقاف التنبيه',
                          subtitle: 'تعطيل المنبه والإشعارات لهذه الصلاة',
                          mode: PrayerAlarmType.off,
                          currentMode: effectiveMode,
                          icon: Icons.notifications_off_outlined,
                          textColor: textColor,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 2. Audio Source (Alarm mode only)
                if (isAlarmMode) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader('صوت الأذان', textColor),
                      if (isAudioCustomized)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          ),
                          icon: const Icon(Icons.undo_rounded, size: 16, color: AppColors.secondaryGold),
                          label: Text(
                            'استعادة الافتراضي',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              color: AppColors.secondaryGold,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            context
                                .read<PrayerAlarmSettingsCubit>()
                                .updatePrayerAudioSource(prayerId, null, clearOverride: true);
                          },
                        ),
                    ],
                  ),
                  Card(
                    color: cardColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: IconButton(
                        icon: Icon(
                          state.isPreviewPlaying &&
                                  state.playingPreviewSource?.id == effectiveAudio.id
                              ? Icons.stop_circle_rounded
                              : Icons.play_circle_fill_rounded,
                          color: AppColors.secondaryGold,
                          size: 36,
                        ),
                        onPressed: () {
                          if (state.isPreviewPlaying &&
                              state.playingPreviewSource?.id == effectiveAudio.id) {
                            context.read<PrayerAlarmSettingsCubit>().stopAudioPreview();
                          } else {
                            context
                                .read<PrayerAlarmSettingsCubit>()
                                .playAudioPreview(effectiveAudio, isFajr: prayerId == PrayerId.fajr);
                          }
                        },
                      ),
                      title: Text(
                        effectiveAudio.displayName,
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      subtitle: Text(
                        isAudioCustomized
                            ? 'صوت مخصص لهذه الصلاة (اضغط للتغيير)'
                            : 'حسب المؤذن الافتراضي (اضغط للتخصيص)',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: isAudioCustomized
                              ? AppColors.secondaryGold
                              : textColor.withOpacity(0.6),
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: AppColors.secondaryGold,
                        size: 16,
                      ),
                      onTap: () async {
                        context.read<PrayerAlarmSettingsCubit>().stopAudioPreview();
                        final selected = await Navigator.of(context).push<AudioSourceConfig>(
                          MaterialPageRoute(
                            builder: (_) => AdhanCatalogScreen(
                              currentSelectedSource: effectiveAudio,
                              isFajr: prayerId == PrayerId.fajr,
                            ),
                          ),
                        );
                        if (selected != null && context.mounted) {
                          context
                              .read<PrayerAlarmSettingsCubit>()
                              .updatePrayerAudioSource(prayerId, selected);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Volume Level Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader(
                        'مستوى الصوت: ${(effectiveDisplayVolume * 100).round()}% ${isVolumeCustomized ? '(مخصص)' : '(افتراضي)'}',
                        textColor,
                      ),
                      if (isVolumeCustomized)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          ),
                          icon: const Icon(Icons.undo_rounded, size: 16, color: AppColors.secondaryGold),
                          label: Text(
                            'استعادة الافتراضي (${(state.globalAdhanVolume * 100).round()}%)',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              color: AppColors.secondaryGold,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            context
                                .read<PrayerAlarmSettingsCubit>()
                                .updatePrayerVolume(prayerId, null, clearOverride: true);
                          },
                        ),
                    ],
                  ),
                  Card(
                    color: cardColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(Icons.volume_mute_rounded, color: textColor.withOpacity(0.5)),
                          Expanded(
                            child: Slider(
                              value: effectiveDisplayVolume,
                              min: 0.1,
                              max: 1.0,
                              divisions: 9,
                              activeColor: AppColors.secondaryGold,
                              inactiveColor: textColor.withOpacity(0.2),
                              onChanged: (val) {
                                context
                                    .read<PrayerAlarmSettingsCubit>()
                                    .updatePrayerVolume(prayerId, val);
                              },
                            ),
                          ),
                          const Icon(Icons.volume_up_rounded, color: AppColors.secondaryGold),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 4. Vibration Override
                  _buildSectionHeader('الاهتزاز', textColor),
                  Card(
                    color: cardColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          _buildVibrationRadio(
                            context,
                            title:
                                'تلقائي (حسب الإعداد العام: ${state.isGlobalAdhanVibrationEnabled ? "مفعّل" : "معطّل"})',
                            value: null,
                            currentValue: config.isVibrationEnabled,
                            textColor: textColor,
                          ),
                          const Divider(height: 1, indent: 56),
                          _buildVibrationRadio(
                            context,
                            title: 'تفعيل دائماً',
                            value: true,
                            currentValue: config.isVibrationEnabled,
                            textColor: textColor,
                          ),
                          const Divider(height: 1, indent: 56),
                          _buildVibrationRadio(
                            context,
                            title: 'تعطيل دائماً',
                            value: false,
                            currentValue: config.isVibrationEnabled,
                            textColor: textColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 4),
      child: Text(
        title,
        style: GoogleFonts.cairo(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.secondaryGold,
        ),
      ),
    );
  }

  Widget _buildModeRadio(
    BuildContext context, {
    required String title,
    required String subtitle,
    required PrayerAlarmType mode,
    required PrayerAlarmType currentMode,
    required IconData icon,
    required Color textColor,
  }) {
    final isSelected = mode == currentMode;
    return RadioListTile<PrayerAlarmType>(
      value: mode,
      groupValue: currentMode,
      activeColor: AppColors.secondaryGold,
      title: Row(
        children: [
          Icon(icon, color: isSelected ? AppColors.secondaryGold : textColor.withOpacity(0.5), size: 22),
          const SizedBox(width: 12),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(right: 34),
        child: Text(
          subtitle,
          style: GoogleFonts.cairo(
            fontSize: 12,
            color: textColor.withOpacity(0.6),
          ),
        ),
      ),
      onChanged: (val) {
        if (val != null) {
          context.read<PrayerAlarmSettingsCubit>().setPrayerMode(prayerId, val);
        }
      },
    );
  }

  Widget _buildVibrationRadio(
    BuildContext context, {
    required String title,
    required bool? value,
    required bool? currentValue,
    required Color textColor,
  }) {
    return RadioListTile<bool?>(
      value: value,
      groupValue: currentValue,
      activeColor: AppColors.secondaryGold,
      title: Text(
        title,
        style: GoogleFonts.cairo(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
      onChanged: (val) {
        context.read<PrayerAlarmSettingsCubit>().updatePrayerVibration(prayerId, val);
      },
    );
  }
}
