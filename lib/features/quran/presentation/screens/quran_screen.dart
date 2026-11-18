import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_settings_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_settings_state.dart';
import '../widgets/quran_theme_bottom_sheet.dart';
import '../../../../core/DI/service_locator.dart';
import '../widgets/quran_page_widget.dart';
import '../widgets/surah_juz_bottom_sheet.dart';
import '../widgets/quran_ayah_action_bottom_sheet.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_page_shimmer.dart';
import '../../domain/entities/ayah_id.dart';
import '../../domain/entities/quran_ayah.dart';
import '../../domain/entities/quran_word.dart';
import '../../domain/repositories/base_quran_mapping_repository.dart';
import 'package:share_plus/share_plus.dart';
import '../services/quran_clipboard_service.dart';
import '../services/quran_share_service.dart';
import '../utils/quran_image_renderer.dart';
import '../widgets/quran_ayah_share_modal.dart';
import '../../domain/entities/quran_bookmark.dart';
import '../cubit/quran_bookmark_cubit.dart';
import '../cubit/quran_bookmark_state.dart';
import '../widgets/quran_bookmarks_bottom_sheet.dart';
import '../widgets/quran_bookmark_edit_sheet.dart';
import '../widgets/quran_tafseer_bottom_sheet.dart';
import '../services/quran_atlas_prewarmer.dart';
import 'package:hafiz_al_ahd/features/quran_audio/presentation/cubit/quran_audio_cubit.dart';
import 'package:hafiz_al_ahd/features/quran_audio/presentation/cubit/quran_audio_state.dart';
import 'package:hafiz_al_ahd/features/quran_audio/presentation/widgets/quran_audio_dynamic_island.dart';
import '../../data/datasources/surah_names.dart';

class QuranScreen extends StatefulWidget {
  final int? initialPage;
  final ValueChanged<QuranWord>? onWordTapped;
  final ValueChanged<QuranWord>? onWordLongPressed;
  final QuranClipboardService? clipboardService;
  final QuranShareService? shareService;
  final BaseQuranAtlasPrewarmer? atlasPrewarmer;

  const QuranScreen({
    super.key,
    this.initialPage,
    this.onWordTapped,
    this.onWordLongPressed,
    this.clipboardService,
    this.shareService,
    this.atlasPrewarmer,
  });

  static void showInstructionsDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.secondaryGold, width: 1.5),
          ),
          backgroundColor:
              isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFDF0),
          title: Row(
            children: const [
              Icon(Icons.menu_book_rounded,
                  color: AppColors.secondaryGold, size: 26),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تعليمات التفاعل مع المصحف',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInstructionRow(
                icon: Icons.touch_app_rounded,
                title: 'اضغط مطولاً على أي كلمة',
                desc:
                    'لعرض الآية كاملة والوصول إلى خياراتها (تفسير، نسخ، واستماع).',
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              _buildInstructionRow(
                icon: Icons.fullscreen_rounded,
                title: 'اضغط ضغطة سريعة في أي مكان',
                desc:
                    'لإخفاء أو إظهار أشرطة التطبيق والاستمتاع بالقراءة في وضع ملء الشاشة.',
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              _buildInstructionRow(
                icon: Icons.swipe_rounded,
                title: 'اسحب يميناً أو يساراً',
                desc: 'للتنقل السريع والسلس بين صفحات المصحف الشريف.',
                isDark: isDark,
              ),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () async {
                  final prefs = sl<SharedPreferences>();
                  await prefs.setBool('quran_gesture_onboarding_shown', true);
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondaryGold,
                  foregroundColor: AppColors.primaryBlack,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 36, vertical: 10),
                ),
                child: const Text(
                  'فهمت، لنبدأ',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Widget _buildInstructionRow({
    required IconData icon,
    required String title,
    required String desc,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.secondaryGold.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.secondaryGold, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white : AppColors.primaryBlack,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  height: 1.4,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  State<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends State<QuranScreen>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  late final ValueNotifier<int> _currentPageNotifier;
  late final BaseQuranAtlasPrewarmer _atlasPrewarmer;
  bool _isFullScreen = false;
  bool _isAppActive = true;

  bool get _isRouteActive => ModalRoute.of(context)?.isCurrent ?? true;

  ModalBottomSheetRoute<void>? _activeAyahSheetRoute;
  bool _isAyahSheetOpen = false;
  bool _isAutoPageAnimating = false;
  DateTime _lastUserPageInteractionTime = DateTime.fromMillisecondsSinceEpoch(0);
  int? _pendingTargetPage;
  Timer? _pendingPageTurnTimer;
  int _selectionRequestToken = 0;

  final Map<int, ValueChanged<QuranWord>> _tappedCallbacks = {};
  final Map<int, ValueChanged<QuranWord>> _longPressedCallbacks = {};

  ValueChanged<QuranWord>? _getWordTappedCallback(int pageNumber) {
    if (widget.onWordTapped != null) return widget.onWordTapped;
    return _tappedCallbacks.putIfAbsent(
      pageNumber,
      () => (word) => _handleWordTapped(word, pageNumber),
    );
  }

  ValueChanged<QuranWord>? _getWordLongPressedCallback(int pageNumber) {
    if (widget.onWordLongPressed != null) return widget.onWordLongPressed;
    return _longPressedCallbacks.putIfAbsent(
      pageNumber,
      () => (word) => _handleWordLongPressed(word, pageNumber),
    );
  }

  @override
  void didUpdateWidget(QuranScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onWordTapped != oldWidget.onWordTapped ||
        widget.onWordLongPressed != oldWidget.onWordLongPressed) {
      _tappedCallbacks.clear();
      _longPressedCallbacks.clear();
    }
  }

  QuranClipboardService get _clipboardService =>
      widget.clipboardService ??
      (sl.isRegistered<QuranClipboardService>()
          ? sl<QuranClipboardService>()
          : const QuranClipboardService());

  QuranShareService get _shareService =>
      widget.shareService ??
      (sl.isRegistered<QuranShareService>()
          ? sl<QuranShareService>()
          :  QuranShareService());

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPage ?? 1;
    _pageController = PageController(initialPage: initial - 1);
    _currentPageNotifier = ValueNotifier<int>(initial);
    _atlasPrewarmer = widget.atlasPrewarmer ?? QuranAtlasPrewarmer();
    WidgetsBinding.instance.addObserver(this);
    _loadLastPage();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppActive = state == AppLifecycleState.resumed;
    if (!_isAppActive) {
      _atlasPrewarmer.cancel();
    }
  }

  Future<void> _loadLastPage() async {
    final prefs = sl<SharedPreferences>();
    final lastPage = widget.initialPage ?? (prefs.getInt('last_quran_page') ?? 1);
    _currentPageNotifier.value = lastPage;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(lastPage - 1);
      }
      context.read<QuranCubit>().loadPage(lastPage);
      if (lastPage < 604) {
        context.read<QuranCubit>().preloadPage(lastPage + 1);
        _atlasPrewarmer.schedulePrewarm(
          targetPageNumber: lastPage + 1,
          cubit: context.read<QuranCubit>(),
          currentVisiblePage: lastPage,
          isEligible: () => mounted && _isRouteActive && _isAppActive,
        );
      }
      _checkFirstTimeOnboarding();
    });
  }

  Future<void> _checkFirstTimeOnboarding() async {
    final prefs = sl<SharedPreferences>();
    final hasShown = prefs.getBool('quran_gesture_onboarding_shown') ?? false;
    if (!hasShown && mounted) {
      QuranScreen.showInstructionsDialog(context);
    }
  }

  Future<void> _saveLastPage(int pageNumber) async {
    final prefs = sl<SharedPreferences>();
    await prefs.setInt('last_quran_page', pageNumber);
  }

  @override
  void dispose() {
    _pendingPageTurnTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _atlasPrewarmer.dispose();
    _closeActiveSheetRouteOnly();
    _pageController.dispose();
    _currentPageNotifier.dispose();
    _tappedCallbacks.clear();
    _longPressedCallbacks.clear();
    super.dispose();
  }

  void _closeActiveSheetRouteOnly() {
    if (_activeAyahSheetRoute != null && _activeAyahSheetRoute!.isActive) {
      final route = _activeAyahSheetRoute!;
      _activeAyahSheetRoute = null;
      _isAyahSheetOpen = false;
      if (route.navigator != null) {
        if (route.isCurrent) {
          route.navigator!.pop();
        } else {
          route.navigator!.removeRoute(route);
        }
      }
      _checkAndApplyPendingPageTurn();
    }
  }

  QuranBookmarkCubit? _tryGetBookmarkCubit(BuildContext context) {
    try {
      return context.read<QuranBookmarkCubit>();
    } catch (_) {
      try {
        return sl<QuranBookmarkCubit>();
      } catch (_) {
        return null;
      }
    }
  }

  QuranAudioCubit? _tryGetAudioCubit(BuildContext context) {
    try {
      return context.read<QuranAudioCubit>();
    } catch (_) {
      return null;
    }
  }

  void _checkAndApplyPendingPageTurn() {
    if (!mounted || _pendingTargetPage == null) return;
    final cubit = _tryGetAudioCubit(context);
    if (cubit == null || !cubit.state.isPlaying) {
      _pendingPageTurnTimer?.cancel();
      _pendingPageTurnTimer = null;
      _pendingTargetPage = null;
      return;
    }

    // 1. Guard: Route occlusion by Modal Bottom Sheet or Dialog
    if (!_isRouteActive || _isAyahSheetOpen) {
      _pendingPageTurnTimer?.cancel();
      _pendingPageTurnTimer = Timer(const Duration(milliseconds: 500), _checkAndApplyPendingPageTurn);
      return;
    }

    // 2. Guard: Ongoing animation
    if (_isAutoPageAnimating) return;

    // 3. Guard: User actively dragging/scrolling PageView
    if (_pageController.hasClients &&
        _pageController.position.haveDimensions &&
        _pageController.position.isScrollingNotifier.value) {
      _pendingPageTurnTimer?.cancel();
      _pendingPageTurnTimer = Timer(const Duration(milliseconds: 300), _checkAndApplyPendingPageTurn);
      return;
    }

    // 4. Guard: Cooldown after manual touch (1500ms)
    final elapsed = DateTime.now().difference(_lastUserPageInteractionTime).inMilliseconds;
    if (elapsed < 1500) {
      final remaining = (1500 - elapsed).clamp(50, 1500);
      _pendingPageTurnTimer?.cancel();
      _pendingPageTurnTimer = Timer(Duration(milliseconds: remaining + 50), _checkAndApplyPendingPageTurn);
      return;
    }

    final targetPage = _pendingTargetPage!;
    if (_currentPageNotifier.value != targetPage && _pageController.hasClients) {
      final animatedTargetPage = targetPage;
      _isAutoPageAnimating = true;
      _pageController
          .animateToPage(
            animatedTargetPage - 1,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
          )
          .then((_) {
            // Race condition guard: only clear pending target if not superseded by a newer target
            if (_pendingTargetPage == animatedTargetPage) {
              _pendingTargetPage = null;
            }
          })
          .catchError((_) {})
          .whenComplete(() {
            _isAutoPageAnimating = false;
            // If a newer target arrived while animating, trigger it immediately
            if (_pendingTargetPage != null && _pendingTargetPage != _currentPageNotifier.value) {
              _checkAndApplyPendingPageTurn();
            }
          });
    } else {
      _pendingTargetPage = null;
    }
  }

  void _handlePlayAyahAudio(QuranAyah ayah) {
    _closeActiveSheetRouteOnly();
    try {
      final audioCubit = _tryGetAudioCubit(context);
      audioCubit?.playAyah(ayah.id);
    } catch (_) {}
  }

  Future<void> _openAyahBottomSheet(QuranAyah ayah) async {
    _closeActiveSheetRouteOnly();

    final bookmarkCubit = _tryGetBookmarkCubit(context);

    final route = ModalBottomSheetRoute<void>(
      builder: (sheetContext) {
        if (bookmarkCubit != null) {
          return BlocBuilder<QuranBookmarkCubit, QuranBookmarkState>(
            bloc: bookmarkCubit,
            builder: (context, bookmarkState) {
              final isBookmarked = bookmarkCubit.isAyahBookmarked(ayah.id);
              final bookmark = bookmarkCubit.getBookmark(ayah.id);
              final bookmarkColor = bookmark?.colorCode != null
                  ? Color(bookmark!.colorCode!)
                  : null;
              return QuranAyahActionBottomSheet(
                ayah: ayah,
                isBookmarked: isBookmarked,
                bookmarkColor: bookmarkColor,
                onCloseTap: () => _closeActiveSheetRouteOnly(),
                onPlayAudioTap: () => _handlePlayAyahAudio(ayah),
                onTafseerTap: () => _handleOpenTafseer(ayah),
                onCopyTap: () => _handleCopyAyah(ayah),
                onShareTap: () => _handleShareAyah(ayah),
                onBookmarkTap: () => _handleToggleBookmark(ayah),
              );
            },
          );
        } else {
          return QuranAyahActionBottomSheet(
            ayah: ayah,
            isBookmarked: false,
            onCloseTap: () => _closeActiveSheetRouteOnly(),
            onPlayAudioTap: () => _handlePlayAyahAudio(ayah),
            onTafseerTap: () => _handleOpenTafseer(ayah),
            onCopyTap: () => _handleCopyAyah(ayah),
            onShareTap: () => _handleShareAyah(ayah),
            onBookmarkTap: () => _handleToggleBookmark(ayah),
          );
        }
      },
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context).context,
      ),
    );

    _activeAyahSheetRoute = route;
    _isAyahSheetOpen = true;

    try {
      await Navigator.of(context).push(route);
    } finally {
      if (_activeAyahSheetRoute == route) {
        _activeAyahSheetRoute = null;
        _isAyahSheetOpen = false;
      }
      _checkAndApplyPendingPageTurn();
    }
  }

  Future<void> _handleOpenTafseer(QuranAyah ayah) async {
    // Close the action bottom sheet route ONLY without clearing the QuranAyah selection.
    _closeActiveSheetRouteOnly();

    final route = ModalBottomSheetRoute<void>(
      builder: (sheetContext) => QuranTafseerBottomSheet(
        ayah: ayah,
        onCloseTap: () => _closeActiveSheetRouteOnly(),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context).context,
      ),
    );

    _activeAyahSheetRoute = route;
    _isAyahSheetOpen = true;

    try {
      await Navigator.of(context).push(route);
    } finally {
      if (_activeAyahSheetRoute == route) {
        _activeAyahSheetRoute = null;
        _isAyahSheetOpen = false;
      }
      _checkAndApplyPendingPageTurn();
    }
  }

  Future<void> _handleToggleBookmark(QuranAyah ayah) async {
    final cubit = _tryGetBookmarkCubit(context);
    if (cubit == null) return;
    final existingBookmark = cubit.getBookmark(ayah.id);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => QuranBookmarkEditSheet(
        ayahId: ayah.id,
        pageNumber: ayah.pageNumber,
        existingBookmark: existingBookmark,
        onSave: (name, colorCode) async {
          await cubit.saveBookmark(
            ayahId: ayah.id,
            pageNumber: ayah.pageNumber,
            name: name,
            colorCode: colorCode,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    Icons.bookmark_added_rounded,
                    color: Color(colorCode),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تم حفظ ($name) بنجاح',
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
                  color: Color(colorCode).withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        onDelete: existingBookmark != null
            ? () async {
                await cubit.removeBookmark(ayah.id);
                if (!mounted) return;
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(
                          Icons.bookmark_remove_rounded,
                          color: AppColors.secondaryGold,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'تمت إزالة الآية من الفواصل',
                            style: TextStyle(
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
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            : null,
      ),
    );
  }

  Future<void> _navigateToBookmark(QuranBookmark bookmark) async {
    Navigator.of(context).maybePop();

    int targetPage = bookmark.pageNumber ?? 1;
    final mappingRepo = sl<BaseQuranMappingRepository>();
    final res = await mappingRepo.getAyah(bookmark.ayahId);
    res.fold((_) {}, (ayah) {
      targetPage = ayah.pageNumber;
    });

    if (_currentPageNotifier.value != targetPage) {
      _pageController.jumpToPage(targetPage - 1);
      _currentPageNotifier.value = targetPage;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleAyahSelectionOrReopen(bookmark.ayahId, pageNumber: targetPage);
      }
    });
  }

  Future<void> _handleCopyAyah(QuranAyah ayah) async {
    final success = await _clipboardService.copyAyah(ayah);

    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (success) {
      _closeActiveSheetRouteOnly();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color: AppColors.secondaryGold,
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تم نسخ الآية الكريمة بنجاح',
                  style: TextStyle(fontFamily: 'Tajawal', color: Colors.white),
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
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'فشل نسخ الآية، يرجى المحاولة مرة أخرى',
                  style: TextStyle(fontFamily: 'Tajawal', color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.errorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleShareAyah(QuranAyah ayah) async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (modalContext) => QuranAyahShareModal(
        ayah: ayah,
        onClose: () => Navigator.of(modalContext).pop(),
        onShareText: () async {
          Navigator.of(modalContext).pop();
          await _executeShareText(ayah);
        },
        onShareImage: (cardKey) async {
          final pngBytes = await QuranImageRenderer.captureBoundaryToPng(cardKey);
          if (modalContext.mounted && Navigator.of(modalContext).canPop()) {
            Navigator.of(modalContext).pop();
          }
          await _executeShareImage(ayah, pngBytes);
        },
      ),
    );
  }

  Future<void> _executeShareText(QuranAyah ayah) async {
    final status = await _shareService.shareText(ayah);

    if (!mounted) return;

    if (status == ShareResultStatus.success) {
      _closeActiveSheetRouteOnly();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color: AppColors.secondaryGold,
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تمت مشاركة الآية الكريمة بنجاح',
                  style: TextStyle(fontFamily: 'Tajawal', color: Colors.white),
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
    } else if (status == ShareResultStatus.dismissed) {
      // User dismissed share sheet without sharing: keep BottomSheet open, no false success.
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'فشلت مشاركة الآية، يرجى المحاولة مرة أخرى',
                  style: TextStyle(fontFamily: 'Tajawal', color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.errorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _executeShareImage(
    QuranAyah ayah,
    Uint8List pngBytes,
  ) async {
    String? tempPath;
    try {
      tempPath = await QuranImageRenderer.saveTempImageFile(
        ayah: ayah,
        pngBytes: pngBytes,
      );

      final status = await _shareService.shareImageFile(tempPath, ayah);

      if (!mounted) return;

      if (status == ShareResultStatus.success) {
        _closeActiveSheetRouteOnly();
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: AppColors.secondaryGold,
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تمت مشاركة البطاقة القرآنية بنجاح',
                    style: TextStyle(fontFamily: 'Tajawal', color: Colors.white),
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
      } else if (status == ShareResultStatus.dismissed) {
        // Dismissed without sharing: keep modal open, do not show false success.
      } else {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'فشلت مشاركة الصورة، يرجى المحاولة مرة أخرى',
                    style: TextStyle(fontFamily: 'Tajawal', color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'حدث خطأ أثناء تصيير صورة الآية',
                  style: TextStyle(fontFamily: 'Tajawal', color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.errorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (tempPath != null) {
        await QuranImageRenderer.cleanupTempFile(tempPath);
      }
    }
  }

  void _handleWordTapped(QuranWord word, int pageNumber) {
    _atlasPrewarmer.cancel();
    final currentSelected = context.read<QuranCubit>().selectedAyahId;
    if (currentSelected == word.ayahId) {
      _handleAyahSelectionOrReopen(word.ayahId, pageNumber: pageNumber);
    }
  }

  void _handleWordLongPressed(QuranWord word, int pageNumber) {
    _atlasPrewarmer.cancel();
    _handleAyahSelectionOrReopen(word.ayahId, pageNumber: pageNumber);
  }

  Future<void> _handleAyahSelectionOrReopen(
    AyahId ayahId, {
    required int pageNumber,
  }) async {
    _atlasPrewarmer.cancel();
    final cubit = context.read<QuranCubit>();
    final currentSelected = cubit.selectedAyahId;

    if (currentSelected == ayahId && _isAyahSheetOpen) {
      return;
    }

    final int requestToken = ++_selectionRequestToken;

    cubit.selectAyah(ayahId, pageNumber: pageNumber);

    final mappingRepo = sl<BaseQuranMappingRepository>();
    final result = await mappingRepo.getAyah(ayahId);

    if (!mounted) return;
    if (requestToken != _selectionRequestToken) return;
    if (cubit.selectedAyahId != ayahId) return;

    if (_isAyahSheetOpen && _activeAyahSheetRoute != null) {
      _closeActiveSheetRouteOnly();
    }

    result.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure.message,
              style: const TextStyle(fontFamily: 'Tajawal'),
            ),
            backgroundColor: AppColors.errorColor,
            duration: const Duration(seconds: 2),
          ),
        );
      },
      (ayah) {
        _openAyahBottomSheet(ayah);
      },
    );
  }

  void _toggleFullScreen() {
    _atlasPrewarmer.cancel();
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
  }

  void _showPageJumpDialog() {
    _atlasPrewarmer.cancel();
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'الانتقال إلى صفحة',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'رقم الصفحة (1 - 604)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.secondaryGold, width: 2),
              ),
            ),
            autofocus: true,
            onSubmitted: (value) {
              _jumpToPage(value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'إلغاء',
                style: TextStyle(color: Colors.grey, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                _jumpToPage(controller.text);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondaryGold,
                foregroundColor: AppColors.primaryBlack,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'انتقال',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _jumpToPage(String value) {
    _atlasPrewarmer.cancel();
    int? page = int.tryParse(value);
    if (page != null && page >= 1 && page <= 604) {
      _pageController.jumpToPage(page - 1);
      _currentPageNotifier.value = page;
      Navigator.pop(context);
    }
  }

  bool _isDarkMode(BuildContext context, ThemeMode mode) {
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return Theme.of(context).brightness == Brightness.dark;
  }

  @override
  Widget build(BuildContext context) {
    final audioCubit = _tryGetAudioCubit(context);

    return BlocBuilder<QuranSettingsCubit, QuranSettingsState>(
      builder: (context, settingsState) {
        final isDark = _isDarkMode(context, settingsState.quranThemeMode);
        final bgColor = isDark
            ? const Color(0xFF121212)
            : const Color(0xffFFFCE6);
        final headerIconColor = isDark
            ? Colors.white70
            : AppColors.darkSilverMarble;

        Widget buildBody(AyahId? activeAudioAyah) {
          return Stack(
            children: [
              // 1. PageView
              GestureDetector(
                onTap: _toggleFullScreen,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    final bool isUserGesture = notification is UserScrollNotification ||
                        (notification is ScrollUpdateNotification && notification.dragDetails != null);

                    if (isUserGesture && !_isAutoPageAnimating) {
                      _lastUserPageInteractionTime = DateTime.now();
                    } else if (notification is ScrollEndNotification) {
                      // Only update interaction timestamp if initiated by user gesture, NOT programmatic animation
                      if (!_isAutoPageAnimating && notification.dragDetails != null) {
                        _lastUserPageInteractionTime = DateTime.now();
                      }
                      if (_pendingTargetPage != null && !_isAutoPageAnimating) {
                        _pendingPageTurnTimer?.cancel();
                        _pendingPageTurnTimer = Timer(
                          const Duration(milliseconds: 1550),
                          _checkAndApplyPendingPageTurn,
                        );
                      }
                    }
                    return false;
                  },
                  child: PageView.builder(
                  controller: _pageController,
                  reverse: false,
                  itemCount: 604,
                  allowImplicitScrolling: true,
                  onPageChanged: (index) {
                    if (!_isAutoPageAnimating) {
                      _lastUserPageInteractionTime = DateTime.now();
                    }
                    final int pageNumber = index + 1;
                    _currentPageNotifier.value = pageNumber;
                    if (_pendingTargetPage == pageNumber) {
                      _pendingTargetPage = null;
                    }
                    _selectionRequestToken++;
                    _closeActiveSheetRouteOnly();
                    context.read<QuranCubit>().clearSelection();
                    context.read<QuranCubit>().loadPage(pageNumber);
                    _saveLastPage(pageNumber);

                    if (pageNumber < 604) {
                      context.read<QuranCubit>().preloadPage(pageNumber + 1);
                      _atlasPrewarmer.schedulePrewarm(
                        targetPageNumber: pageNumber + 1,
                        cubit: context.read<QuranCubit>(),
                        currentVisiblePage: pageNumber,
                        isEligible: () => mounted && _isRouteActive && _isAppActive,
                      );
                    }
                    if (pageNumber > 1) {
                      context.read<QuranCubit>().preloadPage(pageNumber - 1);
                    }
                  },
                  itemBuilder: (context, index) {
                    final int pageNumber = index + 1;
                    return BlocBuilder<QuranCubit, QuranState>(
                      buildWhen: (previous, current) {
                        if (current is QuranPageLoaded) {
                          return current.page.pageNumber == pageNumber;
                        }
                        return true;
                      },
                      builder: (context, state) {
                        final cubit = context.read<QuranCubit>();

                        // 1. If currently downloading fonts or extracting, show download progress UI
                        if (state is QuranDownloadingFonts || (state is QuranLoading && cubit.isUnzipping)) {
                          final bool isDownloading = state is QuranDownloadingFonts;
                          final double progress = isDownloading ? state.progress : 1.0;
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 120,
                                      height: 120,
                                      child: CircularProgressIndicator(
                                        value: isDownloading ? progress : null,
                                        strokeWidth: 8,
                                        color: AppColors.secondaryGold,
                                        backgroundColor: isDark ? Colors.white12 : Colors.black12,
                                        strokeCap: StrokeCap.round,
                                      ),
                                    ),
                                    if (isDownloading)
                                      Text(
                                        '${(progress * 100).toInt()}%',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Tajawal',
                                          color: isDark ? Colors.white : AppColors.primaryBlack,
                                        ),
                                      )
                                    else
                                      const Icon(Icons.settings_suggest_rounded, size: 48, color: AppColors.secondaryGold),
                                  ],
                                ),
                                const SizedBox(height: 40),
                                Text(
                                  isDownloading ? 'جاري تحميل خطوط المصحف الشريف...' : 'جاري تهيئة الخطوط...',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Tajawal',
                                    color: isDark ? Colors.white : AppColors.primaryBlack,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'هذه العملية تتم مرة واحدة فقط لضمان عمل المصحف\nبدون إنترنت وبأفضل جودة ممكنة.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.5,
                                    fontFamily: 'Tajawal',
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        // 2. If an error occurred (download error or page error):
                        if (state is QuranError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.redAccent.withValues(alpha: 0.1),
                                    ),
                                    child: const Icon(
                                      Icons.cloud_off_rounded,
                                      size: 54,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    state.message,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Tajawal',
                                      fontSize: 16,
                                      height: 1.6,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : AppColors.darkText,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.secondaryGold,
                                      foregroundColor: Colors.black,
                                      elevation: 2,
                                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    onPressed: () {
                                      if (!cubit.fontsReady) {
                                        cubit.retryFontsDownload();
                                      } else {
                                        cubit.loadPage(pageNumber);
                                      }
                                    },
                                    icon: const Icon(Icons.refresh_rounded, size: 22),
                                    label: const Text(
                                      'إعادة المحاولة',
                                      style: TextStyle(
                                        fontFamily: 'Tajawal',
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        // 3. Check loaded / cached page
                        final effectiveState = (state is QuranPageLoaded && state.page.pageNumber == pageNumber)
                            ? state
                            : cubit.getCachedPage(pageNumber);

                        if (effectiveState != null) {
                          // If fonts are not ready and the font is not loaded, show download retry prompt
                          if (!cubit.fontsReady && !effectiveState.isFontLoaded) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.secondaryGold.withValues(alpha: 0.1),
                                      ),
                                      child: const Icon(
                                        Icons.font_download_off_rounded,
                                        size: 54,
                                        color: AppColors.secondaryGold,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      'لم يتم اكتمال تحميل خطوط المصحف بعد.\nيرجى التأكد من اتصال الإنترنت ثم إعادة المحاولة.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'Tajawal',
                                        fontSize: 16,
                                        height: 1.6,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : AppColors.darkText,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.secondaryGold,
                                        foregroundColor: Colors.black,
                                        elevation: 2,
                                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                      onPressed: () => cubit.retryFontsDownload(),
                                      icon: const Icon(Icons.refresh_rounded, size: 22),
                                      label: const Text(
                                        'تحميل الخطوط الآن',
                                        style: TextStyle(
                                          fontFamily: 'Tajawal',
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return QuranPageWidget(
                            page: effectiveState.page,
                            isFontLoaded: effectiveState.isFontLoaded,
                            lineMappings: effectiveState.lineMappings,
                            selectedAyahId: effectiveState.selectedAyahId,
                            audioHighlightedAyahId: activeAudioAyah,
                            onWordTapped: _getWordTappedCallback(pageNumber),
                            onWordLongPressed: _getWordLongPressedCallback(pageNumber),
                          );
                        }

                        return const QuranPageShimmer();
                      },
                    );
                  },
                ),
              ),
            ),

              // 2. Header AppBar
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                top: _isFullScreen ? -150 : 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: _isFullScreen,
                  child: Container(
                    decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color.fromARGB(255, 90, 90, 90),
                        AppColors.primaryBlack,
                        AppColors.amoledBackground,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: SizedBox(
                      height: 70,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          IconButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.arrow_back),
                            style: IconButton.styleFrom(
                              iconSize: 32,
                              foregroundColor: headerIconColor,
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          const Text(
                            'المصحف الشريف',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: AppColors.darkSilverMarble,
                            ),
                          ),
                          const Spacer(),

                          IconButton(
                            tooltip: 'الفواصل المحفوظة',
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (sheetCtx) => QuranBookmarksBottomSheet(
                                  onBookmarkSelected: (bookmark) => _navigateToBookmark(bookmark),
                                ),
                              );
                            },
                            icon: const Icon(Icons.bookmarks_rounded),
                            style: IconButton.styleFrom(
                              iconSize: 28,
                              foregroundColor: const Color(0xffD4AF37),
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (context) {
                                  return SurahJuzBottomSheet(
                                    onPageSelected: (page) {
                                      _pageController.jumpToPage(page - 1);
                                      _currentPageNotifier.value = page;
                                    },
                                  );
                                },
                              );
                            },
                            icon: const Icon(
                              Icons.format_list_bulleted_rounded,
                            ),
                            style: IconButton.styleFrom(
                              iconSize: 32,
                              foregroundColor: const Color(
                                0xffD4AF37,
                              ), // لون ذهبي فخم
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (context) {
                                  return const QuranThemeBottomSheet();
                                },
                              );
                            },
                            icon: const Icon(Icons.settings),
                            style: IconButton.styleFrom(
                              iconSize: 30,
                              foregroundColor: AppColors.darkSilverMarble,
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

              // 3. Bottom Slider
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                bottom: _isFullScreen ? -150 : 30,
                left: 20,
                right: 20,
                child: IgnorePointer(
                  ignoring: _isFullScreen,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _isFullScreen ? 0.0 : 1.0,
                    child: ValueListenableBuilder<int>(
                      valueListenable: _currentPageNotifier,
                      builder: (context, currentPage, child) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 15,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF222222).withValues(alpha: 0.9)
                                : Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              InkWell(
                                onTap: _showPageJumpDialog,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondaryGold.withValues(alpha: 0.15),
                                    border: Border.all(color: AppColors.secondaryGold.withValues(alpha: 0.5)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.edit_rounded,
                                        size: 14,
                                        color: isDark ? Colors.white70 : AppColors.deepBackground,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$currentPage',
                                        style: TextStyle(
                                          fontFamily: 'Tajawal',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: isDark
                                            ? Colors.white
                                            : AppColors.deepBackground,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    activeTrackColor: const Color(0xffD4AF37),
                                    inactiveTrackColor: isDark
                                        ? Colors.grey[800]
                                        : const Color(0xffD4AF37).withValues(alpha: 0.3),
                                    thumbColor: const Color(0xffD4AF37),
                                    trackHeight: 4.0,
                                  ),
                                  child: Slider(
                                    value: currentPage.toDouble(),
                                    min: 1,
                                    max: 604,
                                    onChanged: (value) {
                                      _currentPageNotifier.value = value.toInt();
                                    },
                                    onChangeEnd: (value) {
                                      _pageController.jumpToPage(value.toInt() - 1);
                                    },
                                  ),
                                ),
                              ),
                              Text(
                                '604',
                                style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.deepBackground,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // 4. Floating Dynamic Island Audio Player
              if (audioCubit != null)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  bottom: _isFullScreen ? -220 : 92,
                  left: 16,
                  right: 16,
                  child: IgnorePointer(
                    ignoring: _isFullScreen,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 280),
                      opacity: _isFullScreen ? 0.0 : 1.0,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _currentPageNotifier,
                        builder: (context, currentPage, _) {
                          final pageSurah = getSurahNumberForPage(currentPage);
                          return BlocProvider.value(
                            value: audioCubit,
                            child: QuranAudioDynamicIsland(
                              key: const ValueKey('quran_audio_dynamic_island'),
                              defaultSurahNumber: pageSurah,
                              isFullScreen: _isFullScreen,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          );
        }

        Widget bodyContent;
        if (audioCubit != null) {
          bodyContent = BlocListener<QuranAudioCubit, QuranAudioState>(
            bloc: audioCubit,
            listenWhen: (prev, curr) =>
                (prev.isPlaying != curr.isPlaying) ||
                (curr.isPlaying &&
                    prev.highlightState.activeAyah != curr.highlightState.activeAyah &&
                    curr.highlightState.activeAyah != null),
            listener: (context, state) async {
              if (!state.isPlaying) {
                // Audio stopped or paused: immediately cancel any pending target and active timer
                _pendingPageTurnTimer?.cancel();
                _pendingPageTurnTimer = null;
                _pendingTargetPage = null;
                return;
              }
              final activeAyah = state.highlightState.activeAyah;
              if (activeAyah == null) return;

              try {
                final mappingRepo = sl<BaseQuranMappingRepository>();
                final res = await mappingRepo.getAyah(activeAyah);
                res.fold((_) {}, (ayah) async {
                  if (!mounted) return;
                  final targetPage = ayah.pageNumber;

                  // If already on the target page, clear pending request
                  if (_currentPageNotifier.value == targetPage) {
                    _pendingTargetPage = null;
                    return;
                  }

                  // 1. Guard against route occlusion (Bottom Sheet, Dialog, or active sheet)
                  if (!_isRouteActive || _isAyahSheetOpen) {
                    _pendingTargetPage = targetPage;
                    return;
                  }

                  // 2. Guard against ongoing auto-animation
                  if (_isAutoPageAnimating) {
                    _pendingTargetPage = targetPage;
                    return;
                  }

                  // 3. Guard against active user page drag/scroll
                  if (_pageController.hasClients &&
                      _pageController.position.haveDimensions &&
                      _pageController.position.isScrollingNotifier.value) {
                    _pendingTargetPage = targetPage;
                    return;
                  }

                  // 4. Guard against recent manual interaction cooldown (1500ms)
                  final elapsedSinceInteraction =
                      DateTime.now().difference(_lastUserPageInteractionTime).inMilliseconds;
                  if (elapsedSinceInteraction < 1500) {
                    _pendingTargetPage = targetPage;
                    final remaining = (1500 - elapsedSinceInteraction).clamp(50, 1500);
                    _pendingPageTurnTimer?.cancel();
                    _pendingPageTurnTimer = Timer(
                      Duration(milliseconds: remaining + 50),
                      _checkAndApplyPendingPageTurn,
                    );
                    return;
                  }

                  // All clear: execute smooth auto-page turn immediately
                  if (_pageController.hasClients && !_isAutoPageAnimating) {
                    _isAutoPageAnimating = true;
                    _pendingTargetPage = null;
                    try {
                      await _pageController.animateToPage(
                        targetPage - 1,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                      );
                    } finally {
                      _isAutoPageAnimating = false;
                    }
                  }
                });
              } catch (_) {}
            },
            child: BlocBuilder<QuranAudioCubit, QuranAudioState>(
              bloc: audioCubit,
              buildWhen: (prev, curr) =>
                  prev.highlightState.activeAyah != curr.highlightState.activeAyah,
              builder: (context, audioState) {
                return buildBody(audioState.highlightState.activeAyah);
              },
            ),
          );
        } else {
          bodyContent = buildBody(null);
        }

        return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: bgColor,
          body: bodyContent,
        );
      },
    );
  }
}
