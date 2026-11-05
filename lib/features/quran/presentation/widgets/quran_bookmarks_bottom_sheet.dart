import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/core/widgets/app_loader.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import '../../../../core/DI/service_locator.dart';
import '../../../../core/utils/app_colors.dart';
import '../../data/datasources/surah_names.dart';
import '../../domain/entities/quran_ayah.dart';
import '../../domain/entities/quran_bookmark.dart';
import '../../domain/repositories/base_quran_mapping_repository.dart';
import '../cubit/quran_bookmark_cubit.dart';
import '../cubit/quran_bookmark_state.dart';
import 'quran_bookmark_edit_sheet.dart';

/// Modal bottom sheet displaying the user's saved Quran Ayah bookmarks.
/// Dynamically sizes to its content count up to full screen height.
/// Provides canonical text, custom names, custom colors, swipe-to-dismiss (Dismissible),
/// Undo functionality, and navigation to the Quran page.
class QuranBookmarksBottomSheet extends StatefulWidget {
  final void Function(QuranBookmark bookmark) onBookmarkSelected;

  const QuranBookmarksBottomSheet({
    super.key,
    required this.onBookmarkSelected,
  });

  @override
  State<QuranBookmarksBottomSheet> createState() =>
      _QuranBookmarksBottomSheetState();
}

class _QuranBookmarksBottomSheetState extends State<QuranBookmarksBottomSheet> {
  final Set<AyahId> _locallyDismissedAyahIds = {};
  final List<QuranBookmark> _dismissedBookmarks = [];
  Timer? _undoTimer;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  void _onBookmarkDismissed(QuranBookmark bookmark) {
    _undoTimer?.cancel();
    setState(() {
      _locallyDismissedAyahIds.add(bookmark.ayahId);
      _dismissedBookmarks.add(bookmark);
    });

    final cubit = context.read<QuranBookmarkCubit>();
    cubit.removeBookmark(bookmark.ayahId);

    _undoTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _dismissedBookmarks.clear());
      }
    });

    final surahName = getSurahName(bookmark.ayahId.surahNumber);
    final count = _dismissedBookmarks.length;
    final toRestore = List<QuranBookmark>.from(_dismissedBookmarks);
    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.delete_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                count == 1
                    ? 'تم حذف فاصلة سورة $surahName (الآية ${bookmark.ayahId.ayahNumber})'
                    : 'تم حذف $count فواصل',
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: count == 1 ? 'تراجع' : 'تراجع عن الكل',
          textColor: AppColors.secondaryGold,
          onPressed: () {
            _restoreBookmarks(toRestore, cubit: cubit, messenger: messenger);
          },
        ),
        backgroundColor: const Color(0xFFC62828),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _restoreBookmarks(
    List<QuranBookmark> bookmarks, {
    QuranBookmarkCubit? cubit,
    ScaffoldMessengerState? messenger,
  }) async {
    _undoTimer?.cancel();
    if (bookmarks.isEmpty) return;

    final toRestore = List<QuranBookmark>.from(bookmarks);
    if (mounted) {
      setState(() {
        for (final b in toRestore) {
          _locallyDismissedAyahIds.remove(b.ayahId);
        }
        _dismissedBookmarks.removeWhere((b) => toRestore.contains(b));
      });
    }

    final targetCubit = cubit ?? context.read<QuranBookmarkCubit>();
    await targetCubit.restoreBookmarks(toRestore);

    final targetMessenger =
        messenger ?? (mounted ? ScaffoldMessenger.of(context) : null);
    if (targetMessenger == null) return;

    targetMessenger.hideCurrentSnackBar();
    final count = toRestore.length;
    final message = count == 1
        ? 'تمت استعادة (${toRestore.first.name ?? 'الفاصلة'}) بنجاح'
        : 'تمت استعادة $count فواصل بنجاح';

    targetMessenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              color: AppColors.secondaryGold,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primaryBlack,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: AppColors.secondaryGold.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBgColor = isDark
        ? AppColors.primaryBlack
        : Theme.of(context).scaffoldBackgroundColor;
    final cardBg = isDark
        ? const Color(0xFF262626)
        : AppColors.secondaryGold.withValues(alpha: 0.05);
    final borderColor = AppColors.secondaryGold.withValues(alpha: 0.3);
    final primaryTextColor = isDark ? Colors.white : AppColors.darkText;
    final subtextColor = isDark ? Colors.white70 : Colors.black54;

    return DraggableScrollableSheet(
      builder: (_, scrollController) => Directionality(
        textDirection: TextDirection.rtl,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: MediaQuery.of(context).size.height * 0.90,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: sheetBgColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: borderColor, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: Material(
                  color: sheetBgColor,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Drag Handle
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        height: 5,
                        width: 44,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),

                      // 2. Header
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.bookmarks_rounded,
                                  color: AppColors.secondaryGold,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'الفواصل المحفوظة',
                                  style: TextStyle(
                                    fontFamily: 'Tajawal',
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: primaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              color: subtextColor,
                              tooltip: 'إغلاق',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),

                      // 3. In-sheet Undo Banner
                      if (_dismissedBookmarks.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2C1E1E)
                                  : const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.4),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  color: Colors.redAccent,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _dismissedBookmarks.length == 1
                                        ? 'تم حذف "${_dismissedBookmarks.first.name ?? 'الفاصلة'}"'
                                        : 'تم حذف ${_dismissedBookmarks.length} فواصل',
                                    style: TextStyle(
                                      fontFamily: 'Tajawal',
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.darkText,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    backgroundColor: AppColors.secondaryGold,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.undo_rounded,
                                    size: 15,
                                  ),
                                  label: Text(
                                    _dismissedBookmarks.length == 1
                                        ? 'تراجع'
                                        : 'تراجع عن الكل',
                                    style: const TextStyle(
                                      fontFamily: 'Tajawal',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () {
                                    _restoreBookmarks(_dismissedBookmarks);
                                  },
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  color: subtextColor,
                                  tooltip: 'إغلاق',
                                  onPressed: () {
                                    _undoTimer?.cancel();
                                    setState(() => _dismissedBookmarks.clear());
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                      // 4. Bookmarks List (Flexible with shrinkWrap to fit content height)
                      Flexible(
                        child: BlocBuilder<QuranBookmarkCubit, QuranBookmarkState>(
                          builder: (context, state) {
                            if (state is QuranBookmarkLoading) {
                              return const Padding(
                                padding: EdgeInsets.all(40),
                                child: Center(
                                  child:  AppLoader(),
                                ),
                              );
                            }

                            if (state is QuranBookmarkError) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Text(
                                    state.message,
                                    style: const TextStyle(
                                      fontFamily: 'Tajawal',
                                      color: AppColors.errorColor,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final allBookmarks = state is QuranBookmarkLoaded
                                ? state.bookmarks
                                : <QuranBookmark>[];

                            final bookmarks = allBookmarks
                                .where(
                                  (b) => !_locallyDismissedAyahIds.contains(
                                    b.ayahId,
                                  ),
                                )
                                .toList();

                            if (bookmarks.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32.0,
                                  vertical: 36.0,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.secondaryGold
                                            .withValues(alpha: 0.1),
                                      ),
                                      child: const Icon(
                                        Icons.bookmark_outline_rounded,
                                        color: AppColors.secondaryGold,
                                        size: 38,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'لا توجد فواصل محفوظة بعد',
                                      style: TextStyle(
                                        fontFamily: 'Tajawal',
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: primaryTextColor,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'يمكنك حفظ فاصلة لأي آية من خلال الضغط المطول عليها في المصحف ثم اختيار "فاصلة".',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'Tajawal',
                                        fontSize: 14,
                                        height: 1.5,
                                        color: subtextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return ListView.separated(
                              controller: scrollController,

                              shrinkWrap: true,
                              physics: const ClampingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              itemCount: bookmarks.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final bookmark = bookmarks[index];
                                return _buildDismissibleBookmarkTile(
                                  context: context,
                                  bookmark: bookmark,
                                  cardBg: cardBg,
                                  borderColor: borderColor,
                                  primaryTextColor: primaryTextColor,
                                  subtextColor: subtextColor,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDismissibleBookmarkTile({
    required BuildContext context,
    required QuranBookmark bookmark,
    required Color cardBg,
    required Color borderColor,
    required Color primaryTextColor,
    required Color subtextColor,
  }) {
    return Dismissible(
      key: ValueKey('bookmark_${bookmark.ayahId.formatted}'),
      direction: DismissDirection.horizontal,
      background: _buildDismissBackground(isStart: true),
      secondaryBackground: _buildDismissBackground(isStart: false),
      onDismissed: (_) {
        _onBookmarkDismissed(bookmark);
      },
      child: _buildBookmarkTile(
        context: context,
        bookmark: bookmark,
        cardBg: cardBg,
        borderColor: borderColor,
        primaryTextColor: primaryTextColor,
        subtextColor: subtextColor,
      ),
    );
  }

  Widget _buildDismissBackground({required bool isStart}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFC62828),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: isStart ? Alignment.centerRight : Alignment.centerLeft,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
          SizedBox(width: 8),
          Text(
            'حذف الفاصلة',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookmarkTile({
    required BuildContext context,
    required QuranBookmark bookmark,
    required Color cardBg,
    required Color borderColor,
    required Color primaryTextColor,
    required Color subtextColor,
  }) {
    final surahName = getSurahName(bookmark.ayahId.surahNumber);
    final bookmarkColor = bookmark.colorCode != null
        ? Color(bookmark.colorCode!)
        : AppColors.secondaryGold;
    final bookmarkName = bookmark.name ?? 'فاصل الحفظ';

    return InkWell(
      onTap: () => widget.onBookmarkSelected(bookmark),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: bookmark.colorCode != null
                ? bookmarkColor.withValues(alpha: 0.45)
                : borderColor,
            width: 1.2,
          ),
        ),
        child: FutureBuilder<QuranAyah?>(
          future: _resolveAyah(bookmark),
          builder: (context, snapshot) {
            final ayah = snapshot.data;
            final pageNumber = ayah?.pageNumber ?? bookmark.pageNumber;
            final uthmaniText = ayah?.uthmaniText ?? 'جاري تحميل نص الآية...';

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Bookmark Icon (Styled with custom color)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: bookmarkColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.bookmark_rounded,
                    color: bookmarkColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Surah • Ayah • Page & Custom Name Tag
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text(
                            'سورة $surahName',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: bookmarkColor,
                            ),
                          ),
                          Text(
                            '•  الآية ${bookmark.ayahId.ayahNumber}',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 13,
                              color: primaryTextColor,
                            ),
                          ),
                          if (pageNumber != null)
                            Text(
                              '•  صـ $pageNumber',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 12,
                                color: subtextColor,
                              ),
                            ),
                          // Custom Name Tag Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: bookmarkColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: bookmarkColor.withValues(alpha: 0.35),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              bookmarkName,
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: bookmarkColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Canonical Uthmani Text
                      Text(
                        uthmaniText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Amiri',
                          fontSize: 15,
                          height: 1.6,
                          color: primaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // Edit Button to update name & color
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: subtextColor,
                  tooltip: 'تعديل الفاصلة',
                  onPressed: () {
                    _openEditSheet(context, bookmark);
                  },
                ),

                // Delete Action
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: Colors.redAccent.withValues(alpha: 0.8),
                  tooltip: 'إزالة الفاصلة',
                  onPressed: () {
                    _onBookmarkDismissed(bookmark);
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openEditSheet(BuildContext context, QuranBookmark bookmark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => QuranBookmarkEditSheet(
        ayahId: bookmark.ayahId,
        pageNumber: bookmark.pageNumber,
        existingBookmark: bookmark,
        onSave: (name, colorCode) async {
          await context.read<QuranBookmarkCubit>().saveBookmark(
            ayahId: bookmark.ayahId,
            pageNumber: bookmark.pageNumber,
            name: name,
            colorCode: colorCode,
          );
        },
        onDelete: () {
          _onBookmarkDismissed(bookmark);
        },
      ),
    );
  }

  Future<QuranAyah?> _resolveAyah(QuranBookmark bookmark) async {
    try {
      final repo = sl<BaseQuranMappingRepository>();
      final result = await repo.getAyah(bookmark.ayahId);
      return result.fold((_) => null, (ayah) => ayah);
    } catch (_) {
      return null;
    }
  }
}
