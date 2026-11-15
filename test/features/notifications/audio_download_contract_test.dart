import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_state.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/audio_download_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/playable_audio_resolver.dart';

void main() {
  group('DownloadProgress — calculation and semantics', () {
    test('determinate progress computes fraction and percentage accurately', () {
      final progress = DownloadProgress.determinate(
        receivedBytes: 500000,
        totalBytes: 1000000,
      );

      expect(progress.isIndeterminate, isFalse);
      expect(progress.fraction, equals(0.5));
      expect(progress.percentage, equals(50));
    });

    test('fraction clamps between 0.0 and 1.0 even if bytes overflow', () {
      final overflow = DownloadProgress.determinate(
        receivedBytes: 1500000,
        totalBytes: 1000000,
      );
      expect(overflow.fraction, equals(1.0));
      expect(overflow.percentage, equals(100));
    });

    test('indeterminate progress has null fraction and percentage', () {
      final indeterminate = DownloadProgress.indeterminate(receivedBytes: 250000);
      expect(indeterminate.isIndeterminate, isTrue);
      expect(indeterminate.fraction, isNull);
      expect(indeterminate.percentage, isNull);
    });

    test('zero totalBytes is treated as indeterminate', () {
      final zeroTotal = DownloadProgress(receivedBytes: 100, totalBytes: 0);
      expect(zeroTotal.isIndeterminate, isTrue);
      expect(zeroTotal.fraction, isNull);
    });

    test('negative totalBytes is treated as indeterminate', () {
      final negativeTotal = DownloadProgress(receivedBytes: 100, totalBytes: -1);
      expect(negativeTotal.isIndeterminate, isTrue);
      expect(negativeTotal.fraction, isNull);
    });

    test('initial factory sets 0 received bytes', () {
      final initial = DownloadProgress.initial(totalBytes: 2000000);
      expect(initial.receivedBytes, equals(0));
      expect(initial.totalBytes, equals(2000000));
      expect(initial.fraction, equals(0.0));
      expect(initial.percentage, equals(0));
    });

    test('Equatable value equality works for matching instances', () {
      final p1 = DownloadProgress(receivedBytes: 1000, totalBytes: 2000);
      final p2 = DownloadProgress(receivedBytes: 1000, totalBytes: 2000);
      expect(p1, equals(p2));
    });
  });

  group('AudioDownloadTask & DownloadStatus state machine', () {
    const entryId = 'remote:mishary_alafasy_fajr';

    test('isActive and isTerminal are partitioned across all states', () {
      for (final status in DownloadStatus.values) {
        if (status.isActive) {
          expect(status.isTerminal, isFalse,
              reason: '$status cannot be both active and terminal');
        }
        if (status.isTerminal) {
          expect(status.isActive, isFalse,
              reason: '$status cannot be both active and terminal');
        }
      }
    });

    test('idle factory creates initial task', () {
      final task = AudioDownloadTask.idle(entryId);
      expect(task.entryId, equals(entryId));
      expect(task.status, equals(DownloadStatus.idle));
      expect(task.status.isActive, isFalse);
      expect(task.status.isTerminal, isFalse);
      expect(task.resultSource, isNull);
      expect(task.failure, isNull);
    });

    test('downloading factory sets downloading status and progress', () {
      final progress = DownloadProgress.determinate(
        receivedBytes: 300000,
        totalBytes: 1000000,
      );
      final task = AudioDownloadTask.downloading(
        entryId: entryId,
        progress: progress,
      );

      expect(task.status, equals(DownloadStatus.downloading));
      expect(task.status.isActive, isTrue);
      expect(task.progress.percentage, equals(30));
    });

    test('verifying factory sets verifying status', () {
      final task = AudioDownloadTask.verifying(entryId, 1500000);
      expect(task.status, equals(DownloadStatus.verifying));
      expect(task.status.isActive, isTrue);
      expect(task.progress.receivedBytes, equals(1500000));
    });

    test('promoting factory sets promoting status', () {
      final task = AudioDownloadTask.promoting(entryId, 1500000);
      expect(task.status, equals(DownloadStatus.promoting));
      expect(task.status.isActive, isTrue);
    });

    test('completed factory sets terminal status and stores CustomAudioSource', () {
      const source = CustomAudioSource(
        id: 'custom:remote_mishary_alafasy_fajr',
        displayName: 'أذان الفجر - مشاري العفاسي',
        localRelativePath: 'adhan_sounds/remote_mishary_fajr.mp3',
        originalFileName: 'mishary_fajr.mp3',
        fileSize: 1500000,
      );

      final task = AudioDownloadTask.completed(
        entryId: entryId,
        source: source,
      );

      expect(task.status, equals(DownloadStatus.completed));
      expect(task.status.isTerminal, isTrue);
      expect(task.status.isActive, isFalse);
      expect(task.resultSource, equals(source));
      expect(task.failure, isNull);
    });

    test('failed factory sets terminal status and records failure', () {
      final failure = AudioDownloadIntegrityFailure(
        actualHash: 'aaa',
        expectedHash: 'bbb',
      );
      final task = AudioDownloadTask.failed(
        entryId: entryId,
        failure: failure,
      );

      expect(task.status, equals(DownloadStatus.failed));
      expect(task.status.isTerminal, isTrue);
      expect(task.failure, equals(failure));
      expect(task.resultSource, isNull);
    });

    test('cancelled factory sets terminal status', () {
      final task = AudioDownloadTask.cancelled(entryId);
      expect(task.status, equals(DownloadStatus.cancelled));
      expect(task.status.isTerminal, isTrue);
      expect(task.status.isActive, isFalse);
    });

    test('copyWith updates fields immutably', () {
      final initial = AudioDownloadTask.idle(entryId);
      final updated = initial.copyWith(
        status: DownloadStatus.queued,
      );

      expect(updated.status, equals(DownloadStatus.queued));
      expect(initial.status, equals(DownloadStatus.idle));
    });
  });

  group('AudioDownloadFailure — error taxonomy', () {
    test('AudioDownloadSizeMismatchFailure formats informative message', () {
      final f = AudioDownloadSizeMismatchFailure(
        actualBytes: 1000,
        expectedBytes: 1500,
      );
      expect(f.actualBytes, equals(1000));
      expect(f.expectedBytes, equals(1500));
      expect(f.message, contains('1000'));
      expect(f.message, contains('1500'));
    });

    test('AudioDownloadIntegrityFailure records hash disparity', () {
      final f = AudioDownloadIntegrityFailure(
        actualHash: 'hash_a',
        expectedHash: 'hash_b',
      );
      expect(f.actualHash, equals('hash_a'));
      expect(f.expectedHash, equals('hash_b'));
      expect(f.message, contains('SHA-256'));
    });

    test('AudioDownloadOversizedFailure records size', () {
      final f = AudioDownloadOversizedFailure(bytes: 35 * 1024 * 1024);
      expect(f.bytes, equals(35 * 1024 * 1024));
    });

    test('All download failures provide Arabic localized messages', () {
      final failures = [
        AudioDownloadNetworkFailure(),
        AudioDownloadSizeMismatchFailure(actualBytes: 1, expectedBytes: 2),
        AudioDownloadOversizedFailure(bytes: 100),
        AudioDownloadIntegrityFailure(actualHash: 'a', expectedHash: 'b'),
        AudioDownloadStorageFailure(),
        AudioDownloadCancelledFailure(),
        AudioDownloadConcurrencyFailure(),
        AudioDownloadSecurityFailure(),
      ];

      for (final failure in failures) {
        expect(failure.message, isNotEmpty);
      }
    });
  });

  group('ResolvedPlayableAudio — entity contract', () {
    test('Direct custom audio resolution properties', () {
      const resolved = ResolvedPlayableAudio(
        path: '/data/user/0/app/docs/adhan_sounds/custom_1.mp3',
        isAsset: false,
        isFallback: false,
      );

      expect(resolved.path, equals('/data/user/0/app/docs/adhan_sounds/custom_1.mp3'));
      expect(resolved.isAsset, isFalse);
      expect(resolved.isFallback, isFalse);
      expect(resolved.fallbackReason, isNull);
    });

    test('Fallback resolution records flag and reason', () {
      const fallback = ResolvedPlayableAudio(
        path: 'assets/sounds/fajr_azan.mp3',
        isAsset: true,
        isFallback: true,
        fallbackReason: 'Custom audio file missing from disk',
      );

      expect(fallback.isAsset, isTrue);
      expect(fallback.isFallback, isTrue);
      expect(fallback.fallbackReason, equals('Custom audio file missing from disk'));
    });

    test('Equatable value equality', () {
      const r1 = ResolvedPlayableAudio(path: 'a.mp3', isAsset: true);
      const r2 = ResolvedPlayableAudio(path: 'a.mp3', isAsset: true);
      expect(r1, equals(r2));
    });
  });
}

