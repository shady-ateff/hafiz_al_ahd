import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_segment.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_ayah.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_bookmark.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/base_quran_mapping_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_bookmarks_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/remove_quran_bookmark_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/toggle_quran_bookmark_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_bookmark_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_bookmark_state.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_ayah_action_bottom_sheet.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_bookmarks_bottom_sheet.dart';
import 'package:dartz/dartz.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_line_mapping.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_word.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/word_location.dart';

class FakeMappingRepo implements BaseQuranMappingRepository {
  final Map<AyahId, QuranAyah> ayahs = {};

  @override
  Future<Either<Failure, void>> init() async => const Right(null);

  @override
  Future<Either<Failure, QuranAyah>> getAyah(AyahId ayahId) async {
    final a = ayahs[ayahId];
    if (a != null) return Right(a);
    return Left(CacheFailure(message: 'Not found: $ayahId'));
  }

  @override
  Future<Either<Failure, List<AyahSegment>>> getAyahSegments(AyahId ayahId) async =>
      const Right([]);

  @override
  Future<Either<Failure, List<QuranLineMapping>>> getPageMapping(int pageNumber) async =>
      const Right([]);

  @override
  Future<Either<Failure, QuranWord>> getWord(WordLocation location) async =>
      Left(CacheFailure(message: 'Not implemented'));
}

class FakeBookmarkRepo implements BaseQuranBookmarkLocalDataSourceDummy {
  final List<QuranBookmark> bookmarks = [];
}

abstract class BaseQuranBookmarkLocalDataSourceDummy {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranAyah testAyah1;
  late QuranAyah testAyah2;
  late FakeMappingRepo fakeMappingRepo;

  setUpAll(() {
    testAyah1 = QuranAyah(
      id: AyahId(surahNumber: 1, ayahNumber: 1),
      pageNumber: 1,
      endPageNumber: 1,
      uthmaniText: 'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
      wordsCount: 4,
      segments: [
        AyahSegment(
          ayahId: AyahId(surahNumber: 1, ayahNumber: 1),
          pageNumber: 1,
          lineNumber: 1,
          wordStart: 0,
          wordEnd: 3,
          qcfText: 'ﱁ ﱂ ﱃ ﱄ',
        ),
      ],
    );

    testAyah2 = QuranAyah(
      id: AyahId(surahNumber: 2, ayahNumber: 255),
      pageNumber: 42,
      endPageNumber: 42,
      uthmaniText: 'ٱللَّهُ لَآ إِلَـٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ',
      wordsCount: 6,
      segments: [
        AyahSegment(
          ayahId: AyahId(surahNumber: 2, ayahNumber: 255),
          pageNumber: 42,
          lineNumber: 1,
          wordStart: 0,
          wordEnd: 5,
          qcfText: 'ﭐ ﭒ ﭓ ﭔ ﭕ ﭖ',
        ),
      ],
    );

    fakeMappingRepo = FakeMappingRepo();
    fakeMappingRepo.ayahs[testAyah1.id] = testAyah1;
    fakeMappingRepo.ayahs[testAyah2.id] = testAyah2;

    if (sl.isRegistered<BaseQuranMappingRepository>()) {
      sl.unregister<BaseQuranMappingRepository>();
    }
    sl.registerSingleton<BaseQuranMappingRepository>(fakeMappingRepo);
  });

  group('Phase 2.6.3.4 — Quran Ayah Bookmark UI Tests', () {
    testWidgets('1. QuranAyahActionBottomSheet displays outline icon when isBookmarked is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuranAyahActionBottomSheet(
              ayah: testAyah1,
              isBookmarked: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check for outline icon
      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_rounded), findsNothing);
      expect(find.text('فاصلة'), findsOneWidget);
    });

    testWidgets('2. QuranAyahActionBottomSheet displays filled bookmark icon when isBookmarked is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuranAyahActionBottomSheet(
              ayah: testAyah1,
              isBookmarked: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check for filled gold icon
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsNothing);
      expect(find.text('فاصلة'), findsOneWidget);
    });

    testWidgets('3. Tapping bookmark action triggers onBookmarkTap callback', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuranAyahActionBottomSheet(
              ayah: testAyah1,
              isBookmarked: false,
              onBookmarkTap: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('فاصلة'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('4. QuranBookmarksBottomSheet renders empty state when no bookmarks exist', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<QuranBookmarkCubit>(
              create: (context) => _TestBookmarkCubit(bookmarks: []),
              child: QuranBookmarksBottomSheet(
                onBookmarkSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('لا توجد فواصل محفوظة بعد'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_outline_rounded), findsOneWidget);
    });

    testWidgets('5. QuranBookmarksBottomSheet displays list of bookmarks with canonical text and metadata', (tester) async {
      final b1 = QuranBookmark(
        ayahId: testAyah1.id,
        pageNumber: 1,
        createdAt: DateTime(2026, 11, 2, 10, 0),
      );
      final b2 = QuranBookmark(
        ayahId: testAyah2.id,
        pageNumber: 42,
        createdAt: DateTime(2026, 11, 2, 9, 0),
      );

      QuranBookmark? selectedBookmark;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<QuranBookmarkCubit>(
              create: (context) => _TestBookmarkCubit(bookmarks: [b1, b2]),
              child: QuranBookmarksBottomSheet(
                onBookmarkSelected: (b) => selectedBookmark = b,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Surah and Ayah metadata
      expect(find.textContaining('سورة الفاتحة'), findsOneWidget);
      expect(find.textContaining('الآية 1'), findsOneWidget);
      expect(find.textContaining('صـ 1'), findsOneWidget);

      expect(find.textContaining('سورة البقرة'), findsOneWidget);
      expect(find.textContaining('الآية 255'), findsOneWidget);
      expect(find.textContaining('صـ 42'), findsOneWidget);

      // Verify Canonical Uthmani Text is resolved and displayed
      expect(find.textContaining(testAyah1.uthmaniText), findsOneWidget);
      expect(find.textContaining(testAyah2.uthmaniText), findsOneWidget);

      // Tap on the first bookmark
      await tester.tap(find.textContaining('سورة الفاتحة'));
      await tester.pumpAndSettle();

      expect(selectedBookmark, equals(b1));
    });

    testWidgets('6. QuranBookmarksBottomSheet supports Dismissible swipe and displays custom name tag', (tester) async {
      final bCustom = QuranBookmark(
        ayahId: testAyah1.id,
        pageNumber: 1,
        createdAt: DateTime(2026, 11, 2, 10, 0),
        name: 'فاصل ورد الحفظ',
        colorCode: 0xFF2E7D32,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<QuranBookmarkCubit>(
              create: (context) => _TestBookmarkCubit(bookmarks: [bCustom]),
              child: QuranBookmarksBottomSheet(
                onBookmarkSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify custom name tag badge is rendered
      expect(find.text('فاصل ورد الحفظ'), findsOneWidget);

      // Verify card is wrapped in a Dismissible widget
      expect(find.byType(Dismissible), findsOneWidget);

      // Swipe to dismiss
      await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Verify Undo (تراجع) button appears
      expect(find.text('تراجع'), findsWidgets);

      // Tap Undo
      await tester.tap(find.text('تراجع').first);
      await tester.pumpAndSettle();

      // Verify bookmark is restored
      expect(find.text('فاصل ورد الحفظ'), findsOneWidget);
    });

    testWidgets('7. Dismissing multiple bookmarks shows aggregated count and Undo restores all items', (tester) async {
      final b1 = QuranBookmark(
        ayahId: testAyah1.id,
        pageNumber: 1,
        createdAt: DateTime(2026, 11, 2, 10, 0),
        name: 'فاصل الأول',
      );
      final b2 = QuranBookmark(
        ayahId: testAyah2.id,
        pageNumber: 42,
        createdAt: DateTime(2026, 11, 2, 9, 0),
        name: 'فاصل الثاني',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<QuranBookmarkCubit>(
              create: (context) => _TestBookmarkCubit(bookmarks: [b1, b2]),
              child: QuranBookmarksBottomSheet(
                onBookmarkSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final key1 = ValueKey('bookmark_${testAyah1.id.formatted}');
      final key2 = ValueKey('bookmark_${testAyah2.id.formatted}');

      expect(find.byKey(key1), findsOneWidget);
      expect(find.byKey(key2), findsOneWidget);

      // Dismiss first bookmark
      await tester.drag(find.byKey(key1), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('تم حذف "فاصل الأول"'), findsOneWidget);
      expect(find.byKey(key1), findsNothing);
      expect(find.byKey(key2), findsOneWidget);

      // Dismiss second bookmark
      await tester.drag(find.byKey(key2), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.byKey(key1), findsNothing);
      expect(find.byKey(key2), findsNothing);

      // Aggregated banner shows count
      expect(find.text('تم حذف 2 فواصل'), findsWidgets);
      expect(find.text('تراجع عن الكل'), findsWidgets);

      // Tap Undo all
      await tester.tap(find.text('تراجع عن الكل').first);
      await tester.pumpAndSettle();

      // Verify both bookmarks are restored
      expect(find.byKey(key1), findsOneWidget);
      expect(find.byKey(key2), findsOneWidget);
      expect(find.text('فاصل الأول'), findsOneWidget);
      expect(find.text('فاصل الثاني'), findsOneWidget);
    });
  });
}

class _TestBookmarkCubit extends QuranBookmarkCubit {
  final List<QuranBookmark> _initialList;

  _TestBookmarkCubit({required List<QuranBookmark> bookmarks})
      : _initialList = bookmarks,
        super(
          getBookmarksUseCase: _DummyGetUseCase(),
          toggleBookmarkUseCase: _DummyToggleUseCase(),
          removeBookmarkUseCase: _DummyRemoveUseCase(),
        ) {
    emit(QuranBookmarkLoaded(_initialList));
  }

  @override
  Future<void> removeBookmark(AyahId ayahId) async {
    _initialList.removeWhere((b) => b.ayahId == ayahId);
    emit(QuranBookmarkLoaded(List.from(_initialList)));
  }

  @override
  Future<QuranBookmark?> saveBookmark({
    required AyahId ayahId,
    int? pageNumber,
    DateTime? createdAt,
    String? name,
    int? colorCode,
  }) async {
    final b = QuranBookmark(
      ayahId: ayahId,
      pageNumber: pageNumber,
      createdAt: createdAt ?? DateTime.now(),
      name: name,
      colorCode: colorCode,
    );
    _initialList.add(b);
    emit(QuranBookmarkLoaded(List.from(_initialList)));
    return b;
  }

  @override
  Future<void> restoreBookmarks(List<QuranBookmark> bookmarks) async {
    for (final b in bookmarks) {
      if (!_initialList.any((item) => item.ayahId == b.ayahId)) {
        _initialList.add(b);
      }
    }
    emit(QuranBookmarkLoaded(List.from(_initialList)));
  }
}

class _DummyGetUseCase implements GetQuranBookmarksUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DummyToggleUseCase implements ToggleQuranBookmarkUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DummyRemoveUseCase implements RemoveQuranBookmarkUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

