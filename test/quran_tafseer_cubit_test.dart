import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/ayah_id.dart';
import 'package:hafiz_al_ahd/features/quran/domain/entities/quran_tafseer.dart';
import 'package:hafiz_al_ahd/features/quran/domain/repositories/quran_tafseer_repository.dart';
import 'package:hafiz_al_ahd/features/quran/domain/usecases/get_quran_tafseer_use_case.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_tafseer_cubit.dart';
import 'package:hafiz_al_ahd/features/quran/presentation/cubit/quran_tafseer_state.dart';

/// Test repository that uses controllable [Completer]s for deterministic concurrency testing.
class CompleterTafseerRepository implements QuranTafseerRepository {
  final Map<AyahId, Completer<Either<Failure, QuranTafseer>>> _completers = {};

  void prepareCompleter(AyahId ayahId) {
    _completers[ayahId] = Completer<Either<Failure, QuranTafseer>>();
  }

  void completeSuccess(AyahId ayahId, QuranTafseer tafseer) {
    _completers[ayahId]?.complete(Right(tafseer));
  }

  void completeFailure(AyahId ayahId, Failure failure) {
    _completers[ayahId]?.complete(Left(failure));
  }

  @override
  Future<Either<Failure, QuranTafseer>> getTafseer(AyahId ayahId) {
    final completer = _completers[ayahId];
    if (completer == null) {
      throw StateError('No completer prepared for Ayah ${ayahId.formatted}');
    }
    return completer.future;
  }
}

void main() {
  group('QuranTafseerCubit Tests (Phase 4A)', () {
    late CompleterTafseerRepository repository;
    late GetQuranTafseerUseCase useCase;
    late QuranTafseerCubit cubit;

    final ayahA = AyahId(surahNumber: 1, ayahNumber: 1);
    final ayahB = AyahId(surahNumber: 1, ayahNumber: 2);

    final tafseerA = QuranTafseer(
      ayahId: ayahA,
      rawText: 'تفسير الآية الأولى',
      segments: const [
        TafseerSegment(
          text: 'تفسير الآية الأولى',
          type: TafseerSegmentType.commentary,
        ),
      ],
    );

    final tafseerB = QuranTafseer(
      ayahId: ayahB,
      rawText: 'تفسير الآية الثانية',
      segments: const [
        TafseerSegment(
          text: 'تفسير الآية الثانية',
          type: TafseerSegmentType.commentary,
        ),
      ],
    );

    setUp(() {
      repository = CompleterTafseerRepository();
      useCase = GetQuranTafseerUseCase(repository);
      cubit = QuranTafseerCubit(getQuranTafseerUseCase: useCase);
    });

    tearDown(() async {
      await cubit.close();
    });

    test('1. Initial state is QuranTafseerInitial', () {
      expect(cubit.state, equals(const QuranTafseerInitial()));
    });

    test(
      '2. Loading -> Success flow emits QuranTafseerLoading then QuranTafseerLoaded',
      () async {
        repository.prepareCompleter(ayahA);

        final states = <QuranTafseerState>[];
        final subscription = cubit.stream.listen(states.add);

        // Start request
        final future = cubit.loadTafseer(ayahA);
        expect(cubit.state, equals(QuranTafseerLoading(ayahA)));

        // Complete request
        repository.completeSuccess(ayahA, tafseerA);
        await future;
        await pumpEventQueue();

        expect(cubit.state, equals(QuranTafseerLoaded(tafseerA)));
        expect(
          states,
          equals([QuranTafseerLoading(ayahA), QuranTafseerLoaded(tafseerA)]),
        );

        await subscription.cancel();
      },
    );

    test(
      '3. Loading -> Error flow emits QuranTafseerLoading then QuranTafseerError',
      () async {
        repository.prepareCompleter(ayahA);

        final states = <QuranTafseerState>[];
        final subscription = cubit.stream.listen(states.add);

        final future = cubit.loadTafseer(ayahA);
        expect(cubit.state, equals(QuranTafseerLoading(ayahA)));

        repository.completeFailure(
          ayahA,
          CacheFailure(message: 'Dataset corrupted'),
        );
        await future;
        await pumpEventQueue();

        expect(
          cubit.state,
          equals(QuranTafseerError(ayahId: ayahA, message: 'Dataset corrupted')),
        );
        expect(
          states,
          equals([
            QuranTafseerLoading(ayahA),
            QuranTafseerError(ayahId: ayahA, message: 'Dataset corrupted'),
          ]),
        );

        await subscription.cancel();
      },
    );

    test('4. Sequential requests both transition cleanly', () async {
      // First request
      repository.prepareCompleter(ayahA);
      final futureA = cubit.loadTafseer(ayahA);
      repository.completeSuccess(ayahA, tafseerA);
      await futureA;
      await pumpEventQueue();
      expect(cubit.state, equals(QuranTafseerLoaded(tafseerA)));

      // Second request
      repository.prepareCompleter(ayahB);
      final futureB = cubit.loadTafseer(ayahB);
      expect(cubit.state, equals(QuranTafseerLoading(ayahB)));
      repository.completeSuccess(ayahB, tafseerB);
      await futureB;
      await pumpEventQueue();
      expect(cubit.state, equals(QuranTafseerLoaded(tafseerB)));
    });

    test(
      '5. Latest-request-wins: Newer request B completes before older request A',
      () async {
        repository.prepareCompleter(ayahA);
        repository.prepareCompleter(ayahB);

        final states = <QuranTafseerState>[];
        final subscription = cubit.stream.listen(states.add);

        // 1. Dispatch A
        final futureA = cubit.loadTafseer(ayahA);
        expect(cubit.state, equals(QuranTafseerLoading(ayahA)));

        // 2. Dispatch B before A finishes
        final futureB = cubit.loadTafseer(ayahB);
        expect(cubit.state, equals(QuranTafseerLoading(ayahB)));

        // 3. B completes first
        repository.completeSuccess(ayahB, tafseerB);
        await futureB;
        await pumpEventQueue();
        expect(cubit.state, equals(QuranTafseerLoaded(tafseerB)));

        // 4. A completes later -> MUST be discarded
        repository.completeSuccess(ayahA, tafseerA);
        await futureA;
        await pumpEventQueue();

        // Assert B is still the active state, A never overwrote B
        expect(cubit.state, equals(QuranTafseerLoaded(tafseerB)));
        expect(
          states,
          equals([
            QuranTafseerLoading(ayahA),
            QuranTafseerLoading(ayahB),
            QuranTafseerLoaded(tafseerB),
          ]),
        );

        await subscription.cancel();
      },
    );

    test(
      '6. Latest-request-wins: Older request A completes before newer request B, but is discarded',
      () async {
        repository.prepareCompleter(ayahA);
        repository.prepareCompleter(ayahB);

        final states = <QuranTafseerState>[];
        final subscription = cubit.stream.listen(states.add);

        // 1. Dispatch A
        final futureA = cubit.loadTafseer(ayahA);

        // 2. Dispatch B before A finishes
        final futureB = cubit.loadTafseer(ayahB);
        expect(cubit.state, equals(QuranTafseerLoading(ayahB)));

        // 3. A completes while B is in flight -> MUST be discarded
        repository.completeSuccess(ayahA, tafseerA);
        await futureA;
        await pumpEventQueue();

        // State remains Loading(B)
        expect(cubit.state, equals(QuranTafseerLoading(ayahB)));

        // 4. B completes -> Emits Loaded(B)
        repository.completeSuccess(ayahB, tafseerB);
        await futureB;
        await pumpEventQueue();

        expect(cubit.state, equals(QuranTafseerLoaded(tafseerB)));
        expect(
          states,
          equals([
            QuranTafseerLoading(ayahA),
            QuranTafseerLoading(ayahB),
            QuranTafseerLoaded(tafseerB),
          ]),
        );

        await subscription.cancel();
      },
    );

    test(
      '7. Closure safety: Pending request completing after close() does not emit or throw',
      () async {
        repository.prepareCompleter(ayahA);

        final states = <QuranTafseerState>[];
        final subscription = cubit.stream.listen(states.add);

        final futureA = cubit.loadTafseer(ayahA);
        expect(cubit.state, equals(QuranTafseerLoading(ayahA)));

        // Close cubit while request is pending
        await cubit.close();
        expect(cubit.isClosed, isTrue);

        // Complete request after close
        repository.completeSuccess(ayahA, tafseerA);
        await futureA;
        await pumpEventQueue();

        // No post-close emission
        expect(states, equals([QuranTafseerLoading(ayahA)]));

        await subscription.cancel();
      },
    );

    test('8. Reset invalidates in-flight request and returns to initial state', () async {
      repository.prepareCompleter(ayahA);

      final futureA = cubit.loadTafseer(ayahA);
      expect(cubit.state, equals(QuranTafseerLoading(ayahA)));

      cubit.reset();
      expect(cubit.state, equals(const QuranTafseerInitial()));

      // A completes after reset -> discarded
      repository.completeSuccess(ayahA, tafseerA);
      await futureA;
      await pumpEventQueue();

      expect(cubit.state, equals(const QuranTafseerInitial()));
    });
  });
}
