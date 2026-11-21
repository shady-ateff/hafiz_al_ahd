import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_download.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_highlight_state.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_reciter.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/quran_download_queue_progress.dart';
import '../../../../core/utils/app_colors.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../quran/data/datasources/surah_names.dart';
import '../cubit/quran_audio_cubit.dart';
import '../cubit/quran_audio_state.dart';

/// Reading and Memorization Settings Bottom Sheet.
///
/// Allows the user to:
/// 1. Select the active reciter (اختيار الشيخ).
/// 2. Configure recitation scope (Full Surah, Single Ayah, or Custom Range).
/// 3. Set Ayah repetition parameters to assist in Quran memorization (إعدادات التكرار للحفظ).
/// 4. Manage single-Surah offline audio download (تحميل السورة للاستماع أوفلاين).
class QuranAudioSettingsSheet extends StatefulWidget {
  final int? surahNumber;

  const QuranAudioSettingsSheet({super.key, this.surahNumber});

  static Future<void> show(BuildContext context, {int? surahNumber}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BlocProvider.value(
        value: context.read<QuranAudioCubit>(),
        child: QuranAudioSettingsSheet(surahNumber: surahNumber),
      ),
    );
  }

  @override
  State<QuranAudioSettingsSheet> createState() =>
      _QuranAudioSettingsSheetState();
}

class _QuranAudioSettingsSheetState extends State<QuranAudioSettingsSheet> {
  late int _repeatCount; // 1, 3, 5, 10, or 0 (infinite)
  late AudioRepeatMode _selectedMode;
  int? _rangeStart;
  int? _rangeEnd;

  int get _effectiveSurahNumber {
    if (widget.surahNumber != null &&
        widget.surahNumber! >= 1 &&
        widget.surahNumber! <= 114) {
      return widget.surahNumber!;
    }
    final cubitSurah = context.read<QuranAudioCubit>().state.currentSurahNumber;
    if (cubitSurah != null && cubitSurah >= 1 && cubitSurah <= 114) {
      return cubitSurah;
    }
    return 1;
  }

  @override
  void initState() {
    super.initState();
    final cubit = context.read<QuranAudioCubit>();
    _selectedMode = cubit.state.highlightState.repeatMode;
    _rangeStart = cubit.state.highlightState.repeatRangeStart?.ayahNumber ?? 1;
    _rangeEnd = cubit.state.highlightState.repeatRangeEnd?.ayahNumber ?? 5;
    final savedCount = cubit.state.highlightState.repeatCount;
    _repeatCount = savedCount ??
        ((_selectedMode == AudioRepeatMode.off ||
                _selectedMode == AudioRepeatMode.continuous)
            ? 1
            : 3);

    // Trigger reciters load if empty, otherwise query full downloaded reciters immediately
    if (cubit.state.reciters.isEmpty && !cubit.state.isLoadingReciters) {
      cubit.init();
    } else {
      cubit.checkAllDownloadedReciters();
    }

    // Check single-Surah download status for active Surah & Reciter
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reciterId = cubit.state.selectedReciter?.id ?? '7';
      cubit.checkDownloadStatus(
        surahNumber: _effectiveSurahNumber,
        reciterId: reciterId,
      );
      cubit.checkFullQuranStatus(reciterId);
      cubit.checkAllDownloadedReciters();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.darkText;
    final secondaryText = isDark ? Colors.white70 : Colors.black54;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: AppColors.secondaryGold.withValues(alpha: 0.3),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Drag Handle
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Sheet Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryGold.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: AppColors.secondaryGold,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'إعدادات التلاوة والحفظ',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: secondaryText),
                  ),
                ],
              ),
            ),
            const Divider(height: 24, thickness: 0.5),

            Expanded(
              child: BlocBuilder<QuranAudioCubit, QuranAudioState>(
                builder: (context, state) {
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      // Section 1: Reciter Selection
                      _buildSectionHeader(
                        'اختيار القارئ',
                        Icons.person_outline_rounded,
                        textColor,
                      ),
                      const SizedBox(height: 10),
                      _buildRecitersList(state, isDark),

                      const SizedBox(height: 24),

                      // Section 2: Recitation Scope / Range
                      _buildSectionHeader(
                        'نطاق التلاوة والتكرار',
                        Icons.repeat_rounded,
                        textColor,
                      ),
                      const SizedBox(height: 10),
                      _buildRepeatModeSelector(isDark),

                      if (_selectedMode == AudioRepeatMode.range) ...[
                        const SizedBox(height: 14),
                        _buildRangeConfig(state, isDark),
                      ],

                      if (_selectedMode == AudioRepeatMode.surah ||
                          _selectedMode == AudioRepeatMode.singleAyah ||
                          _selectedMode == AudioRepeatMode.range) ...[
                        const SizedBox(height: 24),

                        // Section 3: Repetition Count
                        _buildSectionHeader(
                          _getRepeatSectionTitle(_selectedMode),
                          Icons.repeat_one_rounded,
                          textColor,
                        ),
                        const SizedBox(height: 10),
                        _buildRepeatCountChips(isDark),
                      ],

                      // Section 4: Single-Surah Offline Download (QA.5 Phase 5.5)
                      const SizedBox(height: 24),
                      _buildSectionHeader(
                        'تحميل السورة للاستماع دون إنترنت',
                        Icons.cloud_download_outlined,
                        textColor,
                      ),
                      const SizedBox(height: 10),
                      _buildDownloadSection(state, isDark, textColor, secondaryText),

                      // Section 5: Full-Quran Offline Download (QA.6 Phase 6.7)
                      const SizedBox(height: 24),
                      _buildSectionHeader(
                        'تحميل المصحف كاملاً للاستماع دون إنترنت',
                        Icons.library_books_rounded,
                        textColor,
                      ),
                      const SizedBox(height: 10),
                      _buildFullQuranDownloadSection(state, isDark, textColor, secondaryText),

                      const SizedBox(height: 30),
                    ],
                  );
                },
              ),
            ),

            // Apply Button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondaryGold,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                    ),
                    onPressed: () => _applySettings(context),
                    child: const Text(
                      'حفظ وتطبيق الإعدادات',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.secondaryGold),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecitersList(QuranAudioState state, bool isDark) {
    if (state.isLoadingReciters && state.reciters.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: AppLoader(width: 58, height: 58),
        ),
      );
    }

    final reciters = state.reciters;
    if (reciters.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'تعذر تحميل قائمة القراء',
              style: TextStyle(fontFamily: 'Tajawal', fontSize: 13),
            ),
            TextButton.icon(
              onPressed: () => context.read<QuranAudioCubit>().init(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'إعادة المحاولة',
                style: TextStyle(fontFamily: 'Tajawal'),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: reciters.length,
        separatorBuilder: (_, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final reciter = reciters[index];
          final isSelected = state.selectedReciter?.id == reciter.id;
          final queueProgress = state.fullQuranProgress;
          final isReciterDownloading = queueProgress != null &&
              queueProgress.reciterId == reciter.id &&
              queueProgress.isRunning;
          final isReciterPaused = queueProgress != null &&
              queueProgress.reciterId == reciter.id &&
              queueProgress.status.isPaused;
          final isReciterCompleted = (state.isFullQuranDownloaded && state.selectedReciter?.id == reciter.id) ||
              state.downloadedReciterIds.contains(reciter.id) ||
              (queueProgress != null && queueProgress.reciterId == reciter.id && queueProgress.isCompleted);

          return InkWell(
            onTap: () {
              context.read<QuranAudioCubit>().selectReciter(reciter.id);
              context.read<QuranAudioCubit>().checkDownloadStatus(
                    surahNumber: _effectiveSurahNumber,
                    reciterId: reciter.id,
                  );
              context.read<QuranAudioCubit>().checkFullQuranStatus(reciter.id);
            },
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 140,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.secondaryGold.withValues(alpha: 0.18)
                    : (isDark ? const Color(0xFF282828) : Colors.grey[100]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? AppColors.secondaryGold
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: isSelected
                        ? AppColors.secondaryGold
                        : (isDark ? Colors.grey[800] : Colors.grey[300]),
                    child: Text(
                      reciter.arabicName.isNotEmpty
                          ? reciter.arabicName[0]
                          : 'ق',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Colors.white
                            : AppColors.secondaryGold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    reciter.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isSelected
                          ? AppColors.secondaryGold
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  if (isReciterDownloading) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryGold.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.secondaryGold.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.downloading_rounded,
                              size: 11,
                              color: AppColors.secondaryGold,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'جاري التحميل...',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondaryGold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (isReciterPaused) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pause_circle_rounded, size: 10, color: Colors.orange),
                            SizedBox(width: 3),
                            Text(
                              'متوقف مؤقتاً',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (isReciterCompleted) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.offline_pin_rounded, size: 10, color: Colors.green),
                            SizedBox(width: 3),
                            Text(
                              'محمل يعمل بلا إنترنت',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (reciter.style != null) ...[
                    Text(
                      reciter.style!,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 10,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRepeatModeSelector(bool isDark) {
    final generalModes = [
      {
        'mode': AudioRepeatMode.continuous,
        'label': 'مستمر',
        'icon': Icons.all_inclusive_rounded,
      },
      {
        'mode': AudioRepeatMode.off,
        'label': 'سورة كاملة',
        'icon': Icons.format_list_numbered_rtl_rounded,
      },
    ];

    final repeatModes = [
      {
        'mode': AudioRepeatMode.surah,
        'label': 'تكرار سورة',
        'icon': Icons.repeat_rounded,
      },
      {
        'mode': AudioRepeatMode.singleAyah,
        'label': 'تكرار آية',
        'icon': Icons.repeat_one_rounded,
      },
      {
        'mode': AudioRepeatMode.range,
        'label': 'نطاق (حفظ)',
        'icon': Icons.tune_rounded,
      },
    ];

    Widget buildButton(Map<String, dynamic> m) {
      final mode = m['mode'] as AudioRepeatMode;
      final label = m['label'] as String;
      final icon = m['icon'] as IconData;
      final isSelected = _selectedMode == mode;

      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedMode = mode;
                if (mode == AudioRepeatMode.continuous ||
                    mode == AudioRepeatMode.off) {
                  _repeatCount = 1;
                } else if (_repeatCount <= 1) {
                  _repeatCount = 3;
                }
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 6,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.secondaryGold.withValues(alpha: 0.18)
                    : (isDark ? const Color(0xFF282828) : Colors.grey[100]),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? AppColors.secondaryGold
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isSelected
                        ? AppColors.secondaryGold
                        : (isDark ? Colors.white70 : Colors.black54),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isSelected
                          ? AppColors.secondaryGold
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(children: generalModes.map(buildButton).toList()),
        const SizedBox(height: 8),
        Row(children: repeatModes.map(buildButton).toList()),
      ],
    );
  }

  Widget _buildRangeConfig(QuranAudioState state, bool isDark) {
    final maxAyahs = state.currentSurahAudio?.ayahTimings.length ?? 7;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF282828) : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'حدد بداية ونهاية النطاق (سورة ${state.currentSurahNumber != null ? getSurahName(state.currentSurahNumber!) : ''}):',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildNumberStepper(
                  label: 'من الآية',
                  value: _rangeStart ?? 1,
                  min: 1,
                  max: (_rangeEnd ?? maxAyahs).clamp(1, maxAyahs),
                  onChanged: (v) => setState(() => _rangeStart = v),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildNumberStepper(
                  label: 'إلى الآية',
                  value: _rangeEnd ?? maxAyahs,
                  min: (_rangeStart ?? 1).clamp(1, maxAyahs),
                  max: maxAyahs,
                  onChanged: (v) => setState(() => _rangeEnd = v),
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNumberStepper({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontSize: 12,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: value > min ? () => onChanged(value - 1) : null,
              ),
              Text(
                '$value',
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: value < max ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getRepeatSectionTitle(AudioRepeatMode mode) {
    switch (mode) {
      case AudioRepeatMode.surah:
        return 'عدد مرات تكرار السورة';
      case AudioRepeatMode.singleAyah:
        return 'عدد مرات تكرار الآية';
      case AudioRepeatMode.range:
        return 'عدد مرات تكرار النطاق';
      default:
        return 'عدد مرات التكرار';
    }
  }

  Widget _buildRepeatCountChips(bool isDark) {
    final counts = [
      {'count': 1, 'label': 'مرة واحدة'},
      {'count': 2, 'label': 'مرتان'},
      {'count': 3, 'label': '٣ مرات'},
      {'count': 5, 'label': '٥ مرات'},
      {'count': 10, 'label': '١٠ مرات'},
      {'count': 0, 'label': 'مستمر ∞'},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: counts.map((item) {
        final count = item['count'] as int;
        final label = item['label'] as String;
        final isSelected = _repeatCount == count;

        return ChoiceChip(
          label: Text(
            label,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
          selected: isSelected,
          selectedColor: AppColors.secondaryGold,
          backgroundColor: isDark ? const Color(0xFF282828) : Colors.grey[100],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(
            color: isSelected ? AppColors.secondaryGold : Colors.transparent,
          ),
          onSelected: (selected) {
            if (selected) {
              setState(() {
                _repeatCount = count;
              });
            }
          },
        );
      }).toList(),
    );
  }

  void _applySettings(BuildContext context) {
    final cubit = context.read<QuranAudioCubit>();

    cubit.setRepeatMode(
      _selectedMode,
      rangeStartAyah: _selectedMode == AudioRepeatMode.range
          ? _rangeStart
          : null,
      rangeEndAyah: _selectedMode == AudioRepeatMode.range ? _rangeEnd : null,
      repeatCount: _repeatCount > 0 ? _repeatCount : null,
    );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم تطبيق إعدادات التلاوة والحفظ بنجاح',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // -------------------------------------------------------------
  // Single-Surah Offline Download UI (QA.5 Phase 5.5)
  // -------------------------------------------------------------

  Widget _buildDownloadSection(
    QuranAudioState state,
    bool isDark,
    Color textColor,
    Color secondaryText,
  ) {
    final surahNum = _effectiveSurahNumber;
    final surahName = getSurahName(surahNum);
    final reciter = state.selectedReciter;
    final reciterId = reciter?.id ?? '7';
    final reciterName = reciter?.arabicName ?? 'القارئ';

    final displayStatus = state.getDownloadDisplayStatus(surahNum, reciterId);
    final progress = state.getDownloadProgress(surahNum, reciterId);
    final cubit = context.read<QuranAudioCubit>();
    final isCompleted = displayStatus == AudioDownloadDisplayStatus.completed;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isCompleted ? AppColors.goldenGradient : null,
        color: isCompleted
            ? null
            : (isDark ? const Color(0xFF282828) : Colors.grey[50]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCompleted
              ? AppColors.lightGold.withValues(alpha: 0.6)
              : AppColors.secondaryGold.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: isCompleted
            ? [
                BoxShadow(
                  color: AppColors.secondaryGold.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? Colors.black.withValues(alpha: 0.12)
                      : AppColors.secondaryGold.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCompleted
                      ? Icons.check_circle_rounded
                      : Icons.cloud_download_rounded,
                  color: isCompleted
                      ? const Color(0xFF1E1E1E)
                      : AppColors.secondaryGold,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سورة $surahName — $reciterName',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isCompleted ? const Color(0xFF1E1E1E) : textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getDownloadSubtitle(displayStatus, progress),
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        fontWeight: isCompleted ? FontWeight.w500 : FontWeight.normal,
                        color: isCompleted
                            ? const Color(0xFF382E09)
                            : (displayStatus == AudioDownloadDisplayStatus.failed
                                ? Colors.redAccent
                                : secondaryText),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDownloadActionRow(
            displayStatus: displayStatus,
            progress: progress,
            surahNumber: surahNum,
            reciterId: reciterId,
            cubit: cubit,
            isDark: isDark,
            secondaryText: secondaryText,
          ),
        ],
      ),
    );
  }

  String _getDownloadSubtitle(
    AudioDownloadDisplayStatus status,
    DownloadProgress? progress,
  ) {
    switch (status) {
      case AudioDownloadDisplayStatus.completed:
        return 'محملة ومحفوظة محليًا على الجهاز';
      case AudioDownloadDisplayStatus.downloading:
        final ratio = progress?.progressRatio ?? 0.0;
        final pct = (ratio * 100).toInt();
        if (pct > 0) {
          return 'جاري التحميل... $pct%';
        }
        return 'جاري الاتصال وبدء التحميل...';
      case AudioDownloadDisplayStatus.paused:
        final ratio = progress?.progressRatio ?? 0.0;
        final pct = (ratio * 100).toInt();
        if (pct > 0) {
          return 'التحميل متوقف مؤقتًا ($pct%)';
        }
        return 'التحميل متوقف مؤقتًا';
      case AudioDownloadDisplayStatus.verifying:
        return 'جاري التحقق من سلامة الملف الصوتي...';
      case AudioDownloadDisplayStatus.failed:
        return _formatUserFriendlyError(progress?.lastError);
      case AudioDownloadDisplayStatus.cancelled:
        return 'تم إلغاء التحميل';
      case AudioDownloadDisplayStatus.notDownloaded:
        return 'غير محملة — اضغط للتحميل والاستماع دون إنترنت';
    }
  }

  String _formatUserFriendlyError(String? rawError) {
    if (rawError == null || rawError.trim().isEmpty) {
      return 'تعذر إتمام التحميل. يرجى التحقق من اتصال الإنترنت وإعادة المحاولة.';
    }

    final lower = rawError.toLowerCase();

    // 1. Network, DNS, Connectivity & Socket errors
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('no address associated with hostname') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('connection closed') ||
        lower.contains('clientexception') ||
        lower.contains('handshakeexception') ||
        lower.contains('timeoutexception') ||
        lower.contains('timed out')) {
      return 'تعذر الاتصال بالخادم. يرجى التحقق من اتصال الإنترنت وإعادة المحاولة.';
    }

    // 2. Storage & Permissions
    if (lower.contains('no space left') || lower.contains('enospc') || lower.contains('disk full')) {
      return 'المساحة التخزينية على جهازك غير كافية لإتمام التحميل.';
    }
    if (lower.contains('permission denied') || lower.contains('eacces') || lower.contains('access denied')) {
      return 'تعذر حفظ الملف بسبب نقص صلاحيات التخزين على الجهاز.';
    }

    // 3. HTTP Server Status Codes
    if (lower.contains('404') || lower.contains('not found')) {
      return 'الملف الصوتي غير متوفر على الخادم لهذا القارئ.';
    }
    if (lower.contains('500') || lower.contains('502') || lower.contains('503') || lower.contains('504')) {
      return 'الخادم غير متاح حاليًا. يرجى المحاولة في وقت لاحق.';
    }

    // 4. File integrity
    if (lower.contains('stream truncated') || lower.contains('checksum mismatch') || lower.contains('corrupt')) {
      return 'فشل التحقق من اكتمال الملف الصوتي. يرجى إعادة المحاولة.';
    }

    // If it contains Arabic letters and no raw exception traces, it's already localized
    final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(rawError);
    final hasExceptionKeywords = lower.contains('exception') ||
        lower.contains('failed') ||
        lower.contains('errno') ||
        lower.contains('http') ||
        lower.contains('os error');

    if (hasArabic && !hasExceptionKeywords) {
      return rawError;
    }

    return 'تعذر إتمام التحميل. يرجى التحقق من اتصال الإنترنت وإعادة المحاولة.';
  }

  Widget _buildDownloadActionRow({
    required AudioDownloadDisplayStatus displayStatus,
    required DownloadProgress? progress,
    required int surahNumber,
    required String reciterId,
    required QuranAudioCubit cubit,
    required bool isDark,
    required Color secondaryText,
  }) {
    switch (displayStatus) {
      case AudioDownloadDisplayStatus.notDownloaded:
      case AudioDownloadDisplayStatus.cancelled:
        return SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton.icon(
            key: const Key('download_surah_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondaryGold,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              cubit.startSurahDownload(
                surahNumber: surahNumber,
                reciterId: reciterId,
              );
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text(
              'تحميل السورة الآن',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );

      case AudioDownloadDisplayStatus.downloading:
        final ratio = progress?.progressRatio;
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                key: const Key('download_progress_bar'),
                value: (ratio != null && ratio > 0.0) ? ratio : null,
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.secondaryGold),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('download_pause_button'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.secondaryGold),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      cubit.pauseSurahDownload(
                        surahNumber: surahNumber,
                        reciterId: reciterId,
                      );
                    },
                    icon: const Icon(Icons.pause_rounded,
                        size: 16, color: AppColors.secondaryGold),
                    label: const Text(
                      'إيقاف مؤقت',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        color: AppColors.secondaryGold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('download_cancel_button'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      cubit.cancelSurahDownload(
                        surahNumber: surahNumber,
                        reciterId: reciterId,
                      );
                    },
                    icon: const Icon(Icons.close_rounded,
                        size: 16, color: Colors.redAccent),
                    label: const Text(
                      'إلغاء',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      case AudioDownloadDisplayStatus.paused:
        final ratio = progress?.progressRatio ?? 0.0;
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                key: const Key('download_paused_progress_bar'),
                value: ratio > 0.0 ? ratio : null,
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.orange),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    key: const Key('download_resume_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondaryGold,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      cubit.startSurahDownload(
                        surahNumber: surahNumber,
                        reciterId: reciterId,
                      );
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text(
                      'استئناف التحميل',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('download_cancel_paused_button'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      cubit.cancelSurahDownload(
                        surahNumber: surahNumber,
                        reciterId: reciterId,
                      );
                    },
                    icon: const Icon(Icons.close_rounded,
                        size: 16, color: Colors.redAccent),
                    label: const Text(
                      'إلغاء',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      case AudioDownloadDisplayStatus.verifying:
        return const Row(
          key: Key('download_verifying_row'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.secondaryGold),
              ),
            ),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'التحقق من صحة الملف والترقية الذرية...',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 12,
                  color: AppColors.secondaryGold,
                ),
              ),
            ),
          ],
        );

      case AudioDownloadDisplayStatus.completed:
        return Row(
          key: const Key('download_completed_row'),
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.offline_pin_rounded,
                    color: Color(0xFF1E1E1E),
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'جاهزة للاستماع دون اتصال',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                      color: Color(0xFF1E1E1E),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: const Key('delete_download_button'),
                onTap: () {
                  cubit.deleteDownloadedSurah(
                    surahNumber: surahNumber,
                    reciterId: reciterId,
                  );
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFF7A1C1C),
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'حذف',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          color: Color(0xFF7A1C1C),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

      case AudioDownloadDisplayStatus.failed:
        return SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton.icon(
            key: const Key('download_retry_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              cubit.retrySurahDownload(
                surahNumber: surahNumber,
                reciterId: reciterId,
              );
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text(
              'إعادة المحاولة',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Full-Quran Download UI (QA.6 Phase 6.7)
  // ---------------------------------------------------------------------------

  Widget _buildFullQuranDownloadSection(
    QuranAudioState state,
    bool isDark,
    Color textColor,
    Color secondaryText,
  ) {
    final cubit = context.read<QuranAudioCubit>();
    final reciter = state.selectedReciter ?? AudioReciter.kDefaultReciter;
    final progress = state.fullQuranProgress;
    final hasActiveQueue = progress != null &&
        progress.reciterId == reciter.id &&
        !progress.status.isCancelled;

    final isCompleted = state.isFullQuranDownloaded ||
        (hasActiveQueue && progress.isCompleted);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isCompleted ? AppColors.goldenGradient : null,
        color: isCompleted
            ? null
            : (isDark ? const Color(0xFF282828) : Colors.grey[50]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCompleted
              ? AppColors.lightGold.withValues(alpha: 0.6)
              : AppColors.secondaryGold.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: isCompleted
            ? [
                BoxShadow(
                  color: AppColors.secondaryGold.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? Colors.black.withValues(alpha: 0.12)
                      : AppColors.secondaryGold.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCompleted
                      ? Icons.check_circle_rounded
                      : Icons.library_books_rounded,
                  color: isCompleted
                      ? const Color(0xFF1E1E1E)
                      : AppColors.secondaryGold,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          'المصحف كاملاً — ${reciter.displayName}',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isCompleted ? const Color(0xFF1E1E1E) : textColor,
                          ),
                        ),
                        if (hasActiveQueue && progress.isRunning) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryGold.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.secondaryGold.withValues(alpha: 0.5),
                                width: 0.8,
                              ),
                            ),
                            child: const Text(
                              'جاري التحميل...',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondaryGold,
                              ),
                            ),
                          ),
                        ] else if (isCompleted) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'محمل يعمل بلا إنترنت',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E1E1E),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getFullQuranSubtitle(isCompleted, hasActiveQueue, progress),
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        fontWeight: isCompleted ? FontWeight.w500 : FontWeight.normal,
                        color: isCompleted
                            ? const Color(0xFF382E09)
                            : (hasActiveQueue && progress.status.isFailed
                                ? Colors.redAccent
                                : secondaryText),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFullQuranActionRow(
            isCompleted: isCompleted,
            hasActiveQueue: hasActiveQueue,
            progress: progress,
            reciter: reciter,
            cubit: cubit,
            isDark: isDark,
            secondaryText: secondaryText,
          ),
        ],
      ),
    );
  }

  String _getFullQuranSubtitle(
    bool isCompleted,
    bool hasActiveQueue,
    QuranDownloadQueueProgress? progress,
  ) {
    if (isCompleted) {
      return 'جميع السور (114 سورة) محملة وجاهزة للاستماع دون إنترنت';
    }
    if (hasActiveQueue && progress != null) {
      if (progress.isRunning) {
        final activeName = progress.activeSurahNumber != null
            ? ' • سورة ${getSurahName(progress.activeSurahNumber!)}'
            : '';
        return 'تم تحميل ${progress.completedItems} من 114 سورة (${(progress.aggregateRatio * 100).toInt()}%)$activeName';
      } else if (progress.status.isPaused) {
        return 'متوقف مؤقتاً • تم تحميل ${progress.completedItems} من 114 سورة';
      } else if (progress.status.isFailed) {
        return progress.lastError ?? 'فشل التحميل • اضغط لإعادة المحاولة';
      }
    }
    return 'تحميل جميع سور القرآن (114 سورة) للاستماع دون اتصال';
  }

  Widget _buildFullQuranActionRow({
    required bool isCompleted,
    required bool hasActiveQueue,
    required QuranDownloadQueueProgress? progress,
    required AudioReciter reciter,
    required QuranAudioCubit cubit,
    required bool isDark,
    required Color secondaryText,
  }) {
    if (isCompleted) {
      return Row(
        children: [
          const Icon(Icons.offline_pin_rounded, size: 16, color: Color(0xFF1E1E1E)),
          const SizedBox(width: 6),
          const Text(
            'جاهز للاستماع دون اتصال',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E1E1E),
            ),
          ),
        ],
      );
    }

    if (hasActiveQueue && progress != null) {
      if (progress.isRunning) {
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.aggregateRatio > 0 ? progress.aggregateRatio : null,
                minHeight: 6,
                backgroundColor: isDark ? Colors.white12 : Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.secondaryGold),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondaryGold,
                      side: const BorderSide(color: AppColors.secondaryGold, width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () => cubit.pauseFullQuranDownload(progress.queueId),
                    icon: const Icon(Icons.pause_rounded, size: 18),
                    label: const Text('إيقاف مؤقت', style: TextStyle(fontFamily: 'Tajawal', fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.7), width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () => cubit.cancelFullQuranDownload(progress.queueId),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('إلغاء التحميل', style: TextStyle(fontFamily: 'Tajawal', fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
        );
      } else if (progress.status.isPaused) {
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.aggregateRatio,
                minHeight: 6,
                backgroundColor: isDark ? Colors.white12 : Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondaryGold,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      elevation: 0,
                    ),
                    onPressed: () => cubit.resumeFullQuranDownload(
                      queueId: progress.queueId,
                      reciterId: reciter.id,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('استئناف التحميل', style: TextStyle(fontFamily: 'Tajawal', fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.7), width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () => cubit.cancelFullQuranDownload(progress.queueId),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('إلغاء التحميل', style: TextStyle(fontFamily: 'Tajawal', fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
        );
      } else if (progress.status.isFailed) {
        return Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 0,
                ),
                onPressed: () => cubit.retryFullQuranDownload(
                  queueId: progress.queueId,
                  reciterId: reciter.id,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Tajawal', fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: secondaryText,
                  side: BorderSide(color: secondaryText.withValues(alpha: 0.5), width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onPressed: () => cubit.cancelFullQuranDownload(progress.queueId),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal', fontSize: 13)),
              ),
            ),
          ],
        );
      }
    }

    // Idle: Not started yet
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? const Color(0xFF383838) : Colors.white,
          foregroundColor: AppColors.secondaryGold,
          side: const BorderSide(color: AppColors.secondaryGold, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 10),
          elevation: 0,
        ),
        onPressed: () => _handleStartFullQuranDownload(context, cubit, reciter),
        icon: const Icon(Icons.download_for_offline_rounded, size: 18),
        label: const Text(
          'بدء تحميل المصحف كاملاً',
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _handleStartFullQuranDownload(
    BuildContext context,
    QuranAudioCubit cubit,
    AudioReciter reciter,
  ) async {
    final preflight = await cubit.checkFullQuranPreflight(reciterId: reciter.id);

    if (!context.mounted) return;

    if (preflight != null && preflight.isInsufficient) {
      final reqMb = (preflight.requiredBytes! / (1024 * 1024)).toStringAsFixed(1);
      final availMb = (preflight.availableBytes! / (1024 * 1024)).toStringAsFixed(1);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('المساحة التخزينية غير كافية', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
          content: Text(
            'المساحة المطلوبة: $reqMb ميجابايت\nالمساحة المتاحة: $availMb ميجابايت\n\nيرجى توفير مساحة كافية على الجهاز ثم إعادة المحاولة.',
            style: const TextStyle(fontFamily: 'Tajawal', height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسناً', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    if (preflight != null && preflight.isIndeterminate) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('تنبيه المساحة التخزينية', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
          content: const Text(
            'حجم بعض السور غير محدد مسبقًا. لا يمكن حساب المساحة الإجمالية بدقة. هل ترغب في المتابعة؟',
            style: TextStyle(fontFamily: 'Tajawal', height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondaryGold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                cubit.startFullQuranDownload(reciterId: reciter.id);
              },
              child: const Text('متابعة التحميل', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    // Sufficient space confirmation
    final reqMbText = preflight?.requiredBytes != null
        ? '\n\nالمساحة التقديرية المطلوبة: حوالي ${(preflight!.requiredBytes! / (1024 * 1024)).toStringAsFixed(1)} ميجابايت.'
        : '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('تحميل المصحف كاملاً', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
        content: Text(
          'سيتم تحميل جميع سور القرآن الكريم (114 سورة) للقارئ ${reciter.displayName} لتكون متاحة دائماً دون اتصال بالإنترنت.$reqMbText',
          style: const TextStyle(fontFamily: 'Tajawal', height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondaryGold,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              cubit.startFullQuranDownload(reciterId: reciter.id);
            },
            child: const Text('بدء التحميل', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
