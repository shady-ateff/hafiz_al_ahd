import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../domain/entities/audio_download.dart';
import '../../domain/entities/download_progress.dart';
import '../../domain/entities/download_recovery_action.dart';
import '../../domain/entities/download_resource_identity.dart';
import '../../domain/entities/single_surah_download_result.dart';
import '../../domain/services/base_quran_audio_download_coordinator.dart';
import '../datasources/quran_audio_local_data_source.dart';
import '../models/audio_download_model.dart';
import 'quran_audio_storage_service.dart';

/// Contract for managing single-Surah audio downloads with HTTP Range resumption,
/// RFC 9110 Strong Validator verification, and real-time telemetry.
abstract class BaseQuranAudioDownloadService {
  /// Initiates or resumes downloading an individual Surah audio track.
  Stream<DownloadProgress> downloadSurah({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
  });

  /// Pauses an active download, flushing transfer stream to disk and updating SQLite.
  Future<void> pauseDownload(int surahNumber, String reciterId);

  /// Cancels an in-flight download, stopping network stream and releasing resources.
  Future<void> cancelDownload(int surahNumber, String reciterId);

  /// Retries a failed or paused download from its existing staging offset or byte 0.
  Future<void> retryDownload({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
  });

  /// Returns current progress for a Surah if active/recorded, or null.
  DownloadProgress? getProgress(int surahNumber, String reciterId);

  /// Watches real-time progress updates for a specific Surah download.
  Stream<DownloadProgress> watchProgress(int surahNumber, String reciterId);

  /// Downloads a single Surah and awaits authoritative completion, returning a [SingleSurahDownloadResult].
  Future<SingleSurahDownloadResult> downloadSurahAndWait({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
    void Function(DownloadProgress progress)? onProgress,
    bool skipCoordinatorReservation = false,
  });

  /// Cleans up all active download streams and controllers on disposal.
  void dispose();
}

/// Active in-flight download context tracking network streams and cancellation flags.
class _ActiveDownloadTask {
  final http.Client client;
  StreamSubscription<List<int>>? subscription;
  IOSink? currentSink;
  Completer<void>? streamCompleter;
  int downloadedBytes = 0;
  int? totalBytes;
  bool isPaused = false;
  bool isCancelled = false;

  _ActiveDownloadTask({required this.client});

  Future<void> abort() async {
    try {
      await subscription?.cancel();
    } catch (_) {}
    if (streamCompleter != null && !streamCompleter!.isCompleted) {
      streamCompleter!.complete();
    }
    try {
      await currentSink?.flush();
      await currentSink?.close();
    } catch (_) {}
    client.close();
  }
}

/// Production implementation of [BaseQuranAudioDownloadService].
///
/// Implements:
/// - RFC 9110 §8.8.2.2 / §8.8.3 Strong Validator inspection and Range resumption.
/// - Representation invariance via mandatory `Accept-Encoding: identity`.
/// - HTTP 206 slice accounting from `Content-Range` denominator.
/// - Full-file SHA-256 verification and atomic promotion journal integration.
class QuranAudioDownloadService implements BaseQuranAudioDownloadService {
  final BaseQuranAudioLocalDataSource localDataSource;
  final QuranAudioStorageService storageService;
  final http.Client Function()? clientFactory;
  final BaseQuranAudioDownloadCoordinator? coordinator;

  final Map<String, StreamController<DownloadProgress>> _controllers = {};
  final Map<String, DownloadProgress> _latestProgress = {};
  final Map<String, _ActiveDownloadTask> _activeTasks = {};

  QuranAudioDownloadService({
    required this.localDataSource,
    required this.storageService,
    this.clientFactory,
    this.coordinator,
  });

  String _taskKey(int surahNumber, String reciterId) => '$reciterId:$surahNumber';

  StreamController<DownloadProgress> _getOrCreateController(String key) {
    var controller = _controllers[key];
    if (controller == null || controller.isClosed) {
      controller = StreamController<DownloadProgress>.broadcast();
      _controllers[key] = controller;
    }
    return controller;
  }

  void _emitProgress(DownloadProgress progress) {
    final key = _taskKey(progress.surahNumber, progress.reciterId);
    _latestProgress[key] = progress;
    final controller = _controllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(progress);
    }
  }

  @override
  DownloadProgress? getProgress(int surahNumber, String reciterId) {
    return _latestProgress[_taskKey(surahNumber, reciterId)];
  }

  @override
  Stream<DownloadProgress> watchProgress(int surahNumber, String reciterId) {
    final key = _taskKey(surahNumber, reciterId);
    return _getOrCreateController(key).stream;
  }

  @override
  Stream<DownloadProgress> downloadSurah({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
    bool skipCoordinatorReservation = false,
  }) {
    // 1. Argument validations
    if (surahNumber < 1 || surahNumber > 114) {
      throw ArgumentError.value(surahNumber, 'surahNumber', 'Surah number must be between 1 and 114');
    }
    if (reciterId.trim().isEmpty) {
      throw ArgumentError.value(reciterId, 'reciterId', 'Reciter ID cannot be empty');
    }
    if (audioUrl.trim().isEmpty) {
      throw ArgumentError.value(audioUrl, 'audioUrl', 'Audio URL cannot be empty');
    }

    final key = _taskKey(surahNumber, reciterId);

    // If download is already in flight, return its active stream
    if (_activeTasks.containsKey(key)) {
      return _getOrCreateController(key).stream;
    }

    final controller = _getOrCreateController(key);

    _executeDownloadPipeline(
      surahNumber: surahNumber,
      reciterId: reciterId,
      audioUrl: audioUrl,
      expectedTotalBytes: expectedTotalBytes,
      skipCoordinatorReservation: skipCoordinatorReservation,
    );

    return controller.stream;
  }

  /// Normalizes an audio URL by cleaning duplicate consecutive slashes in the path
  /// (e.g. `https://download.quranicaudio.com/quran/reciter//112.mp3` -> `.../112.mp3`).
  static String normalizeAudioUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      final cleanPath = uri.path.replaceAll(RegExp(r'/+'), '/');
      return uri.replace(path: cleanPath).toString();
    } catch (_) {
      return url.trim();
    }
  }

  Future<void> _executeDownloadPipeline({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
    bool skipCoordinatorReservation = false,
  }) async {
    final effectiveAudioUrl = normalizeAudioUrl(audioUrl);
    final key = _taskKey(surahNumber, reciterId);
    final client = clientFactory != null ? clientFactory!() : http.Client();
    final task = _ActiveDownloadTask(client: client);
    _activeTasks[key] = task;

    DownloadReservationTicket? reservationTicket;
    if (!skipCoordinatorReservation && coordinator != null) {
      try {
        reservationTicket = await coordinator!.reserveSingleSurah(
          surahNumber: surahNumber,
          reciterId: reciterId,
        );
      } catch (e) {
        _activeTasks.remove(key);
        client.close();
        _emitProgress(DownloadProgress(
          surahNumber: surahNumber,
          reciterId: reciterId,
          status: AudioDownloadStatus.failed,
          downloadedBytes: 0,
          lastError: e.toString(),
        ));
        return;
      }
    }

    IOSink? sink;
    File? stagingFile;

    try {
      // Step 1: Pre-flight & Recovery Check
      final storageDir = await storageService.getStorageDirectory();
      final stagingDir = await storageService.getStagingDirectory();
      final paddedSurah = surahNumber.toString().padLeft(3, '0');
      final cleanReciter = reciterId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final stagingFileName = 'dl_${cleanReciter}_$paddedSurah.tmp';
      stagingFile = File(p.join(stagingDir.path, stagingFileName));

      // Check destination file existence
      final destFile = await storageService.resolveSurahFile(surahNumber, reciterId);
      final destExists = await destFile.exists();
      final destLength = destExists ? await destFile.length() : null;

      final existingRecord = await localDataSource.getDownloadRecord(surahNumber, reciterId);
      final hasJournal = (await localDataSource.getPromotionJournal(surahNumber, reciterId)) != null;

      if (hasJournal) {
        await storageService.recoverPendingPromotionJournals(localDataSource);
      }

      if (existingRecord != null) {
        final recoveryAction = resolveRecoveryAction(
          dbRecord: existingRecord,
          stagingFileExists: await stagingFile.exists(),
          stagingPhysicalLength: await stagingFile.exists() ? await stagingFile.length() : null,
          hasStrongValidator: existingRecord.etag != null || existingRecord.lastModified != null,
          hasPendingJournal: false,
          resourceIdentityMatches: true,
          destinationFileExists: destExists,
          destinationPhysicalLength: destLength,
        );

        if (recoveryAction == StartupRecoveryResult.alreadyCompleted) {
          _emitProgress(DownloadProgress(
            surahNumber: surahNumber,
            reciterId: reciterId,
            status: AudioDownloadStatus.completed,
            downloadedBytes: destLength ?? 0,
            expectedTotalBytes: destLength,
          ));
          return;
        }
      }

      // Step 2: Head Request for Strong Validator and Representation Check
      // Condition 1: Accept-Encoding: identity is mandatory
      final headHeaders = {'Accept-Encoding': 'identity'};
      String? responseEtag;
      String? responseLastModified;
      String? responseOriginDate;
      int? headContentLength;

      try {
        final headUri = Uri.parse(effectiveAudioUrl);
        final headRes = await client.head(headUri, headers: headHeaders).timeout(
          const Duration(seconds: 4),
        );
        if (headRes.statusCode >= 200 && headRes.statusCode < 300) {
          responseEtag = headRes.headers['etag'];
          responseLastModified = headRes.headers['last-modified'];
          responseOriginDate = headRes.headers['date'];
          final cl = headRes.headers['content-length'];
          if (cl != null) headContentLength = int.tryParse(cl);
        }
      } catch (e) {
        debugPrint('[DownloadService] HEAD preflight optional check skipped/failed: $e');
      }

      // Classify Strong Validator according to RFC 9110
      String? strongValidatorToken;
      final etagCandidate = responseEtag ?? existingRecord?.etag;
      final lmCandidate = responseLastModified ?? existingRecord?.lastModified;

      if (HttpStrongValidator.isStrongEtag(etagCandidate)) {
        strongValidatorToken = etagCandidate!.trim();
      } else if (HttpStrongValidator.isStrongLastModified(
        lastModifiedHeader: lmCandidate,
        originDateHeader: responseOriginDate,
      )) {
        strongValidatorToken = 'STRONG_LM:$responseOriginDate|$lmCandidate';
      }

      // Step 3: Determine Offset & Staging File State
      int startOffset = 0;
      final stagingExists = await stagingFile.exists();
      int stagingLength = stagingExists ? await stagingFile.length() : 0;
      final effectiveExpected = expectedTotalBytes ?? headContentLength ?? existingRecord?.expectedSizeBytes;

      // RFC 9110 Invariant: If origin explicitly provides a Weak ETag (W/), Range resumption is forbidden
      final isWeakEtag = (responseEtag != null &&
          (responseEtag.trim().startsWith('W/') || responseEtag.trim().startsWith('w/')));

      if (isWeakEtag) {
        if (stagingExists && stagingLength > 0) {
          await stagingFile.writeAsBytes([], mode: FileMode.write);
        }
        startOffset = 0;
      } else if (stagingExists && stagingLength > 0) {
        if (effectiveExpected != null && stagingLength == effectiveExpected) {
          await _finalizeFullDownload(
            stagingFile: stagingFile,
            surahNumber: surahNumber,
            reciterId: reciterId,
            audioUrl: effectiveAudioUrl,
            totalBytes: effectiveExpected,
            etag: responseEtag ?? existingRecord?.etag,
            lastModified: responseLastModified ?? existingRecord?.lastModified,
          );
          return;
        }

        if (effectiveExpected != null && stagingLength > effectiveExpected) {
          await stagingFile.writeAsBytes([], mode: FileMode.write);
          startOffset = 0;
        } else {
          startOffset = stagingLength;
        }
      } else {
        startOffset = 0;
      }

      // Step 4: Dispatch HTTP GET with Range or Byte 0
      final getHeaders = <String, String>{
        'Accept-Encoding': 'identity',
      };
      if (startOffset > 0) {
        getHeaders['Range'] = 'bytes=$startOffset-';
        if (strongValidatorToken != null && HttpStrongValidator.isStrongEtag(strongValidatorToken)) {
          getHeaders['If-Range'] = strongValidatorToken;
        }
      }

      final request = http.Request('GET', Uri.parse(effectiveAudioUrl));
      request.headers.addAll(getHeaders);

      final streamedResponse = await client.send(request);

      if (task.isCancelled) {
        await _handleCancelled(surahNumber, reciterId);
        return;
      }

      int? authoritativeTotalBytes;

      if (streamedResponse.statusCode == 206) {
        // Rev 7 Contract C1-1: 206 total is EXCLUSIVELY the Content-Range denominator
        final contentRange = streamedResponse.headers['content-range'];
        if (contentRange != null) {
          final slashIdx = contentRange.lastIndexOf('/');
          if (slashIdx != -1) {
            final totalPart = contentRange.substring(slashIdx + 1).trim();
            authoritativeTotalBytes = int.tryParse(totalPart);
          }
        }
        authoritativeTotalBytes ??= expectedTotalBytes ?? headContentLength;

        sink = stagingFile.openWrite(mode: FileMode.append);
      } else if (streamedResponse.statusCode == 200) {
        final cl = streamedResponse.headers['content-length'];
        authoritativeTotalBytes = cl != null ? int.tryParse(cl) : (expectedTotalBytes ?? headContentLength);

        sink = stagingFile.openWrite(mode: FileMode.write);
        startOffset = 0;
      } else if (streamedResponse.statusCode == 416) {
        await stagingFile.writeAsBytes([], mode: FileMode.write);
        _activeTasks.remove(key);
        await _executeDownloadPipeline(
          surahNumber: surahNumber,
          reciterId: reciterId,
          audioUrl: effectiveAudioUrl,
          expectedTotalBytes: expectedTotalBytes,
        );
        return;
      } else {
        throw HttpException('HTTP download failed with status ${streamedResponse.statusCode}');
      }

      task.currentSink = sink;
      task.downloadedBytes = startOffset;
      task.totalBytes = authoritativeTotalBytes;

      // Update DB record to downloading
      final now = DateTime.now();
      await localDataSource.saveDownloadRecord(AudioDownloadModel(
        surahNumber: surahNumber,
        reciterId: reciterId,
        localRelativePath: QuranAudioStorageService.buildRelativePath(surahNumber, reciterId),
        tempRelativePath: p.relative(stagingFile.path, from: storageDir.path).replaceAll('\\', '/'),
        status: AudioDownloadStatus.downloading,
        actualSizeBytes: startOffset,
        expectedSizeBytes: authoritativeTotalBytes,
        etag: responseEtag ?? streamedResponse.headers['etag'],
        lastModified: responseLastModified ?? streamedResponse.headers['last-modified'],
        downloadedAt: existingRecord?.downloadedAt ?? now,
      ));

      // Step 5: Transfer Loop with Telemetry via Completer & Subscription
      int downloadedBytes = startOffset;
      DateTime lastTelemetry = DateTime.now();
      int bytesSinceTelemetry = 0;

      _emitProgress(DownloadProgress(
        surahNumber: surahNumber,
        reciterId: reciterId,
        status: AudioDownloadStatus.downloading,
        downloadedBytes: downloadedBytes,
        expectedTotalBytes: authoritativeTotalBytes,
      ));

      final streamCompleter = Completer<void>();
      task.streamCompleter = streamCompleter;

      final subscription = streamedResponse.stream.listen(
        (chunk) {
          if (task.isPaused || task.isCancelled) return;

          sink!.add(chunk);
          downloadedBytes += chunk.length;
          task.downloadedBytes = downloadedBytes;
          bytesSinceTelemetry += chunk.length;

          final currentNow = DateTime.now();
          final elapsed = currentNow.difference(lastTelemetry).inMilliseconds;
          if (elapsed >= 150) {
            final speed = bytesSinceTelemetry / (elapsed / 1000.0);
            Duration? eta;
            if (authoritativeTotalBytes != null && speed > 0) {
              final remaining = authoritativeTotalBytes - downloadedBytes;
              if (remaining > 0) {
                eta = Duration(seconds: (remaining / speed).ceil());
              }
            }

            _emitProgress(DownloadProgress(
              surahNumber: surahNumber,
              reciterId: reciterId,
              status: AudioDownloadStatus.downloading,
              downloadedBytes: downloadedBytes,
              expectedTotalBytes: authoritativeTotalBytes,
              downloadSpeedBytesPerSecond: speed,
              estimatedTimeRemaining: eta,
            ));

            lastTelemetry = currentNow;
            bytesSinceTelemetry = 0;
          }
        },
        onDone: () {
          if (!streamCompleter.isCompleted) streamCompleter.complete();
        },
        onError: (e, stack) {
          if (!streamCompleter.isCompleted) streamCompleter.completeError(e, stack);
        },
        cancelOnError: true,
      );

      task.subscription = subscription;

      await streamCompleter.future;

      if (task.isPaused || task.isCancelled) return;

      // Step 6: Transfer Complete - Flush Sink
      await sink.flush();
      await sink.close();
      task.currentSink = null;

      // Assert total length if expected length is known
      if (authoritativeTotalBytes != null && downloadedBytes != authoritativeTotalBytes) {
        throw HttpException('Stream truncated: received $downloadedBytes bytes, expected $authoritativeTotalBytes');
      }

      // Step 7: Finalize Verification & Atomic Promotion
      await _finalizeFullDownload(
        stagingFile: stagingFile,
        surahNumber: surahNumber,
        reciterId: reciterId,
        audioUrl: effectiveAudioUrl,
        totalBytes: downloadedBytes,
        etag: responseEtag ?? streamedResponse.headers['etag'],
        lastModified: responseLastModified ?? streamedResponse.headers['last-modified'],
      );
    } catch (e) {
      if (task.isCancelled) {
        await _handleCancelled(surahNumber, reciterId);
        return;
      }
      if (task.isPaused) {
        return;
      }

      debugPrint('[DownloadService] Transfer error for Surah $surahNumber: $e');
      final errorMsg = e.toString();

      _emitProgress(DownloadProgress(
        surahNumber: surahNumber,
        reciterId: reciterId,
        status: AudioDownloadStatus.failed,
        downloadedBytes: (await stagingFile?.exists() ?? false) ? await stagingFile!.length() : 0,
        expectedTotalBytes: expectedTotalBytes,
        lastError: errorMsg,
      ));

      final existing = await localDataSource.getDownloadRecord(surahNumber, reciterId);
      if (existing != null) {
        await localDataSource.saveDownloadRecord(existing.copyWith(
          status: AudioDownloadStatus.failed,
          lastError: errorMsg,
        ));
      }
    } finally {
      reservationTicket?.dispose();
      _activeTasks.remove(key);
      try {
        await sink?.close();
      } catch (_) {}
      client.close();
    }
  }

  Future<void> _finalizeFullDownload({
    required File stagingFile,
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    required int totalBytes,
    String? etag,
    String? lastModified,
  }) async {
    _emitProgress(DownloadProgress(
      surahNumber: surahNumber,
      reciterId: reciterId,
      status: AudioDownloadStatus.verifying,
      downloadedBytes: totalBytes,
      expectedTotalBytes: totalBytes,
    ));

    await storageService.promoteStagingFileWithJournal(
      stagingFile: stagingFile,
      surahNumber: surahNumber,
      reciterId: reciterId,
      localDataSource: localDataSource,
      expectedSizeBytes: totalBytes,
      etag: etag,
      lastModified: lastModified,
    );

    _emitProgress(DownloadProgress(
      surahNumber: surahNumber,
      reciterId: reciterId,
      status: AudioDownloadStatus.completed,
      downloadedBytes: totalBytes,
      expectedTotalBytes: totalBytes,
    ));
  }

  Future<void> _handlePaused(
    int surahNumber,
    String reciterId,
    int downloadedBytes,
    int? expectedTotal,
  ) async {
    final existing = await localDataSource.getDownloadRecord(surahNumber, reciterId);
    final storageDir = await storageService.getStorageDirectory();
    final stagingDir = await storageService.getStagingDirectory();
    final paddedSurah = surahNumber.toString().padLeft(3, '0');
    final cleanReciter = reciterId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final stagingFileName = 'dl_${cleanReciter}_$paddedSurah.tmp';
    final now = DateTime.now();

    final recordToSave = existing != null
        ? existing.copyWith(
            status: AudioDownloadStatus.paused,
            actualSizeBytes: downloadedBytes,
            expectedSizeBytes: expectedTotal,
          )
        : AudioDownloadModel(
            surahNumber: surahNumber,
            reciterId: reciterId,
            localRelativePath: QuranAudioStorageService.buildRelativePath(surahNumber, reciterId),
            tempRelativePath: p.relative(p.join(stagingDir.path, stagingFileName), from: storageDir.path).replaceAll('\\', '/'),
            status: AudioDownloadStatus.paused,
            actualSizeBytes: downloadedBytes,
            expectedSizeBytes: expectedTotal,
            downloadedAt: now,
          );

    await localDataSource.saveDownloadRecord(recordToSave);

    _emitProgress(DownloadProgress(
      surahNumber: surahNumber,
      reciterId: reciterId,
      status: AudioDownloadStatus.paused,
      downloadedBytes: downloadedBytes,
      expectedTotalBytes: expectedTotal,
    ));
  }

  Future<void> _handleCancelled(int surahNumber, String reciterId) async {
    try {
      final stagingDir = await storageService.getStagingDirectory();
      final paddedSurah = surahNumber.toString().padLeft(3, '0');
      final cleanReciter = reciterId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final stagingFile = File(p.join(stagingDir.path, 'dl_${cleanReciter}_$paddedSurah.tmp'));
      if (await stagingFile.exists()) {
        await stagingFile.delete();
      }
    } catch (_) {}

    final existing = await localDataSource.getDownloadRecord(surahNumber, reciterId);
    if (existing != null) {
      await localDataSource.saveDownloadRecord(existing.copyWith(
        status: AudioDownloadStatus.cancelled,
        actualSizeBytes: 0,
      ));
    }

    _emitProgress(DownloadProgress(
      surahNumber: surahNumber,
      reciterId: reciterId,
      status: AudioDownloadStatus.cancelled,
      downloadedBytes: 0,
    ));
  }

  @override
  Future<void> pauseDownload(int surahNumber, String reciterId) async {
    final key = _taskKey(surahNumber, reciterId);
    final task = _activeTasks.remove(key);
    if (task != null) {
      task.isPaused = true;
      await task.abort();
      await _handlePaused(
        surahNumber,
        reciterId,
        task.downloadedBytes,
        task.totalBytes,
      );
    }
  }

  @override
  Future<void> cancelDownload(int surahNumber, String reciterId) async {
    final key = _taskKey(surahNumber, reciterId);
    final task = _activeTasks.remove(key);
    if (task != null) {
      task.isCancelled = true;
      await task.abort();
    }
    await _handleCancelled(surahNumber, reciterId);
  }

  @override
  Future<void> retryDownload({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
  }) async {
    await cancelDownload(surahNumber, reciterId);
    downloadSurah(
      surahNumber: surahNumber,
      reciterId: reciterId,
      audioUrl: audioUrl,
      expectedTotalBytes: expectedTotalBytes,
    );
  }

  @override
  Future<SingleSurahDownloadResult> downloadSurahAndWait({
    required int surahNumber,
    required String reciterId,
    required String audioUrl,
    int? expectedTotalBytes,
    void Function(DownloadProgress progress)? onProgress,
    bool skipCoordinatorReservation = false,
  }) async {
    SingleSurahDownloadResult? terminalResult;

    try {
      final stream = downloadSurah(
        surahNumber: surahNumber,
        reciterId: reciterId,
        audioUrl: audioUrl,
        expectedTotalBytes: expectedTotalBytes,
        skipCoordinatorReservation: skipCoordinatorReservation,
      );

      await for (final progress in stream) {
        if (onProgress != null) {
          try {
            onProgress(progress);
          } catch (e) {
            debugPrint('[downloadSurahAndWait] Telemetry callback error: $e');
          }
        }

        if (progress.status == AudioDownloadStatus.completed) {
          terminalResult = await _authoritativeVerifyCompletion(
            surahNumber: surahNumber,
            reciterId: reciterId,
          );
          break;
        } else if (progress.status == AudioDownloadStatus.failed) {
          terminalResult = SingleSurahDownloadResult.failed(
            surahNumber: surahNumber,
            reciterId: reciterId,
            errorMessage: progress.lastError ?? 'Download failed',
            downloadedBytes: progress.downloadedBytes,
          );
          break;
        } else if (progress.status == AudioDownloadStatus.paused) {
          terminalResult = SingleSurahDownloadResult.paused(
            surahNumber: surahNumber,
            reciterId: reciterId,
            downloadedBytes: progress.downloadedBytes,
          );
          break;
        } else if (progress.status == AudioDownloadStatus.cancelled) {
          terminalResult = SingleSurahDownloadResult.cancelled(
            surahNumber: surahNumber,
            reciterId: reciterId,
          );
          break;
        }
      }
    } catch (e) {
      terminalResult = SingleSurahDownloadResult.failed(
        surahNumber: surahNumber,
        reciterId: reciterId,
        errorMessage: 'Download stream error: $e',
      );
    }

    terminalResult ??= await _authoritativeReconcileAfterStreamDone(
      surahNumber: surahNumber,
      reciterId: reciterId,
    );

    return terminalResult;
  }

  Future<SingleSurahDownloadResult> _authoritativeVerifyCompletion({
    required int surahNumber,
    required String reciterId,
  }) async {
    final record = await localDataSource.getDownloadRecord(surahNumber, reciterId);
    final file = await storageService.resolveSurahFile(surahNumber, reciterId);

    final bool isRecordValid = record != null &&
        record.status == AudioDownloadStatus.completed &&
        record.transferIntegrityVerified;

    final bool isFileValid = await file.exists() &&
        await file.length() > 0 &&
        (record == null || await file.length() == record.actualSizeBytes);

    if (isRecordValid && isFileValid) {
      return SingleSurahDownloadResult.completed(
        surahNumber: surahNumber,
        reciterId: reciterId,
        filePath: file.path,
        totalBytes: record.actualSizeBytes,
        sha256: record.sha256 ?? '',
      );
    }

    return SingleSurahDownloadResult.failed(
      surahNumber: surahNumber,
      reciterId: reciterId,
      errorMessage: 'Authoritative completion verification failed '
          '(recordValid=$isRecordValid, fileValid=$isFileValid)',
    );
  }

  Future<SingleSurahDownloadResult> _authoritativeReconcileAfterStreamDone({
    required int surahNumber,
    required String reciterId,
  }) async {
    final record = await localDataSource.getDownloadRecord(surahNumber, reciterId);
    if (record == null) {
      return SingleSurahDownloadResult.failed(
        surahNumber: surahNumber,
        reciterId: reciterId,
        errorMessage: 'Download terminated prematurely without record',
      );
    }

    if (record.status == AudioDownloadStatus.completed) {
      return _authoritativeVerifyCompletion(
        surahNumber: surahNumber,
        reciterId: reciterId,
      );
    } else if (record.status == AudioDownloadStatus.paused) {
      return SingleSurahDownloadResult.paused(
        surahNumber: surahNumber,
        reciterId: reciterId,
        downloadedBytes: record.actualSizeBytes,
      );
    } else {
      return SingleSurahDownloadResult.failed(
        surahNumber: surahNumber,
        reciterId: reciterId,
        errorMessage: 'Stream closed prematurely with record in status: ${record.status}',
        downloadedBytes: record.actualSizeBytes,
      );
    }
  }

  @override
  void dispose() {
    for (final task in _activeTasks.values) {
      task.isCancelled = true;
      task.abort();
    }
    _activeTasks.clear();

    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
    _latestProgress.clear();
  }
}
