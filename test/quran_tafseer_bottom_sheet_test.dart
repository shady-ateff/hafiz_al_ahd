import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/widgets/app_loader.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_segment.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_ayah.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_tafseer.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/quran_tafseer_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_tafseer_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_tafseer_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_tafseer_bottom_sheet.dart';

class MockTafseerRepository implements QuranTafseerRepository {
  Completer<Either<Failure, QuranTafseer>>? completer;
  int callCount = 0;
  AyahId? lastRequestedAyahId;

  void prepareCompleter() {
    completer = Completer<Either<Failure, QuranTafseer>>();
  }

  @override
  Future<Either<Failure, QuranTafseer>> getTafseer(AyahId ayahId) {
    callCount++;
    lastRequestedAyahId = ayahId;
    return completer!.future;
  }
}

void main() {
  group('QuranTafseerBottomSheet Widget Tests (Phase 4B)', () {
    late MockTafseerRepository mockRepo;
    late GetQuranTafseerUseCase useCase;
    late QuranTafseerCubit cubit;

    final testAyah = QuranAyah(
      id: AyahId(surahNumber: 1, ayahNumber: 1),
      pageNumber: 1,
      endPageNumber: 1,
      uthmaniText: 'بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ',
      wordsCount: 4,
      segments: [
        AyahSegment(
          ayahId: AyahId(surahNumber: 1, ayahNumber: 1),
          pageNumber: 1,
          lineNumber: 2,
          wordStart: 0,
          wordEnd: 3,
          qcfText: 'بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ',
        ),
      ],
    );

    final sampleTafseer = QuranTafseer(
      ayahId: testAyah.id,
      rawText: 'أبتدئ قراءة القرآن باسم الله، ﵡ ٱللَّهِﵠ علم على الرب.',
      segments: const [
        TafseerSegment(
          text: 'أبتدئ قراءة القرآن باسم الله، ',
          type: TafseerSegmentType.commentary,
        ),
        TafseerSegment(
          text: 'ﵡ ٱللَّهِﵠ',
          type: TafseerSegmentType.quranQuote,
        ),
        TafseerSegment(
          text: ' علم على الرب.',
          type: TafseerSegmentType.commentary,
        ),
      ],
      sourceName: 'التفسير الميسر',
    );

    setUp(() {
      mockRepo = MockTafseerRepository();
      useCase = GetQuranTafseerUseCase(mockRepo);
      cubit = QuranTafseerCubit(getQuranTafseerUseCase: useCase);
    });

    tearDown(() async {
      await cubit.close();
    });

    Widget createTestApp({
      required Widget child,
      Size size = const Size(400, 800),
    }) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: Scaffold(body: child),
        ),
      );
    }

    testWidgets('1. Loading state displays indicator and message', (tester) async {
      mockRepo.prepareCompleter();

      await tester.pumpWidget(createTestApp(
        child: QuranTafseerBottomSheet(
          ayah: testAyah,
          cubit: cubit,
        ),
      ));

      // Trigger load
      unawaited(cubit.loadTafseer(testAyah.id));
      await tester.pump();

      expect(find.byKey(const Key('tafseer_loading_view')), findsOneWidget);
      expect(find.byType(AppLoader), findsOneWidget);
      expect(find.text('جارٍ تحميل التفسير...'), findsOneWidget);
    });

    testWidgets('2. Successful Tafseer rendering displays headers and text', (tester) async {
      mockRepo.prepareCompleter();

      await tester.pumpWidget(createTestApp(
        child: QuranTafseerBottomSheet(
          ayah: testAyah,
          cubit: cubit,
        ),
      ));

      final future = cubit.loadTafseer(testAyah.id);
      mockRepo.completer!.complete(Right(sampleTafseer));
      await future;
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tafseer_loaded_view')), findsOneWidget);
      expect(find.text('بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ'), findsOneWidget);
      expect(find.text('التفسير الميسر'), findsOneWidget);
      expect(find.text('مجمع الملك فهد لطباعة المصحف الشريف'), findsOneWidget);
      expect(find.textContaining('الفاتحة'), findsOneWidget);
    });

    testWidgets('3. Quran quotation highlighting uses gold and bold styling in RichText', (tester) async {
      mockRepo.prepareCompleter();

      await tester.pumpWidget(createTestApp(
        child: QuranTafseerBottomSheet(
          ayah: testAyah,
          cubit: cubit,
        ),
      ));

      final future = cubit.loadTafseer(testAyah.id);
      mockRepo.completer!.complete(Right(sampleTafseer));
      await future;
      await tester.pumpAndSettle();

      // Find commentary Text widget inside loaded view
      final richTextFinder = find.byKey(const Key('tafseer_commentary_text'));
      expect(richTextFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(richTextFinder);
      final span = textWidget.textSpan! as TextSpan;
      final children = span.children!;

      expect(children.length, equals(3));

      // 1. Commentary segment
      final segment1 = children[0] as TextSpan;
      expect(segment1.text, equals('أبتدئ قراءة القرآن باسم الله، '));
      expect(segment1.style?.fontFamily, equals('Tajawal'));

      // 2. Quran Quote segment
      final segment2 = children[1] as TextSpan;
      expect(segment2.text, equals('ﵡ ٱللَّهِﵠ'));
      expect(segment2.style?.fontFamily, equals('Amiri'));
      expect(segment2.style?.color, equals(AppColors.secondaryGold));
      expect(segment2.style?.fontWeight, equals(FontWeight.bold));

      // 3. Commentary segment
      final segment3 = children[2] as TextSpan;
      expect(segment3.text, equals(' علم على الرب.'));
      expect(segment3.style?.fontFamily, equals('Tajawal'));
    });

    testWidgets('4. Root Directionality is RTL', (tester) async {
      mockRepo.prepareCompleter();

      await tester.pumpWidget(createTestApp(
        child: QuranTafseerBottomSheet(
          ayah: testAyah,
          cubit: cubit,
        ),
      ));

      final directionality = tester.widget<Directionality>(
        find.descendant(
          of: find.byType(QuranTafseerBottomSheet),
          matching: find.byType(Directionality),
        ).first,
      );
      expect(directionality.textDirection, equals(TextDirection.rtl));
    });

    testWidgets('5. Long Tafseer commentary scrolls without overflow', (tester) async {
      mockRepo.prepareCompleter();

      // Build a long commentary
      final longSegments = List.generate(
        30,
        (i) => TafseerSegment(
          text: 'هذا مقطع تفسير طويل للاختبار والتأكد من قابلية التمرير دون حدوث أي خطأ تخطيط ($i). ',
          type: i.isEven ? TafseerSegmentType.commentary : TafseerSegmentType.quranQuote,
        ),
      );

      final longTafseer = QuranTafseer(
        ayahId: testAyah.id,
        rawText: longSegments.map((s) => s.text).join(),
        segments: longSegments,
      );

      await tester.pumpWidget(createTestApp(
        child: QuranTafseerBottomSheet(
          ayah: testAyah,
          cubit: cubit,
        ),
      ));

      final future = cubit.loadTafseer(testAyah.id);
      mockRepo.completer!.complete(Right(longTafseer));
      await future;
      await tester.pumpAndSettle();

      final listViewFinder = find.byType(ListView);
      expect(listViewFinder, findsOneWidget);

      // Perform scroll drag
      await tester.drag(listViewFinder, const Offset(0, -300));
      await tester.pumpAndSettle();

      // No overflow exceptions thrown
      expect(tester.takeException(), isNull);
    });

    testWidgets('6. Error state displays error view and message', (tester) async {
      mockRepo.prepareCompleter();

      await tester.pumpWidget(createTestApp(
        child: QuranTafseerBottomSheet(
          ayah: testAyah,
          cubit: cubit,
        ),
      ));

      final future = cubit.loadTafseer(testAyah.id);
      mockRepo.completer!.complete(Left(CacheFailure(message: 'ملف التفسير غير متوفر')));
      await future;
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tafseer_error_view')), findsOneWidget);
      expect(find.text('تعذر تحميل التفسير'), findsOneWidget);
      expect(find.text('ملف التفسير غير متوفر'), findsOneWidget);
      expect(find.byKey(const Key('tafseer_retry_button')), findsOneWidget);
    });

    testWidgets('7. Retry button re-executes loadTafseer', (tester) async {
      mockRepo.prepareCompleter();

      await tester.pumpWidget(createTestApp(
        child: QuranTafseerBottomSheet(
          ayah: testAyah,
          cubit: cubit,
        ),
      ));

      // 1. Initial request fails
      final future1 = cubit.loadTafseer(testAyah.id);
      mockRepo.completer!.complete(Left(CacheFailure(message: 'شبكة غير متاحة')));
      await future1;
      await tester.pumpAndSettle();

      expect(mockRepo.callCount, equals(1));
      expect(find.byKey(const Key('tafseer_error_view')), findsOneWidget);

      // 2. Prepare for retry
      mockRepo.prepareCompleter();

      // 3. Tap retry button
      await tester.tap(find.byKey(const Key('tafseer_retry_button')));
      await tester.pump();

      expect(mockRepo.callCount, equals(2));
      expect(find.byKey(const Key('tafseer_loading_view')), findsOneWidget);

      // Complete successfully
      mockRepo.completer!.complete(Right(sampleTafseer));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tafseer_loaded_view')), findsOneWidget);
    });

    testWidgets('8. Small screen resilience: renders safely without layout overflow', (tester) async {
      mockRepo.prepareCompleter();

      // Compact small screen (320x480)
      await tester.pumpWidget(createTestApp(
        size: const Size(320, 480),
        child: QuranTafseerBottomSheet(
          ayah: testAyah,
          cubit: cubit,
        ),
      ));

      final future = cubit.loadTafseer(testAyah.id);
      mockRepo.completer!.complete(Right(sampleTafseer));
      await future;
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tafseer_loaded_view')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

