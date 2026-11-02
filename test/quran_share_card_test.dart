import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_segment.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_ayah.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/widgets/quran_ayah_share_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranAyah shortAyah;
  late QuranAyah mediumAyah;
  late QuranAyah longAyah;

  setUpAll(() async {
    ByteData byteData;
    try {
      byteData = await rootBundle.load('assets/fonts/amiri.ttf');
    } catch (_) {
      final file = File('assets/fonts/amiri.ttf');
      final bytes = await file.readAsBytes();
      byteData = ByteData.sublistView(bytes);
    }
    final fontLoaderAmiri = FontLoader('Amiri')
      ..addFont(Future.value(byteData));
    await fontLoaderAmiri.load();

    final fontLoaderTajawal = FontLoader('Tajawal')
      ..addFont(Future.value(byteData));
    await fontLoaderTajawal.load();

    ByteData bsmlData;
    try {
      bsmlData = await rootBundle.load('assets/fonts/QCF2BSML.ttf');
    } catch (_) {
      final file = File('assets/fonts/QCF2BSML.ttf');
      final bytes = await file.readAsBytes();
      bsmlData = ByteData.sublistView(bytes);
    }
    final fontLoaderBsml = FontLoader('QCF_BSML')
      ..addFont(Future.value(bsmlData));
    await fontLoaderBsml.load();
  });

  setUp(() {
    shortAyah = QuranAyah(
      id: AyahId(surahNumber: 112, ayahNumber: 1),
      pageNumber: 604,
      endPageNumber: 604,
      uthmaniText: 'قُلْ هُوَ ٱللَّهُ أَحَدٌ',
      wordsCount: 4,
      segments: [
        AyahSegment(
          ayahId: AyahId(surahNumber: 112, ayahNumber: 1),
          pageNumber: 604,
          lineNumber: 4,
          wordStart: 0,
          wordEnd: 3,
          qcfText: 'ﭑ ﭒ ﭓ ﭔ',
        ),
      ],
    );

    mediumAyah = QuranAyah(
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

    longAyah = QuranAyah(
      id: AyahId(surahNumber: 2, ayahNumber: 255),
      pageNumber: 42,
      endPageNumber: 42,
      uthmaniText:
          'ٱللَّهُ لَآ إِلَـٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ لَا تَأْخُذُهُۥ سِنَةٌ وَلَا نَوْمٌ ۚ لَّهُۥ مَا فِى ٱلسَّمَـٰوَٰتِ وَمَا فِى ٱلْأَرْضِ ۗ مَن ذَا ٱلَّذِى يَشْفَعُ عِندَهُۥٓ إِلَّا بِإِذْنِهِۦ ۚ يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ ۖ وَلَا يُحِيطُونَ بِشَىْءٍ مِّنْ عِلْمِهِۦٓ إِلَّا بِمَا شَآءَ ۚ وَسِعَ كُرْسِيُّهُ ٱلسَّمَـٰوَٰتِ وَٱلْأَرْضَ ۖ وَلَا يَـُٔودُهُۥ حِفْظُهُمَا ۚ وَهُوَ ٱلْعَلِىُّ ٱلْعَظِيمُ',
      wordsCount: 50,
      segments: [
        AyahSegment(
          ayahId: AyahId(surahNumber: 2, ayahNumber: 255),
          pageNumber: 42,
          lineNumber: 1,
          wordStart: 0,
          wordEnd: 49,
          qcfText: 'ﭐ ﭒ ﭓ ﭔ',
        ),
      ],
    );
  });

  group('Phase 2.6.3.3 — QuranAyahShareCard Rendering & Visual Parity Tests', () {
    testWidgets('1. Card renders logo, Surah info, Ayah text, and attribution correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: QuranAyahShareCard(
                ayah: shortAyah,
                width: 540,
                height: 675,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Surah Name and Ayah Number
      expect(find.textContaining('سورة الإخلاص'), findsWidgets);
      expect(find.textContaining('الآية 1'), findsOneWidget);
      expect(find.textContaining('صفحة 604'), findsOneWidget);

      // Verify exact Uthmani text with Ayah end symbol
      expect(find.text('${shortAyah.uthmaniText} ۝١'), findsOneWidget);

      // Verify App attribution
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data?.replaceAll('ـ', '').contains('حافظ العهد') ?? false),
        ),
        findsOneWidget,
      );

      // Verify App Logo
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('2. Long Ayah wraps gracefully without layout overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: QuranAyahShareCard(
                ayah: longAyah,
                width: 540,
                height: 675,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // No RenderFlex overflow assertion should have occurred
      expect(tester.takeException(), isNull);

      // Verify complete long Ayah text is rendered
      expect(find.text('${longAyah.uthmaniText} ۝٢٥٥'), findsOneWidget);
      expect(find.textContaining('سورة البقرة'), findsOneWidget);
      expect(find.textContaining('الآية 255'), findsOneWidget);
    });

    testWidgets('3. RepaintBoundary captures exact 1080×1350 PNG dimensions', (tester) async {
      tester.view.physicalSize = const Size(1080, 1350);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final cardKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 540,
                height: 675,
                child: RepaintBoundary(
                  key: cardKey,
                  child: QuranAyahShareCard(ayah: mediumAyah, height: 675),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final boundary = cardKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      expect(boundary.size.width, equals(540));
      expect(boundary.size.height, equals(675));

      // Scaling by 2.0 produces exactly 1080 × 1350
      Uint8List? bytes;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2.0);
        expect(image.width, equals(1080));
        expect(image.height, equals(1350));

        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(byteData, isNotNull);
        bytes = byteData!.buffer.asUint8List();
      });

      expect(bytes, isNotNull);
      // Verify PNG header magic bytes (0x89, 'P', 'N', 'G')
      expect(bytes![0], equals(0x89));
      expect(bytes![1], equals(0x50));
      expect(bytes![2], equals(0x4E));
      expect(bytes![3], equals(0x47));
    });

    testWidgets('4. Visual Evidence Generation: Renders & saves real PNG previews (Short, Medium, Long Ayahs)', (tester) async {
      tester.view.physicalSize = const Size(1080, 1350);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final artifactDir = Directory(
        r'C:\Users\shady atef\.gemini\antigravity\brain\f256f378-bbd2-4ef4-8714-655871d460ed',
      );

      Future<void> captureAndSave(
        QuranAyah ayah,
        String filename, {
        bool isDarkMode = true,
      }) async {
        final cardKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Amiri'),
            home: Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(
                child: RepaintBoundary(
                  key: cardKey,
                  child: QuranAyahShareCard(
                    ayah: ayah,
                    width: 1080,
                    isDarkMode: isDarkMode,
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final boundary = cardKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;

        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          final bytes = byteData!.buffer.asUint8List();

          final outFile = File('${artifactDir.path}/$filename');
          await outFile.writeAsBytes(bytes);
          debugPrint('Saved visual preview: ${outFile.path} (${bytes.length} bytes, dimensions: ${image.width}x${image.height})');
        });
      }

      // Generate Short Ayah Preview (Al-Ikhlas: 1) - Night Theme, Fit Height
      await captureAndSave(shortAyah, 'share_card_short.png', isDarkMode: true);

      // Generate Medium Ayah Preview (Al-Fatiha: 1) - Day Theme, Fit Height
      await captureAndSave(mediumAyah, 'share_card_medium.png', isDarkMode: false);

      // Generate Long Ayah Preview (Ayat Al-Kursi, Al-Baqarah: 255) - Night Theme, Fit Height
      await captureAndSave(longAyah, 'share_card_long.png', isDarkMode: true);
    });

    testWidgets('5. Card dynamically adapts palette for Day (Light) and Night (Dark) themes', (tester) async {
      tester.view.physicalSize = const Size(1080, 1350);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 1. Day Mode (Light)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: QuranAyahShareCard(
                ayah: shortAyah,
                isDarkMode: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('${shortAyah.uthmaniText} ۝١'), findsOneWidget);

      // 2. Night Mode (Dark)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: QuranAyahShareCard(
                ayah: shortAyah,
                isDarkMode: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('${shortAyah.uthmaniText} ۝١'), findsOneWidget);
    });

    testWidgets('6. Card renders QCF text when useQcf is true and Amiri text as backup when false', (tester) async {
      tester.view.physicalSize = const Size(1080, 1350);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 1. QCF Enabled
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: QuranAyahShareCard(
                ayah: shortAyah,
                useQcf: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final qcfExpected = shortAyah.segments.map((s) => s.qcfText).join(' ');
      expect(find.text(qcfExpected), findsOneWidget);

      // 2. Backup Mode (Amiri Uthmani Text)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: QuranAyahShareCard(
                ayah: shortAyah,
                useQcf: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('${shortAyah.uthmaniText} ۝١'), findsOneWidget);
    });
  });
}

