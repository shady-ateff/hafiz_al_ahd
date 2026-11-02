import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/DI/service_locator.dart';
import '../../../../core/utils/app_colors.dart';
import '../../data/datasources/surah_names.dart';
import '../../domain/entities/quran_ayah.dart';
import '../../domain/entities/quran_tafseer.dart';
import '../cubit/quran_tafseer_cubit.dart';
import '../cubit/quran_tafseer_state.dart';

/// BottomSheet widget displaying the authoritative Tafseer commentary for a selected [QuranAyah].
///
/// Features:
/// 1. Ayah header with Surah name, Ayah number, page number, and original Quran text in Amiri font.
/// 2. RichText commentary with embedded Quranic quotations highlighted in accent gold.
/// 3. Resilient loading, loaded, and error states with Retry capability.
/// 4. Draggable, scrollable RTL presentation bounded for responsiveness.
/// 5. Self-contained Cubit lifecycle: creates and disposes its own Cubit via Service Locator,
///    or optionally consumes an injected [cubit] for widget testing.
class QuranTafseerBottomSheet extends StatelessWidget {
  final QuranAyah ayah;
  final QuranTafseerCubit? cubit;
  final VoidCallback? onCloseTap;

  const QuranTafseerBottomSheet({
    super.key,
    required this.ayah,
    this.cubit,
    this.onCloseTap,
  });

  @override
  Widget build(BuildContext context) {
    if (cubit != null) {
      return BlocProvider.value(
        value: cubit!,
        child: _TafseerBottomSheetContent(
          ayah: ayah,
          onCloseTap: onCloseTap,
        ),
      );
    }

    return BlocProvider<QuranTafseerCubit>(
      create: (_) => sl<QuranTafseerCubit>()..loadTafseer(ayah.id),
      child: _TafseerBottomSheetContent(
        ayah: ayah,
        onCloseTap: onCloseTap,
      ),
    );
  }
}

class _TafseerBottomSheetContent extends StatelessWidget {
  final QuranAyah ayah;
  final VoidCallback? onCloseTap;

  const _TafseerBottomSheetContent({
    required this.ayah,
    this.onCloseTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final initialSize = isLandscape ? 0.85 : 0.65;
    final minSize = isLandscape ? 0.35 : 0.30;
    const maxSize = 0.95;
    final snapSizes = isLandscape ? const [0.85, 0.95] : const [0.65, 0.85, 0.95];

    final sheetBgColor =
        isDark ? AppColors.primaryBlack : Theme.of(context).scaffoldBackgroundColor;
    final cardBgColor = isDark
        ? const Color(0xFF262626)
        : AppColors.secondaryGold.withValues(alpha: 0.05);
    final borderColor = AppColors.secondaryGold.withValues(alpha: 0.3);
    final textColor = isDark ? Colors.white : AppColors.darkText;
    final subtextColor = isDark ? Colors.white70 : Colors.black54;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: DraggableScrollableSheet(
            initialChildSize: initialSize,
            minChildSize: minSize,
            maxChildSize: maxSize,
            snap: true,
            snapSizes: snapSizes,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: sheetBgColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // 1. Drag Handle
                    const SizedBox(height: 12),
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. Header Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.auto_stories_rounded,
                                      color: AppColors.secondaryGold,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'تفسير ${getSurahName(ayah.id.surahNumber)} • الآية ${ayah.id.ayahNumber}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Tajawal',
                                          color: AppColors.secondaryGold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'صفحة ${ayah.pageNumber} • التفسير الميسر',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'Tajawal',
                                    color: subtextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            color: subtextColor,
                            tooltip: 'إغلاق',
                            onPressed: onCloseTap ?? () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 16),

                    // 3. Scrollable Body
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        children: [
                          // 3.1 Original Quran Ayah Text Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cardBgColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: borderColor.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              ayah.uthmaniText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Amiri',
                                fontSize: 20,
                                height: 1.9,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 3.2 Tafseer Commentary Content
                          BlocBuilder<QuranTafseerCubit, QuranTafseerState>(
                            builder: (context, state) {
                              if (state is QuranTafseerLoading) {
                                return _buildLoadingView(textColor, subtextColor);
                              }

                              if (state is QuranTafseerError) {
                                return _buildErrorView(
                                  context: context,
                                  message: state.message,
                                  textColor: textColor,
                                  subtextColor: subtextColor,
                                );
                              }

                              if (state is QuranTafseerLoaded) {
                                return _buildLoadedView(
                                  context: context,
                                  tafseer: state.tafseer,
                                  textColor: textColor,
                                  subtextColor: subtextColor,
                                  cardBgColor: cardBgColor,
                                  borderColor: borderColor,
                                );
                              }

                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingView(Color textColor, Color subtextColor) {
    return Container(
      key: const Key('tafseer_loading_view'),
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.secondaryGold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'جارٍ تحميل التفسير...',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 14,
              color: subtextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView({
    required BuildContext context,
    required String message,
    required Color textColor,
    required Color subtextColor,
  }) {
    return Container(
      key: const Key('tafseer_error_view'),
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent.shade200,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            'تعذر تحميل التفسير',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              color: subtextColor,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            key: const Key('tafseer_retry_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondaryGold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text(
              'إعادة المحاولة',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () {
              context.read<QuranTafseerCubit>().loadTafseer(ayah.id);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLoadedView({
    required BuildContext context,
    required QuranTafseer tafseer,
    required Color textColor,
    required Color subtextColor,
    required Color cardBgColor,
    required Color borderColor,
  }) {
    return Column(
      key: const Key('tafseer_loaded_view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Source tag
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.secondaryGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.secondaryGold.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Text(
                tafseer.sourceName,
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondaryGold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'مجمع الملك فهد لطباعة المصحف الشريف',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11,
                  color: subtextColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Commentary text with highlighted quotes
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor.withValues(alpha: 0.15),
            ),
          ),
          child: Text.rich(
            key: const Key('tafseer_commentary_text'),
            TextSpan(
              children: tafseer.segments.map((segment) {
                if (segment.isQuranQuote) {
                  return TextSpan(
                    text: segment.text,
                    style: const TextStyle(
                      fontFamily: 'Amiri',
                      fontSize: 18,
                      height: 1.8,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondaryGold,
                    ),
                  );
                } else {
                  return TextSpan(
                    text: segment.text,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 16,
                      height: 1.8,
                      fontWeight: FontWeight.normal,
                      color: textColor,
                    ),
                  );
                }
              }).toList(),
            ),
            textAlign: TextAlign.justify,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

