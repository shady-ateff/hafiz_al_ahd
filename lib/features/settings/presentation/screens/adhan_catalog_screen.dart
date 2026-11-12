import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/prayer_alarm_settings_state.dart';

class AdhanCatalogScreen extends StatefulWidget {
  final AudioSourceConfig currentSelectedSource;
  final bool isFajr;

  const AdhanCatalogScreen({
    super.key,
    required this.currentSelectedSource,
    this.isFajr = false,
  });

  @override
  State<AdhanCatalogScreen> createState() => _AdhanCatalogScreenState();
}

class _AdhanCatalogScreenState extends State<AdhanCatalogScreen> {
  late AudioSourceConfig _selected;

  static const List<BuiltInAudioSource> _builtInSources = [
    AudioSourceConfig.defaultMishary,
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.currentSelectedSource;
  }

  @override
  void dispose() {
    // Ensure any playing preview is halted when navigating away
    // Handled safely without context across async gap
    super.dispose();
  }

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
            'اختيار صوت الأذان',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'الأصوات المدمجة',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondaryGold,
                ),
              ),
            ),
            ..._builtInSources.map((source) {
              final isSelected = _selected.id == source.id ||
                  (_selected is BuiltInAudioSource &&
                      (_selected.id == 'builtIn:default_general' ||
                          _selected.id == 'builtIn:default_fajr'));

              return BlocBuilder<PrayerAlarmSettingsCubit, PrayerAlarmSettingsState>(
                builder: (context, state) {
                  final isPlayingThis =
                      state.isPreviewPlaying && state.playingPreviewSource?.id == source.id;

                  return Card(
                    color: cardColor,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isSelected
                          ? const BorderSide(color: AppColors.secondaryGold, width: 2)
                          : BorderSide.none,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: IconButton(
                        icon: Icon(
                          isPlayingThis
                              ? Icons.stop_circle_rounded
                              : Icons.play_circle_fill_rounded,
                          color: AppColors.secondaryGold,
                          size: 36,
                        ),
                        onPressed: () {
                          if (isPlayingThis) {
                            context.read<PrayerAlarmSettingsCubit>().stopAudioPreview();
                          } else {
                            context
                                .read<PrayerAlarmSettingsCubit>()
                                .playAudioPreview(source, isFajr: widget.isFajr);
                          }
                        },
                      ),
                      title: Text(
                        source.displayName,
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      subtitle: Text(
                        widget.isFajr
                            ? 'يشمل أذان الفجر (الصلاة خير من النوم)'
                            : 'الأذان لجميع الصلوات (افتراضي)',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: textColor.withOpacity(0.6),
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: AppColors.secondaryGold)
                          : OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.secondaryGold),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () {
                                setState(() => _selected = source);
                                context.read<PrayerAlarmSettingsCubit>().stopAudioPreview();
                                Navigator.of(context).pop(source);
                              },
                              child: Text(
                                'اختيار',
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  color: AppColors.secondaryGold,
                                ),
                              ),
                            ),
                      onTap: () {
                        setState(() => _selected = source);
                        context.read<PrayerAlarmSettingsCubit>().stopAudioPreview();
                        Navigator.of(context).pop(source);
                      },
                    ),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

