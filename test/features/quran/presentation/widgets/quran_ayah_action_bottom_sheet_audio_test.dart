import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_segment.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_ayah.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_ayah_action_bottom_sheet.dart';

void main() {
  final testAyah = QuranAyah(
    id: AyahId(surahNumber: 1, ayahNumber: 1),
    pageNumber: 1,
    endPageNumber: 1,
    uthmaniText: 'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
    wordsCount: 4,
    segments: [
      AyahSegment(
        ayahId: AyahId(surahNumber: 1, ayahNumber: 1),
        pageNumber: 1,
        lineNumber: 2,
        wordStart: 0,
        wordEnd: 3,
        qcfText: 'ﱁ ﱂ ﱃ ﱄ ﱅ',
      ),
    ],
  );

  Widget buildTestSheet({
    VoidCallback? onPlayAudioTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: QuranAyahActionBottomSheet(
          ayah: testAyah,
          onPlayAudioTap: onPlayAudioTap,
        ),
      ),
    );
  }

  group('QuranAyahActionBottomSheet Audio Action Integration (QA.4)', () {
    testWidgets('1. Renders "استماع" action button with Icons.play_circle_outline_rounded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestSheet());
      await tester.pumpAndSettle();

      expect(find.text('استماع'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
    });

    testWidgets('2. Tapping "استماع" triggers onPlayAudioTap callback', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      var playTapped = false;
      await tester.pumpWidget(buildTestSheet(
        onPlayAudioTap: () => playTapped = true,
      ));
      await tester.pumpAndSettle();

      final playButtonFinder = find.widgetWithText(InkWell, 'استماع');
      expect(playButtonFinder, findsOneWidget);

      await tester.tap(playButtonFinder);
      await tester.pump();

      expect(playTapped, isTrue);
    });

    testWidgets('3. Tapping "استماع" when callback is null does not throw', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestSheet(onPlayAudioTap: null));
      await tester.pumpAndSettle();

      final playButtonFinder = find.widgetWithText(InkWell, 'استماع');
      expect(playButtonFinder, findsOneWidget);

      await tester.tap(playButtonFinder);
      await tester.pump();
      // Completes cleanly without error
    });
  });
}
