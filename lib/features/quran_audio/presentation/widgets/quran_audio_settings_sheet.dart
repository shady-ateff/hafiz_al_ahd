import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/features/quran_audio/domain/entities/audio_highlight_state.dart';
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
class QuranAudioSettingsSheet extends StatefulWidget {
  const QuranAudioSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BlocProvider.value(
        value: context.read<QuranAudioCubit>(),
        child: const QuranAudioSettingsSheet(),
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

  @override
  void initState() {
    super.initState();
    final cubit = context.read<QuranAudioCubit>();
    _selectedMode = cubit.state.highlightState.repeatMode;
    _rangeStart = cubit.state.highlightState.repeatRangeStart?.ayahNumber ?? 1;
    _rangeEnd = cubit.state.highlightState.repeatRangeEnd?.ayahNumber ?? 5;
    _repeatCount = _selectedMode == AudioRepeatMode.off ? 1 : 3;

    // Trigger reciters load if empty
    if (cubit.state.reciters.isEmpty && !cubit.state.isLoadingReciters) {
      cubit.init();
    }
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
                  Text(
                    'إعدادات التلاوة والحفظ',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
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

                      const SizedBox(height: 24),

                      // Section 3: Memorization Repeat Counts
                      _buildSectionHeader(
                        'تكرار الحفظ (مرات إعادة الآية)',
                        Icons.school_outlined,
                        textColor,
                      ),
                      const SizedBox(height: 10),
                      _buildRepeatCountChips(isDark),

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
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color,
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

          return InkWell(
            onTap: () {
              context.read<QuranAudioCubit>().selectReciter(reciter.id);
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
                    reciter.arabicName.isNotEmpty
                        ? reciter.arabicName
                        : reciter.name,
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
                  if (reciter.style != null) ...[
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
    final modes = [
      {
        'mode': AudioRepeatMode.off,
        'label': 'سورة كاملة',
        'icon': Icons.format_list_numbered_rtl_rounded,
      },
      {
        'mode': AudioRepeatMode.singleAyah,
        'label': 'تكرار آية',
        'icon': Icons.repeat_one_rounded,
      },
      {
        'mode': AudioRepeatMode.range,
        'label': 'نطاق آيات (حفظ)',
        'icon': Icons.tune_rounded,
      },
    ];

    return Row(
      children: modes.map((m) {
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
                });
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
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
      }).toList(),
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

  Widget _buildRepeatCountChips(bool isDark) {
    final counts = [
      {'count': 1, 'label': 'مرة واحدة'},
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
}
