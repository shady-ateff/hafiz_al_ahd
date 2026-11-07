import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/errors/exception.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/quran/data/datasources/quran_tafseer_local_data_source.dart';
import 'package:hafiz_al_ahd/features/quran/data/repositories/quran_tafseer_repository_impl.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_tafseer.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_tafseer_use_case.dart';

class FakeQuranTafseerLocalDataSource implements BaseQuranTafseerLocalDataSource {
  final Map<String, String> data;
  bool shouldThrowGeneric = false;

  FakeQuranTafseerLocalDataSource(this.data);

  @override
  bool get isLoaded => true;

  @override
  Future<String> getTafseerText(AyahId ayahId) async {
    if (shouldThrowGeneric) {
      throw Exception('Simulated I/O failure');
    }
    final text = data[ayahId.formatted];
    if (text == null) {
      throw CacheException();
    }
    return text;
  }
}

void main() {
  group('QuranTafseerRepositoryImpl & UseCase Unit Tests', () {
    late FakeQuranTafseerLocalDataSource fakeDataSource;
    late QuranTafseerRepositoryImpl repository;
    late GetQuranTafseerUseCase useCase;

    final testAyah11 = AyahId(surahNumber: 1, ayahNumber: 1);
    final testAyah12 = AyahId(surahNumber: 1, ayahNumber: 2);
    final nonExistentAyah = AyahId(surahNumber: 99, ayahNumber: 99);

    const rawAyah11 =
        "[1] أبتدئ قراءة القرآن باسم الله مستعيناً به، <span class='aya'>ﵡ ٱللَّهِﵠ</span> علم على الرب.";
    const rawAyah12 =
        "[2] الثناء على الله بصفاته التي كلُّها أوصاف كمال.";

    setUp(() {
      fakeDataSource = FakeQuranTafseerLocalDataSource({
        '1:1': rawAyah11,
        '1:2': rawAyah12,
      });
      repository = QuranTafseerRepositoryImpl(localDataSource: fakeDataSource);
      useCase = GetQuranTafseerUseCase(repository);
    });

    test('1. Successfully returns Right(QuranTafseer) with parsed segments', () async {
      final result = await repository.getTafseer(testAyah11);

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right but got Left: $failure'),
        (tafseer) {
          expect(tafseer.ayahId, equals(testAyah11));
          expect(tafseer.rawText, equals(rawAyah11));
          expect(tafseer.sourceName, equals('التفسير الميسر'));
          expect(tafseer.segments.length, equals(3));
          expect(tafseer.segments[0].type, equals(TafseerSegmentType.commentary));
          expect(tafseer.segments[1].type, equals(TafseerSegmentType.quranQuote));
          expect(tafseer.segments[1].text, equals('ﵡ ٱللَّهِﵠ'));
          expect(tafseer.segments[2].type, equals(TafseerSegmentType.commentary));
        },
      );
    });

    test('2. Missing Ayah returns Left(CacheFailure)', () async {
      final result = await repository.getTafseer(nonExistentAyah);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<CacheFailure>());
          expect(failure.message, contains('Tafseer not found for Ayah 99:99'));
        },
        (tafseer) => fail('Expected Left but got Right: $tafseer'),
      );
    });

    test('3. Data source exception returns Left(CacheFailure)', () async {
      fakeDataSource.shouldThrowGeneric = true;

      final result = await repository.getTafseer(testAyah11);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<CacheFailure>());
          expect(failure.message, contains('Failed to retrieve Tafseer'));
        },
        (tafseer) => fail('Expected Left but got Right: $tafseer'),
      );
    });

    test('4. GetQuranTafseerUseCase delegates directly to repository', () async {
      final result = await useCase(testAyah12);

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Expected Right'),
        (tafseer) {
          expect(tafseer.ayahId, equals(testAyah12));
          expect(tafseer.rawText, equals(rawAyah12));
          expect(tafseer.segments.length, equals(1));
          expect(tafseer.segments.first.type, equals(TafseerSegmentType.commentary));
        },
      );
    });
  });
}

