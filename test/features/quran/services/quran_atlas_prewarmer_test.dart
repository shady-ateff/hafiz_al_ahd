import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_page.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_page_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_state.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/services/quran_atlas_prewarmer.dart';

class FakeGetQuranPageUseCase implements GetQuranPageUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTestQuranCubit extends QuranCubit {
  bool testFontsReady = true;
  final Set<int> testLoadedFonts = <int>{};
  final Map<int, QuranPageLoaded> testPagesCache = <int, QuranPageLoaded>{};

  FakeTestQuranCubit() : super(getQuranPageUseCase: FakeGetQuranPageUseCase());

  @override
  bool get fontsReady => testFontsReady;

  @override
  bool isFontLoaded(int pageNumber) => testLoadedFonts.contains(pageNumber);

  @override
  QuranPageLoaded? getCachedPage(int pageNumber) => testPagesCache[pageNumber];

  @override
  Future<void> initFonts() async {}

  @override
  Future<void> preloadPage(int pageNumber) async {}

  void setupPage({
    required int pageNumber,
    required List<QuranLine> lines,
    bool isFontLoaded = true,
  }) {
    if (isFontLoaded) {
      testLoadedFonts.add(pageNumber);
      testLoadedFonts.add(1); // QCF2001 for Basmalah
    }
    testPagesCache[pageNumber] = QuranPageLoaded(
      page: QuranPage(pageNumber: pageNumber, lines: lines),
      isFontLoaded: isFontLoaded,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeTestQuranCubit fakeCubit;
  late List<TaskCallback<dynamic>> scheduledTasks;
  late void Function(TaskCallback<dynamic> task, Priority priority) testScheduler;

  setUp(() {
    fakeCubit = FakeTestQuranCubit();
    scheduledTasks = [];
    testScheduler = (task, priority) {
      scheduledTasks.add(task);
    };
  });

  QuranPageLoaded createStandardPage(int pageNumber) {
    return QuranPageLoaded(
      page: QuranPage(
        pageNumber: pageNumber,
        lines: List.generate(
          15,
          (i) => QuranLine(
            lineNumber: i + 1,
            surahNumber: 2,
            text: 'كلمات تجريبية لصفحة المصحف $pageNumber سطر ${i + 1}',
          ),
        ),
      ),
      isFontLoaded: true,
    );
  }

  QuranPageLoaded createHeaderPage(int pageNumber) {
    // Page with gap at line 1 and 2 for Surah header and Basmalah (lines 3..15)
    return QuranPageLoaded(
      page: QuranPage(
        pageNumber: pageNumber,
        lines: [
          const QuranLine(lineNumber: 3, surahNumber: 18, text: 'الحمد لله الذي أنزل على عبده الكتاب'),
          const QuranLine(lineNumber: 4, surahNumber: 18, text: 'قيما لينذر بأسا شديدا من لدنه'),
        ],
      ),
      isFontLoaded: true,
    );
  }

  group('P3.6-B — QuranAtlasPrewarmer Target Calculation & Boundary Tests', () {
    test('1. Rejects invalid page numbers (< 1 or > 604)', () {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);

      prewarmer.schedulePrewarm(
        targetPageNumber: 0,
        cubit: fakeCubit,
        currentVisiblePage: 0,
      );
      expect(scheduledTasks, isEmpty);

      prewarmer.schedulePrewarm(
        targetPageNumber: 605,
        cubit: fakeCubit,
        currentVisiblePage: 604,
      );
      expect(scheduledTasks, isEmpty);

      prewarmer.dispose();
    });

    test('2. Enforces forward-only N+1 rule', () {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);

      // Rejects reverse navigation (N-1)
      prewarmer.schedulePrewarm(
        targetPageNumber: 64,
        cubit: fakeCubit,
        currentVisiblePage: 65,
      );
      expect(scheduledTasks, isEmpty);

      // Rejects same-page target
      prewarmer.schedulePrewarm(
        targetPageNumber: 65,
        cubit: fakeCubit,
        currentVisiblePage: 65,
      );
      expect(scheduledTasks, isEmpty);

      // Rejects multi-page jump forward (e.g. N+2)
      prewarmer.schedulePrewarm(
        targetPageNumber: 67,
        cubit: fakeCubit,
        currentVisiblePage: 65,
      );
      expect(scheduledTasks, isEmpty);

      // Accepts exact N+1
      prewarmer.schedulePrewarm(
        targetPageNumber: 66,
        cubit: fakeCubit,
        currentVisiblePage: 65,
      );
      expect(scheduledTasks.length, 1);

      prewarmer.dispose();
    });

    test('3. Respects page 604 terminal boundary', () {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);

      // At page 603, target 604 is accepted
      prewarmer.schedulePrewarm(
        targetPageNumber: 604,
        cubit: fakeCubit,
        currentVisiblePage: 603,
      );
      expect(scheduledTasks.length, 1);

      // At page 604, target 605 is rejected
      prewarmer.schedulePrewarm(
        targetPageNumber: 605,
        cubit: fakeCubit,
        currentVisiblePage: 604,
      );
      expect(scheduledTasks.length, 1); // still 1

      prewarmer.dispose();
    });
  });

  group('P3.6-B — QuranAtlasPrewarmer Deduplication & Cancellation Tests', () {
    test('4. Suppresses duplicate prewarming of already-completed targets', () async {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);
      fakeCubit.setupPage(pageNumber: 66, lines: createStandardPage(66).page.lines);

      prewarmer.schedulePrewarm(
        targetPageNumber: 66,
        cubit: fakeCubit,
        currentVisiblePage: 65,
      );
      expect(scheduledTasks.length, 1);

      // Run task
      await scheduledTasks.removeAt(0)();
      expect(prewarmer.lastPrewarmedPage, 66);
      expect(prewarmer.isPagePrewarmed(66), isTrue);

      // Subsequent schedule for page 66 is skipped
      prewarmer.schedulePrewarm(
        targetPageNumber: 66,
        cubit: fakeCubit,
        currentVisiblePage: 65,
      );
      expect(scheduledTasks, isEmpty);

      prewarmer.dispose();
    });

    test('5. Pending cancellation invalidates scheduled task before execution', () async {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);
      fakeCubit.setupPage(pageNumber: 66, lines: createStandardPage(66).page.lines);

      prewarmer.schedulePrewarm(
        targetPageNumber: 66,
        cubit: fakeCubit,
        currentVisiblePage: 65,
      );
      expect(scheduledTasks.length, 1);

      // User touches screen or interrupts -> cancel()
      prewarmer.cancel();

      // Scheduled callback fires later at idle
      await scheduledTasks.removeAt(0)();

      // Did not prewarm
      expect(prewarmer.lastPrewarmedPage, isNull);
      expect(prewarmer.isPagePrewarmed(66), isFalse);

      prewarmer.dispose();
    });

    test('6. Disposal safety: rejects new schedules and clears state', () async {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);
      fakeCubit.setupPage(pageNumber: 66, lines: createStandardPage(66).page.lines);

      prewarmer.schedulePrewarm(
        targetPageNumber: 66,
        cubit: fakeCubit,
        currentVisiblePage: 65,
      );
      expect(scheduledTasks.length, 1);

      prewarmer.dispose();

      // Fire pending callback after disposal
      await scheduledTasks.removeAt(0)();
      expect(prewarmer.lastPrewarmedPage, isNull);

      // Subsequent calls after dispose are ignored
      prewarmer.schedulePrewarm(
        targetPageNumber: 67,
        cubit: fakeCubit,
        currentVisiblePage: 66,
      );
      expect(scheduledTasks, isEmpty);
    });

    test('7. Rapid target replacement executes only the latest resting target', () async {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);
      fakeCubit.setupPage(pageNumber: 66, lines: createStandardPage(66).page.lines);
      fakeCubit.setupPage(pageNumber: 67, lines: createStandardPage(67).page.lines);
      fakeCubit.setupPage(pageNumber: 68, lines: createStandardPage(68).page.lines);

      // User flings quickly: 64 -> 65 -> 66 -> 67
      prewarmer.schedulePrewarm(
        targetPageNumber: 66,
        cubit: fakeCubit,
        currentVisiblePage: 65,
      );
      prewarmer.schedulePrewarm(
        targetPageNumber: 67,
        cubit: fakeCubit,
        currentVisiblePage: 66,
      );
      prewarmer.schedulePrewarm(
        targetPageNumber: 68,
        cubit: fakeCubit,
        currentVisiblePage: 67,
      );

      // Only 1 task scheduled for idle queue
      expect(scheduledTasks.length, 1);

      // Execute idle queue
      await scheduledTasks.removeAt(0)();

      // Only the resting target (68) was prewarmed; 66 and 67 were bypassed
      expect(prewarmer.lastPrewarmedPage, 68);
      expect(prewarmer.isPagePrewarmed(68), isTrue);
      expect(prewarmer.isPagePrewarmed(66), isFalse);
      expect(prewarmer.isPagePrewarmed(67), isFalse);

      prewarmer.dispose();
    });
  });

  group('P3.6-B — QuranAtlasPrewarmer Guard & Reliability Tests', () {
    test('8. Aborts early when fontsReady is false', () async {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);
      fakeCubit.testFontsReady = false;
      fakeCubit.setupPage(pageNumber: 66, lines: createStandardPage(66).page.lines);

      prewarmer.schedulePrewarm(
        targetPageNumber: 66,
        cubit: fakeCubit,
        currentVisiblePage: 65,
      );
      await scheduledTasks.removeAt(0)();

      expect(prewarmer.lastPrewarmedPage, isNull);
      prewarmer.dispose();
    });

    test('9. Aborts early when font for target page is not loaded', () async {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);
      fakeCubit.setupPage(
        pageNumber: 66,
        lines: createStandardPage(66).page.lines,
        isFontLoaded: false,
      );

      prewarmer.schedulePrewarm(
        targetPageNumber: 66,
        cubit: fakeCubit,
        currentVisiblePage: 65,
      );
      await scheduledTasks.removeAt(0)();

      expect(prewarmer.lastPrewarmedPage, isNull);
      prewarmer.dispose();
    });

    test('10. Aborts gracefully when page cache is missing', () async {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);
      // Page 66 is not in fakeCubit cache

      prewarmer.schedulePrewarm(
        targetPageNumber: 66,
        cubit: fakeCubit,
        currentVisiblePage: 65,
      );
      await scheduledTasks.removeAt(0)();

      expect(prewarmer.lastPrewarmedPage, isNull);
      prewarmer.dispose();
    });

    test('11. Respects eligibility predicate (route covered or backgrounded)', () async {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);
      fakeCubit.setupPage(pageNumber: 66, lines: createStandardPage(66).page.lines);

      bool isEligible = false;

      prewarmer.schedulePrewarm(
        targetPageNumber: 66,
        cubit: fakeCubit,
        currentVisiblePage: 65,
        isEligible: () => isEligible,
      );

      // When scheduled with isEligible == false, not even enqueued
      expect(scheduledTasks, isEmpty);

      // Now set eligible to true and schedule
      isEligible = true;
      prewarmer.schedulePrewarm(
        targetPageNumber: 66,
        cubit: fakeCubit,
        currentVisiblePage: 65,
        isEligible: () => isEligible,
      );
      expect(scheduledTasks.length, 1);

      // App goes background before task executes
      isEligible = false;
      await scheduledTasks.removeAt(0)();

      expect(prewarmer.lastPrewarmedPage, isNull);
      prewarmer.dispose();
    });

    test('12. Renders Surah Header and Basmalah glyphs without crash', () async {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);
      final headerPage = createHeaderPage(77);
      fakeCubit.setupPage(pageNumber: 77, lines: headerPage.page.lines);

      prewarmer.schedulePrewarm(
        targetPageNumber: 77,
        cubit: fakeCubit,
        currentVisiblePage: 76,
      );
      expect(scheduledTasks.length, 1);

      await scheduledTasks.removeAt(0)();

      expect(prewarmer.lastPrewarmedPage, 77);
      expect(prewarmer.isPagePrewarmed(77), isTrue);
      prewarmer.dispose();
    });

    test('13. Non-overlapping execution: sequential queuing when busy', () async {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);
      fakeCubit.setupPage(pageNumber: 66, lines: createStandardPage(66).page.lines);
      fakeCubit.setupPage(pageNumber: 67, lines: createStandardPage(67).page.lines);

      prewarmer.schedulePrewarm(
        targetPageNumber: 66,
        cubit: fakeCubit,
        currentVisiblePage: 65,
      );
      expect(scheduledTasks.length, 1);

      // While task 1 is queued/running, a second prewarm arrives
      prewarmer.schedulePrewarm(
        targetPageNumber: 67,
        cubit: fakeCubit,
        currentVisiblePage: 66,
      );

      // Still only 1 pending in scheduler queue (no overlap)
      expect(scheduledTasks.length, 1);

      await scheduledTasks.removeAt(0)();

      // Only the latest target executed
      expect(prewarmer.lastPrewarmedPage, 67);
      prewarmer.dispose();
    });

    test('14. Failure resilience: handles corrupted lines gracefully without throwing', () async {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);
      // Setup page with null or malformed line text scenario
      fakeCubit.setupPage(
        pageNumber: 66,
        lines: [
          const QuranLine(lineNumber: 1, surahNumber: 2, text: ''),
        ],
      );

      prewarmer.schedulePrewarm(
        targetPageNumber: 66,
        cubit: fakeCubit,
        currentVisiblePage: 65,
      );
      expect(scheduledTasks.length, 1);

      // Should complete without throwing
      await expectLater(scheduledTasks.removeAt(0)(), completes);
      expect(prewarmer.isRunning, isFalse);
      prewarmer.dispose();
    });

    test('15. Single-page forward only: rejects backward navigation target even if valid page', () {
      final prewarmer = QuranAtlasPrewarmer(taskScheduler: testScheduler);

      prewarmer.schedulePrewarm(
        targetPageNumber: 10,
        cubit: fakeCubit,
        currentVisiblePage: 11, // user is at 11, moving back to 10
      );
      expect(scheduledTasks, isEmpty);

      prewarmer.dispose();
    });
  });
}
