import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/app_colors.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../quran/data/datasources/surah_names.dart';
import '../../domain/entities/audio_highlight_state.dart';
import '../cubit/quran_audio_cubit.dart';
import '../cubit/quran_audio_state.dart';
import 'quran_audio_settings_sheet.dart';

/// Dynamic Island-inspired Floating Audio Player for the Quran screen.
///
/// **INTERACTIONS**:
/// - **Double Tap (`onDoubleTap`)**: Instantly toggles Play / Pause.
/// - **Single Tap (`onTap`)**: Pops open / collapses the expanded details view:
///   - Surah Name & Current Ayah Number.
///   - Reciter Name (الشيخ).
///   - Remaining recitation duration (المدة المتبقية للسورة).
///   - Interactive seek slider & playback controls.
/// - **Long Press (`onLongPress`)**: Opens the Reading & Recitation Settings Sheet
///   (Reciter change, custom range selection, and Ayah repetition for memorization).
class QuranAudioDynamicIsland extends StatefulWidget {
  final VoidCallback? onSettingsTap;
  final int? defaultSurahNumber;
  final int? defaultStartAyahNumber;
  final bool isFullScreen;

  const QuranAudioDynamicIsland({
    super.key,
    this.onSettingsTap,
    this.defaultSurahNumber,
    this.defaultStartAyahNumber,
    this.isFullScreen = false,
  });

  @override
  State<QuranAudioDynamicIsland> createState() =>
      _QuranAudioDynamicIslandState();
}

class _QuranAudioDynamicIslandState extends State<QuranAudioDynamicIsland>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant QuranAudioDynamicIsland oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFullScreen && _isExpanded) {
      setState(() => _isExpanded = false);
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hours = d.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String _formatRemainingDuration(Duration current, Duration total) {
    if (total <= current || total == Duration.zero) return '00:00';
    final remaining = total - current;
    return '-${_formatDuration(remaining)}';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QuranAudioCubit, QuranAudioState>(
      builder: (context, state) {
        final cubit = context.read<QuranAudioCubit>();
        final isAudioActive =
            state.isPlaying ||
            state.isPaused ||
            state.isLoading ||
            state.isBuffering;
        final surahNum = (isAudioActive && state.currentSurahNumber != null)
            ? state.currentSurahNumber!
            : (widget.defaultSurahNumber ?? state.currentSurahNumber ?? 1);
        final surahTitle = 'سورة ${getSurahName(surahNum)}';
        final activeAyahNum = (isAudioActive && state.highlightState.activeAyah?.ayahNumber != null)
            ? state.highlightState.activeAyah!.ayahNumber
            : (widget.defaultStartAyahNumber ?? (widget.defaultSurahNumber != null ? 1 : null));
        final ayahText = activeAyahNum != null ? 'الآية $activeAyahNum' : '';
        final reciterName = state.selectedReciter?.arabicName.isNotEmpty == true
            ? state.selectedReciter!.arabicName
            : (state.selectedReciter?.name ?? 'مشاري راشد العفاسي');

        final remainingStr = _formatRemainingDuration(
          state.currentPosition,
          state.totalDuration,
        );

        final screenWidth = MediaQuery.of(context).size.width;
        final maxAllowed = (screenWidth - 28.0).clamp(160.0, double.infinity);
        final targetWidth = _isExpanded
            ? (screenWidth - 28.0).clamp(280.0, 520.0).clamp(160.0, maxAllowed)
            : (state.isPlaying ? 230.0 : 190.0).clamp(160.0, maxAllowed);
        final targetRadius = _isExpanded ? 28.0 : 30.0;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              width: targetWidth,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(targetRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: _isExpanded ? 24 : 14,
                    spreadRadius: _isExpanded ? 3 : 1,
                    offset: const Offset(0, 6),
                  ),
                  if (state.isPlaying)
                    BoxShadow(
                      color: AppColors.secondaryGold.withValues(alpha: 0.2),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(targetRadius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    // padding: EdgeInsets.symmetric(
                    //   horizontal: _isExpanded ? 18 : 12,
                    //   vertical: _isExpanded ? 16 : 6,
                    // ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x99242424), // Frosted smoked glass sheen
                          Color(0xB8121212), // Deep translucent dark glass
                        ],
                      ),
                      borderRadius: BorderRadius.circular(targetRadius),
                      border: Border.all(
                        color: AppColors.secondaryGold.withValues(
                          alpha: _isExpanded ? 0.65 : 0.45,
                        ),
                        width: _isExpanded ? 1.4 : 1.1,
                      ),
                    ),
                    child: AnimatedCrossFade(
                      duration: const Duration(milliseconds: 280),
                      firstCurve: Curves.easeOutCubic,
                      secondCurve: Curves.easeInCubic,
                      layoutBuilder:
                          (topChild, topChildKey, bottomChild, bottomChildKey) {
                            return Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: _isExpanded ? 18 : 12,
                                vertical: _isExpanded ? 16 : 6,
                              ),

                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: <Widget>[
                                  Positioned(
                                    key: bottomChildKey,
                                    top: 0.0,
                                    left: 0.0,
                                    right: 0.0,
                                    child: bottomChild,
                                  ),
                                  Positioned(key: topChildKey, child: topChild),
                                ],
                              ),
                            );
                          },
                      crossFadeState: _isExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: _isExpanded
                          ? const SizedBox.shrink()
                          : _buildCompactPill(
                              state: state,
                              cubit: cubit,
                              surahTitle: surahTitle,
                              ayahText: ayahText,
                              surahNum: surahNum,
                            ),
                      secondChild: _isExpanded
                          ? _buildExpandedIsland(
                              state: state,
                              cubit: cubit,
                              surahTitle: surahTitle,
                              ayahText: ayahText,
                              reciterName: reciterName,
                              remainingStr: remainingStr,
                              surahNum: surahNum,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- Compact Dynamic Island Pill ---
  Widget _buildCompactPill({
    required QuranAudioState state,
    required QuranAudioCubit cubit,
    required String surahTitle,
    required String ayahText,
    required int surahNum,
  }) {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Play / Pause Mini Visual Icon - Dedicated Instant Tap Target (Zero Arena Delay)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.mediumImpact();
              cubit.togglePlayPause(
                fallbackSurahNumber: surahNum,
                fallbackStartAyahNumber: widget.defaultStartAyahNumber,
              );
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.secondaryGold.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: state.isLoadingAudio
                  ? const Center(child: AppLoader(width: 18, height: 18))
                  : Icon(
                      state.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: AppColors.secondaryGold,
                      size: 18,
                    ),
            ),
          ),
          const SizedBox(width: 12),

          // Title, Active Ayah Indicator & Soundwave (Recognizes Tap, DoubleTap, LongPress)
          Flexible(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _isExpanded = true);
              },
              onDoubleTap: () {
                HapticFeedback.mediumImpact();
                cubit.togglePlayPause(
                  fallbackSurahNumber: surahNum,
                  fallbackStartAyahNumber: widget.defaultStartAyahNumber,
                );
              },
              onLongPress: () {
                HapticFeedback.heavyImpact();
                if (widget.onSettingsTap != null) {
                  widget.onSettingsTap!();
                } else {
                  QuranAudioSettingsSheet.show(context);
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    flex: 2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          surahTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (ayahText.isNotEmpty)
                          Text(
                            ayahText,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.secondaryGold.withValues(
                                alpha: 0.9,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (state.isPlaying) ...[
                    Spacer(),
                    _buildSoundwave(state.isPlaying),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Expanded Dynamic Island Details Card ---
  Widget _buildExpandedIsland({
    required QuranAudioState state,
    required QuranAudioCubit cubit,
    required String surahTitle,
    required String ayahText,
    required String reciterName,
    required String remainingStr,
    required int surahNum,
  }) {
    final posMs = state.currentPosition.inMilliseconds.toDouble();
    final totalMs = state.totalDuration.inMilliseconds.toDouble();
    final sliderMax = totalMs > 0 ? totalMs : 1.0;
    final sliderVal = posMs.clamp(0.0, sliderMax);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Header: Surah, Ayah & Collapse Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          surahTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (ayahText.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.secondaryGold.withValues(
                              alpha: 0.2,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.secondaryGold.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                          child: Text(
                            ayahText,
                            style: const TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 11,
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
                    reciterName,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),

            // Top action buttons: Settings & Minimize
            Row(
              children: [
                IconButton(
                  tooltip: 'إعدادات التلاوة والحفظ',
                  icon: const Icon(
                    Icons.tune_rounded,
                    color: AppColors.secondaryGold,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () {
                    if (widget.onSettingsTap != null) {
                      widget.onSettingsTap!();
                    } else {
                      QuranAudioSettingsSheet.show(context);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'تصغير',
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white70,
                    size: 24,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () {
                    setState(() {
                      _isExpanded = false;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Scrubber / Seek Slider
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3.5,
            activeTrackColor: AppColors.secondaryGold,
            inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
            thumbColor: AppColors.secondaryGold,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            overlayColor: AppColors.secondaryGold.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: sliderVal,
            min: 0.0,
            max: sliderMax,
            onChanged: (val) {
              cubit.seekTo(Duration(milliseconds: val.toInt()));
            },
          ),
        ),

        // Time indicators: Elapsed time on right, Remaining duration on left
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(state.currentPosition),
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              Row(
                children: [
                  Text(
                    'المتبقي: ',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  Text(
                    remainingStr,
                    style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondaryGold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Playback Control Buttons Row
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Quick Repeat Toggle Button
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                tooltip: 'تبديل التكرار',
                icon: Icon(
                  _getRepeatIcon(state.highlightState.repeatMode),
                  color: state.highlightState.repeatMode != AudioRepeatMode.off
                      ? AppColors.secondaryGold
                      : Colors.white54,
                  size: 22,
                ),
                onPressed: () =>
                    _cycleRepeatMode(cubit, state.highlightState.repeatMode),
              ),

              // Previous Surah
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                tooltip: 'السورة السابقة',
                icon: const Icon(
                  Icons.skip_next_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () => cubit.playPreviousSurah(),
              ),

              // Rewind 10 seconds
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                tooltip: 'ترجيع ١٠ ثوانٍ',
                icon: const Icon(
                  Icons.replay_10_rounded,
                  color: Colors.white70,
                  size: 24,
                ),
                onPressed: () {
                  final current = cubit.state.currentPosition;
                  final target = current - const Duration(seconds: 10);
                  cubit.seekTo(target > Duration.zero ? target : Duration.zero);
                },
              ),

              // Main Play / Pause Button
              Container(
                width: 52,
                height: 52,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  gradient: AppColors.goldenGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x80BC8C15),
                      blurRadius: 14,
                      spreadRadius: 1,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: state.isLoadingAudio
                      ? const AppLoader(width: 28, height: 28)
                      : Icon(
                          state.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                  onPressed: () => cubit.togglePlayPause(
                    fallbackSurahNumber: surahNum,
                    fallbackStartAyahNumber: widget.defaultStartAyahNumber,
                  ),
                ),
              ),

              // Fast forward 10 seconds
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                tooltip: 'تقديم ١٠ ثوانٍ',
                icon: const Icon(
                  Icons.forward_10_rounded,
                  color: Colors.white70,
                  size: 24,
                ),
                onPressed: () {
                  final current = cubit.state.currentPosition;
                  final target = current + const Duration(seconds: 10);
                  if (target < cubit.state.totalDuration) {
                    cubit.seekTo(target);
                  } else {
                    cubit.seekTo(cubit.state.totalDuration);
                  }
                },
              ),

              // Next Surah
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                tooltip: 'السورة التالية',
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () => cubit.playNextSurah(),
              ),

              // Stop Button
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                tooltip: 'إيقاف تام',
                icon: const Icon(
                  Icons.stop_rounded,
                  color: Colors.white54,
                  size: 22,
                ),
                onPressed: () {
                  cubit.stop();
                  setState(() => _isExpanded = false);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  // Soundwave Equalizer Animation Bars
  Widget _buildSoundwave(bool isPlaying) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        final val = _waveController.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildBar(14 * (0.4 + 0.6 * val)),
            const SizedBox(width: 2.5),
            _buildBar(18 * (0.8 - 0.5 * (val - 0.5).abs())),
            const SizedBox(width: 2.5),
            _buildBar(16 * (0.3 + 0.7 * (1.0 - val))),
          ],
        );
      },
    );
  }

  Widget _buildBar(double height) {
    return Container(
      width: 2.5,
      height: height.clamp(4.0, 18.0),
      decoration: BoxDecoration(
        color: AppColors.secondaryGold,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  IconData _getRepeatIcon(AudioRepeatMode mode) {
    switch (mode) {
      case AudioRepeatMode.off:
        return Icons.repeat_rounded;
      case AudioRepeatMode.singleAyah:
        return Icons.repeat_one_rounded;
      case AudioRepeatMode.range:
        return Icons.tune_rounded;
    }
  }

  void _cycleRepeatMode(QuranAudioCubit cubit, AudioRepeatMode current) {
    final nextMode = switch (current) {
      AudioRepeatMode.off => AudioRepeatMode.singleAyah,
      AudioRepeatMode.singleAyah => AudioRepeatMode.range,
      AudioRepeatMode.range => AudioRepeatMode.off,
    };
    cubit.setRepeatMode(nextMode);
  }
}
