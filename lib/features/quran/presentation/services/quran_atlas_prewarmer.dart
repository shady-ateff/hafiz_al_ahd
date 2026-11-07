import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../domain/entities/quran_page.dart';
import '../cubit/quran_cubit.dart';
import '../cubit/quran_state.dart';

/// Contract for offscreen Glyph Atlas Prewarming.
///
/// Prewarms the upcoming Quran page's glyphs into the Impeller Vulkan Glyph Atlas
/// using an offscreen [ui.PictureRecorder] and [ui.Canvas] pass.
abstract class BaseQuranAtlasPrewarmer {
  /// Schedules an offscreen glyph atlas rasterization pass for [targetPageNumber]
  /// at [Priority.idle].
  ///
  /// [currentVisiblePage] is the currently visible page in the reader.
  /// Prewarming is strictly forward-only: [targetPageNumber] must be exactly
  /// `currentVisiblePage + 1`. If [targetPageNumber] <= [currentVisiblePage] or
  /// beyond page 604, the request is ignored.
  ///
  /// [isEligible] is an optional predicate (e.g. checking route and app lifecycle)
  /// evaluated both at schedule time and immediately before recording.
  void schedulePrewarm({
    required int targetPageNumber,
    required QuranCubit cubit,
    int? currentVisiblePage,
    bool Function()? isEligible,
  });

  /// Cancels any pending scheduled idle task and invalidates in-flight completions.
  void cancel();

  /// Disposes internal state and cancels any pending callbacks.
  void dispose();
}

/// Production implementation of [BaseQuranAtlasPrewarmer].
///
/// Ensures:
/// 1. Forward-only single-page lookahead ($N+1$, up to 604).
/// 2. Non-overlapping execution (at most 1 active offscreen rasterization pass).
/// 3. Immediate cancellation on user interaction, route coverage, or page changes.
/// 4. Zero persistent references to [ui.Paragraph], [ui.Picture], or [ui.Image].
/// 5. Try/finally disposal safety on all engine handles.
class QuranAtlasPrewarmer implements BaseQuranAtlasPrewarmer {
  final void Function(TaskCallback<dynamic> task, Priority priority)? _taskScheduler;

  int _activeToken = 0;
  int? _pendingTargetPage;
  QuranCubit? _pendingCubit;
  bool Function()? _pendingEligibilityCheck;
  bool _isRunning = false;
  bool _isScheduled = false;
  bool _isDisposed = false;

  final Set<int> _prewarmedPages = <int>{};
  int? _lastPrewarmedPage;

  QuranAtlasPrewarmer({
    void Function(TaskCallback<dynamic> task, Priority priority)? taskScheduler,
  }) : _taskScheduler = taskScheduler;

  /// Whether an offscreen rasterization pass is currently executing on the raster thread.
  bool get isRunning => _isRunning;

  /// Whether an idle prewarming task is currently waiting in the scheduler queue.
  bool get isScheduled => _isScheduled;

  /// The most recently completed prewarm target page number.
  int? get lastPrewarmedPage => _lastPrewarmedPage;

  /// Unmodifiable view of all pages successfully prewarmed in this session.
  Set<int> get prewarmedPages => Set.unmodifiable(_prewarmedPages);

  /// Returns true if [pageNumber] has already been prewarmed into the glyph atlas.
  bool isPagePrewarmed(int pageNumber) => _prewarmedPages.contains(pageNumber);

  @override
  void schedulePrewarm({
    required int targetPageNumber,
    required QuranCubit cubit,
    int? currentVisiblePage,
    bool Function()? isEligible,
  }) {
    if (_isDisposed) return;

    // Boundary constraints: strictly between 1 and 604
    if (targetPageNumber < 1 || targetPageNumber > 604) return;

    // Forward-only constraint: must target N + 1 and not current visible page
    if (currentVisiblePage != null) {
      if (targetPageNumber != currentVisiblePage + 1) return;
      if (targetPageNumber <= currentVisiblePage) return;
    }

    // Skip already successfully prewarmed targets
    if (_prewarmedPages.contains(targetPageNumber)) return;

    // Check optional eligibility predicate
    if (isEligible != null && !isEligible()) return;

    // Invalidate any previously pending task
    _activeToken++;
    _pendingTargetPage = targetPageNumber;
    _pendingCubit = cubit;
    _pendingEligibilityCheck = isEligible;

    if (!_isScheduled && !_isRunning) {
      _isScheduled = true;
      final scheduler = _taskScheduler ??
          ((task, priority) =>
              SchedulerBinding.instance.scheduleTask(task, priority));

      scheduler(() => _executeTask(), Priority.idle);
    }
  }

  Future<void> _executeTask() async {
    _isScheduled = false;

    if (_isDisposed) return;
    if (_isRunning) return;

    final int executionToken = _activeToken;
    final int? target = _pendingTargetPage;
    final QuranCubit? cubit = _pendingCubit;
    final bool Function()? isEligible = _pendingEligibilityCheck;

    if (target == null || cubit == null) return;
    if (isEligible != null && !isEligible()) return;
    if (_prewarmedPages.contains(target)) return;

    _isRunning = true;
    try {
      await _performPrewarm(
        targetPageNumber: target,
        cubit: cubit,
        taskToken: executionToken,
        isEligible: isEligible,
      );
    } finally {
      _isRunning = false;

      // If a newer target arrived while this task was in flight, schedule it sequentially
      if (!_isDisposed &&
          _activeToken != executionToken &&
          _pendingTargetPage != null &&
          _pendingTargetPage != target) {
        _isScheduled = true;
        final scheduler = _taskScheduler ??
            ((task, priority) =>
                SchedulerBinding.instance.scheduleTask(task, priority));
        scheduler(() => _executeTask(), Priority.idle);
      }
    }
  }

  Future<void> _performPrewarm({
    required int targetPageNumber,
    required QuranCubit cubit,
    required int taskToken,
    required bool Function()? isEligible,
  }) async {
    // 1. Double-check token, disposal, and eligibility
    if (_isDisposed || _activeToken != taskToken) return;
    if (isEligible != null && !isEligible()) return;

    // 2. Verify global font system readiness
    if (!cubit.fontsReady) return;

    // 3. Verify cached page data availability (awaiting preload if in flight)
    var cachedState = cubit.getCachedPage(targetPageNumber);
    if (cachedState == null || !cachedState.isFontLoaded) {
      await cubit.preloadPage(targetPageNumber);
      if (_isDisposed || _activeToken != taskToken) return;
      if (isEligible != null && !isEligible()) return;
      cachedState = cubit.getCachedPage(targetPageNumber);
    }
    if (cachedState == null || !cachedState.isFontLoaded) return;
    if (!cubit.isFontLoaded(targetPageNumber)) return;

    final page = cachedState.page;
    final fontFamily = QuranCubit.getFontFamilyForPage(targetPageNumber);

    // 4. Record offscreen DisplayList using actual production line text and fonts
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    ui.Picture? picture;

    try {
      double y = 0.0;
      final int maxLines =
          (targetPageNumber == 1 || targetPageNumber == 2) ? 7 : 15;
      int expectedLine = 1;

      for (final line in page.lines) {
        if (_isDisposed || _activeToken != taskToken) {
          picture = recorder.endRecording();
          return;
        }

        // Handle Surah header and Basmalah gaps matching production QuranPageWidget logic
        if (line.lineNumber > expectedLine) {
          final int gapSize = line.lineNumber - expectedLine;
          if (gapSize == 2) {
            _drawSurahHeader(canvas, line.surahNumber, y);
            y += 45.0;
            _drawBasmalah(canvas, y);
            y += 45.0;
          } else if (gapSize == 1) {
            if (line.surahNumber == 1 || line.surahNumber == 9) {
              _drawSurahHeader(canvas, line.surahNumber, y);
              y += 45.0;
            } else {
              _drawBasmalah(canvas, y);
              y += 45.0;
            }
          }
          expectedLine = line.lineNumber;
        }

        // Draw production line text with correct QCF2 font and RTL direction
        final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
          fontFamily: fontFamily,
          fontSize: 40.0,
          textDirection: TextDirection.rtl,
        ))
          ..pushStyle(ui.TextStyle(
            fontFamily: fontFamily,
            fontSize: 40.0,
          ))
          ..addText(line.text);

        final paragraph = pb.build();
        paragraph.layout(const ui.ParagraphConstraints(width: 700.0));
        canvas.drawParagraph(paragraph, Offset(0, y));
        y += 45.0;

        expectedLine = line.lineNumber + 1;
      }

      // Check trailing Surah header / Basmalah at bottom of page
      if (expectedLine <= maxLines) {
        final int gapSize = maxLines - expectedLine + 1;
        final int nextSurah =
            page.lines.isNotEmpty ? page.lines.last.surahNumber + 1 : 1;
        if (nextSurah <= 114) {
          if (gapSize == 2) {
            _drawSurahHeader(canvas, nextSurah, y);
            y += 45.0;
            if (nextSurah != 9) {
              _drawBasmalah(canvas, y);
              y += 45.0;
            }
          } else if (gapSize == 1) {
            _drawSurahHeader(canvas, nextSurah, y);
            y += 45.0;
          }
        }
      }

      picture = recorder.endRecording();

      // Check token once more before dispatching GPU raster work
      if (_isDisposed || _activeToken != taskToken) return;

      // 5. Dispatch offscreen rasterization to Raster thread
      // This populates the Impeller Vulkan GlyphAtlas with the exact glyph textures
      final int rasterHeight = (y + 100).toInt().clamp(500, 1500);
      final ui.Image image = await picture.toImage(700, rasterHeight);
      try {
        // Disposed immediately: the Vulkan GlyphAtlas retains the glyph textures,
        // while the offscreen RGBA pixel buffer is freed right away.
      } finally {
        image.dispose();
      }

      // 6. Record success if task was not cancelled during await
      if (!_isDisposed && _activeToken == taskToken) {
        _prewarmedPages.add(targetPageNumber);
        _lastPrewarmedPage = targetPageNumber;
      }
    } catch (_) {
      // Prewarming failure must never block or crash user reading
    } finally {
      picture?.dispose();
    }
  }

  void _drawSurahHeader(Canvas canvas, int surahNumber, double y) {
    final String titleText = getQcfSurahName(surahNumber);
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: 'QCF_BSML',
      fontSize: 50.0,
      textDirection: TextDirection.rtl,
    ))
      ..pushStyle(ui.TextStyle(
        fontFamily: 'QCF_BSML',
        fontSize: 50.0,
      ))
      ..addText(titleText);

    final paragraph = pb.build();
    paragraph.layout(const ui.ParagraphConstraints(width: 700.0));
    canvas.drawParagraph(paragraph, Offset(0, y));
  }

  void _drawBasmalah(Canvas canvas, double y) {
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: 'QCF2001',
      fontSize: 40.0,
      textDirection: TextDirection.rtl,
    ))
      ..pushStyle(ui.TextStyle(
        fontFamily: 'QCF2001',
        fontSize: 40.0,
      ))
      ..addText("ﱁ ﱂ ﱃ ﱄ");

    final paragraph = pb.build();
    paragraph.layout(const ui.ParagraphConstraints(width: 700.0));
    canvas.drawParagraph(paragraph, Offset(0, y));
  }

  /// Calculates the QCF Surah Name glyph code matching production [QuranPageWidget].
  static String getQcfSurahName(int surahNumber) {
    String surahName = "";
    if (64396 + surahNumber >= 64434) {
      surahName = String.fromCharCode(64429 + surahNumber);
    } else {
      surahName = String.fromCharCode(64396 + surahNumber);
    }
    return "${String.fromCharCode(64396)} $surahName";
  }

  @override
  void cancel() {
    _activeToken++;
    _pendingTargetPage = null;
    _pendingCubit = null;
    _pendingEligibilityCheck = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _activeToken++;
    _pendingTargetPage = null;
    _pendingCubit = null;
    _pendingEligibilityCheck = null;
    _prewarmedPages.clear();
  }
}
