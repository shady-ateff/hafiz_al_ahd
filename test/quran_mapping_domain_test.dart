import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_mapping_entities.dart';

void main() {
  group('AyahId Unit Tests', () {
    test('Value equality works correctly', () {
      final id1 = AyahId(surahNumber: 2, ayahNumber: 255);
      final id2 = AyahId(surahNumber: 2, ayahNumber: 255);
      final id3 = AyahId(surahNumber: 2, ayahNumber: 256);
      final id4 = AyahId(surahNumber: 3, ayahNumber: 255);

      expect(id1, equals(id2));
      expect(id1.hashCode, equals(id2.hashCode));
      expect(id1, isNot(equals(id3)));
      expect(id1, isNot(equals(id4)));
    });

    test('String formatting and parsing', () {
      final id = AyahId(surahNumber: 114, ayahNumber: 6);
      expect(id.formatted, equals('114:6'));
      expect(id.toString(), equals('114:6'));

      final parsed = AyahId.fromString('114:6');
      expect(parsed, equals(id));
      expect(parsed.surahNumber, equals(114));
      expect(parsed.ayahNumber, equals(6));
    });

    test('Throws ArgumentError on invalid constructor arguments', () {
      expect(() => AyahId(surahNumber: 0, ayahNumber: 1), throwsArgumentError);
      expect(() => AyahId(surahNumber: 115, ayahNumber: 1), throwsArgumentError);
      expect(() => AyahId(surahNumber: 1, ayahNumber: 0), throwsArgumentError);
      expect(() => AyahId(surahNumber: 1, ayahNumber: -1), throwsArgumentError);
    });

    test('Throws ArgumentError on malformed strings', () {
      expect(() => AyahId.fromString(''), throwsArgumentError);
      expect(() => AyahId.fromString('2'), throwsArgumentError);
      expect(() => AyahId.fromString('2:255:1'), throwsArgumentError);
      expect(() => AyahId.fromString('abc:def'), throwsArgumentError);
    });
  });

  group('WordLocation Unit Tests', () {
    test('Value equality works correctly', () {
      final loc1 = WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 2);
      final loc2 = WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 2);
      final loc3 = WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 3);

      expect(loc1, equals(loc2));
      expect(loc1.hashCode, equals(loc2.hashCode));
      expect(loc1, isNot(equals(loc3)));
    });

    test('Factories and parent AyahId getter', () {
      final ayahId = AyahId(surahNumber: 18, ayahNumber: 10);
      final loc = WordLocation.fromAyahId(ayahId: ayahId, wordIndex: 5);

      expect(loc.surahNumber, equals(18));
      expect(loc.ayahNumber, equals(10));
      expect(loc.wordIndex, equals(5));
      expect(loc.ayahId, equals(ayahId));
      expect(loc.formatted, equals('18:10:5'));
      expect(loc.toString(), equals('18:10:5'));

      final parsed = WordLocation.fromString('18:10:5');
      expect(parsed, equals(loc));
    });

    test('Throws ArgumentError on invalid constructor arguments and malformed strings', () {
      expect(() => WordLocation(surahNumber: 0, ayahNumber: 1, wordIndex: 1), throwsArgumentError);
      expect(() => WordLocation(surahNumber: 1, ayahNumber: 0, wordIndex: 1), throwsArgumentError);
      expect(() => WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 0), throwsArgumentError);
      expect(() => WordLocation.fromString('1:1'), throwsArgumentError);
      expect(() => WordLocation.fromString('1:1:foo'), throwsArgumentError);
    });
  });

  group('QuranWord Unit Tests', () {
    test('Correctly exposes location properties and value equality', () {
      final loc = WordLocation(surahNumber: 112, ayahNumber: 1, wordIndex: 1);
      final word1 = QuranWord(
        location: loc,
        uthmaniText: 'قُلْ',
        qcfText: 'ﱁ',
      );
      final word2 = QuranWord(
        location: loc,
        uthmaniText: 'قُلْ',
        qcfText: 'ﱁ',
      );
      final word3 = QuranWord(
        location: loc,
        uthmaniText: 'هُوَ',
        qcfText: 'ﱂ',
      );

      expect(word1, equals(word2));
      expect(word1.hashCode, equals(word2.hashCode));
      expect(word1, isNot(equals(word3)));

      expect(word1.ayahId, equals(AyahId(surahNumber: 112, ayahNumber: 1)));
      expect(word1.surahNumber, equals(112));
      expect(word1.ayahNumber, equals(1));
      expect(word1.wordIndex, equals(1));
    });

    test('Throws ArgumentError on empty text strings', () {
      final loc = WordLocation(surahNumber: 1, ayahNumber: 1, wordIndex: 1);
      expect(
        () => QuranWord(location: loc, uthmaniText: '', qcfText: 'ﱁ'),
        throwsArgumentError,
      );
      expect(
        () => QuranWord(location: loc, uthmaniText: 'بِسْمِ', qcfText: ''),
        throwsArgumentError,
      );
    });
  });

  group('AyahSegment Unit Tests', () {
    test('Calculates wordCount correctly and supports equality', () {
      final ayahId = AyahId(surahNumber: 2, ayahNumber: 282);
      final seg1 = AyahSegment(
        ayahId: ayahId,
        pageNumber: 48,
        lineNumber: 1,
        wordStart: 0,
        wordEnd: 8,
        qcfText: 'ﮪ ﮫ ﮬ ﮭ ﮮ ﮯ ﮰ ﮱ ﯓ',
      );
      final seg2 = AyahSegment(
        ayahId: ayahId,
        pageNumber: 48,
        lineNumber: 1,
        wordStart: 0,
        wordEnd: 8,
        qcfText: 'ﮪ ﮫ ﮬ ﮭ ﮮ ﮯ ﮰ ﮱ ﯓ',
      );

      expect(seg1, equals(seg2));
      expect(seg1.wordCount, equals(9)); // 8 - 0 + 1 = 9 words
      expect(seg1.surahNumber, equals(2));
      expect(seg1.ayahNumber, equals(282));
    });

    test('Throws ArgumentError on invalid boundary constraints', () {
      final ayahId = AyahId(surahNumber: 1, ayahNumber: 1);
      // wordEnd < wordStart
      expect(
        () => AyahSegment(
          ayahId: ayahId,
          pageNumber: 1,
          lineNumber: 2,
          wordStart: 5,
          wordEnd: 4,
          qcfText: 'test',
        ),
        throwsArgumentError,
      );

      // wordStart < 0
      expect(
        () => AyahSegment(
          ayahId: ayahId,
          pageNumber: 1,
          lineNumber: 2,
          wordStart: -1,
          wordEnd: 2,
          qcfText: 'test',
        ),
        throwsArgumentError,
      );

      // pageNumber out of range
      expect(
        () => AyahSegment(
          ayahId: ayahId,
          pageNumber: 605,
          lineNumber: 1,
          wordStart: 0,
          wordEnd: 1,
          qcfText: 'test',
        ),
        throwsArgumentError,
      );

      // lineNumber out of range
      expect(
        () => AyahSegment(
          ayahId: ayahId,
          pageNumber: 1,
          lineNumber: 16,
          wordStart: 0,
          wordEnd: 1,
          qcfText: 'test',
        ),
        throwsArgumentError,
      );
    });
  });

  group('QuranLineMapping Unit Tests', () {
    final wordA1 = QuranWord(
      location: WordLocation(surahNumber: 112, ayahNumber: 1, wordIndex: 1),
      uthmaniText: 'قُلْ',
      qcfText: 'ﱁ',
    );
    final wordA2 = QuranWord(
      location: WordLocation(surahNumber: 112, ayahNumber: 1, wordIndex: 2),
      uthmaniText: 'هُوَ',
      qcfText: 'ﱂ',
    );
    final wordB1 = QuranWord(
      location: WordLocation(surahNumber: 112, ayahNumber: 2, wordIndex: 1),
      uthmaniText: 'ٱللَّهُ',
      qcfText: 'ﱃ',
    );

    test('Orders words and reconstructs full line text', () {
      final lineMapping = QuranLineMapping(
        pageNumber: 604,
        lineNumber: 3,
        words: [wordA1, wordA2, wordB1],
      );

      expect(lineMapping.wordCount, equals(3));
      expect(lineMapping.reconstructedQcfText, equals('ﱁ ﱂ ﱃ'));
      expect(
        lineMapping.ayahIds,
        equals({
          AyahId(surahNumber: 112, ayahNumber: 1),
          AyahId(surahNumber: 112, ayahNumber: 2),
        }),
      );
      expect(lineMapping.containsAyah(AyahId(surahNumber: 112, ayahNumber: 1)), isTrue);
      expect(lineMapping.containsAyah(AyahId(surahNumber: 112, ayahNumber: 2)), isTrue);
      expect(lineMapping.containsAyah(AyahId(surahNumber: 112, ayahNumber: 3)), isFalse);
    });

    test('Enforces immutable list of words and immutable set of ayahIds', () {
      final wordsList = [wordA1, wordA2];
      final lineMapping = QuranLineMapping(
        pageNumber: 1,
        lineNumber: 2,
        words: wordsList,
      );

      expect(() => (lineMapping.words as dynamic).add(wordB1), throwsUnsupportedError);
      expect(() => (lineMapping.ayahIds as dynamic).add(AyahId(surahNumber: 1, ayahNumber: 1)), throwsUnsupportedError);
    });

    test('Throws ArgumentError on empty word list or invalid bounds', () {
      expect(
        () => QuranLineMapping(pageNumber: 1, lineNumber: 1, words: []),
        throwsArgumentError,
      );
      expect(
        () => QuranLineMapping(pageNumber: 0, lineNumber: 1, words: [wordA1]),
        throwsArgumentError,
      );
      expect(
        () => QuranLineMapping(pageNumber: 1, lineNumber: 0, words: [wordA1]),
        throwsArgumentError,
      );
    });
  });

  group('QuranAyah Unit Tests', () {
    final ayahId = AyahId(surahNumber: 1, ayahNumber: 1);
    final seg = AyahSegment(
      ayahId: ayahId,
      pageNumber: 1,
      lineNumber: 2,
      wordStart: 0,
      wordEnd: 3,
      qcfText: 'ﱁ ﱂ ﱃ ﱄ ﱅ',
    );

    test('Represents single-line ayah correctly', () {
      final ayah = QuranAyah(
        id: ayahId,
        pageNumber: 1,
        endPageNumber: 1,
        uthmaniText: 'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
        wordsCount: 4,
        segments: [seg],
      );

      expect(ayah.isMultiLine, isFalse);
      expect(ayah.isMultiPage, isFalse);
      expect(ayah.surahNumber, equals(1));
      expect(ayah.ayahNumber, equals(1));
      expect(ayah.segments.length, equals(1));
    });

    test('Represents multi-line ayah correctly', () {
      final seg2 = AyahSegment(
        ayahId: ayahId,
        pageNumber: 1,
        lineNumber: 3,
        wordStart: 0,
        wordEnd: 2,
        qcfText: 'ﱆ ﱇ ﱈ',
      );
      final multiLineAyah = QuranAyah(
        id: ayahId,
        pageNumber: 1,
        endPageNumber: 1,
        uthmaniText: 'text',
        wordsCount: 7, // 4 + 3 = 7
        segments: [seg, seg2],
      );

      expect(multiLineAyah.isMultiLine, isTrue);
      expect(multiLineAyah.isMultiPage, isFalse);
    });

    test('Enforces immutability and valid bounds', () {
      final segments = [seg];
      final ayah = QuranAyah(
        id: ayahId,
        pageNumber: 1,
        endPageNumber: 1,
        uthmaniText: 'text',
        wordsCount: 4,
        segments: segments,
      );

      expect(() => (ayah.segments as dynamic).add(seg), throwsUnsupportedError);

      expect(
        () => QuranAyah(
          id: ayahId,
          pageNumber: 2,
          endPageNumber: 1, // endPage < pageNumber
          uthmaniText: 'text',
          wordsCount: 4,
          segments: [seg],
        ),
        throwsArgumentError,
      );

      expect(
        () => QuranAyah(
          id: ayahId,
          pageNumber: 1,
          endPageNumber: 1,
          uthmaniText: '', // empty text
          wordsCount: 4,
          segments: [seg],
        ),
        throwsArgumentError,
      );
    });

    test('Enforces strict consistency rules', () {
      // Rule 1: pageNumber must equal segments.first.pageNumber
      expect(
        () => QuranAyah(
          id: ayahId,
          pageNumber: 2,
          endPageNumber: 2,
          uthmaniText: 'text',
          wordsCount: 4,
          segments: [seg], // seg is on page 1
        ),
        throwsArgumentError,
      );

      // Rule 2: wordsCount must equal sum of segment words
      expect(
        () => QuranAyah(
          id: ayahId,
          pageNumber: 1,
          endPageNumber: 1,
          uthmaniText: 'text',
          wordsCount: 5, // actual is 4
          segments: [seg],
        ),
        throwsArgumentError,
      );

      // Rule 3: segments ordering
      final segA = AyahSegment(
        ayahId: ayahId,
        pageNumber: 1,
        lineNumber: 5,
        wordStart: 0,
        wordEnd: 1,
        qcfText: 'text',
      );
      final segB = AyahSegment(
        ayahId: ayahId,
        pageNumber: 1,
        lineNumber: 3,
        wordStart: 0,
        wordEnd: 1,
        qcfText: 'text',
      );
      expect(
        () => QuranAyah(
          id: ayahId,
          pageNumber: 1,
          endPageNumber: 1,
          uthmaniText: 'text',
          wordsCount: 4,
          segments: [segA, segB], // Line 5 followed by Line 3: unordered!
        ),
        throwsArgumentError,
      );
    });
  });
}
