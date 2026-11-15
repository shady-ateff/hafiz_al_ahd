import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dartz/dartz.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/custom_audio_storage_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_storage_inventory.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_progress.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_state.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/errors/audio_download_failures.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/audio_download_service.dart';

/// Internal cancellation token tied to a single download execution.
class _DownloadCancellationToken {
  final int id;
  bool isCancelled = false;
  StreamSubscription<List<int>>? streamSub;
  Completer<void>? streamCompleter;

  _DownloadCancellationToken(this.id);

  void cancel() {
    isCancelled = true;
    try {
      streamSub?.cancel();
    } catch (_) {}
    if (streamCompleter != null && !streamCompleter!.isCompleted) {
      streamCompleter!.completeError(AudioDownloadCancelledFailure());
    }
  }
}

class AudioDownloadServiceImpl implements BaseAudioDownloadService {
  final http.Client client;
  final CustomAudioStorageService storageService;
  final String? customBaseUrl;
  final Future<QuotaCheckResult> Function(int requiredBytes)? quotaAdmissionGuard;

  final Map<String, StreamController<AudioDownloadTask>> _controllers = {};
  final Map<String, AudioDownloadTask> _currentTasks = {};

  String? _activeEntryId;
  _DownloadCancellationToken? _activeToken;
  int _tokenSequence = 0;
  bool _isDisposed = false;

  AudioDownloadServiceImpl({
    required this.client,
    required this.storageService,
    this.customBaseUrl,
    this.quotaAdmissionGuard,
  });

  @override
  AudioDownloadTask? getTask(String entryId) => _currentTasks[entryId];

  @override
  List<AudioDownloadTask> getActiveTasks() {
    return _currentTasks.values
        .where((task) => task.status.isActive)
        .toList(growable: false);
  }

  @override
  Set<String> getActiveTempPrefixes() {
    if (_activeToken != null) {
      return {'dl_${_activeToken!.id}_'};
    }
    return const {};
  }

  /// Returns the in-flight temporary file prefix if a download is actively running.
  String? get activeTempFilePrefix =>
      _activeToken != null ? 'dl_${_activeToken!.id}_' : null;

  @override
  Stream<AudioDownloadTask> watchTask(String entryId) {
    _controllers.putIfAbsent(
      entryId,
      () => StreamController<AudioDownloadTask>.broadcast(),
    );
    // Yield current task immediately if available
    final current = _currentTasks[entryId] ?? AudioDownloadTask.idle(entryId);
    return Stream<AudioDownloadTask>.value(current).concatWith(
      _controllers[entryId]!.stream,
    );
  }

  void _emit(AudioDownloadTask task) {
    _currentTasks[task.entryId] = task;
    final controller = _controllers[task.entryId];
    if (controller != null && !controller.isClosed) {
      controller.add(task);
    }
  }

  /// Derives an immutable, content-addressed target filename:
  /// `remote_${slug}_${shaPrefix24}${ext}`
  static String buildTargetFileName(AdhanCatalogEntry entry) {
    final slug = entry.id
        .replaceFirst('remote:', '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final shaPrefix = entry.sha256.length >= 24
        ? entry.sha256.substring(0, 24).toLowerCase()
        : entry.sha256.toLowerCase();
    final ext = p.extension(entry.objectKey).toLowerCase();
    final safeExt = (ext.isEmpty || !CustomAudioStorageService.allowedExtensions.contains(ext))
        ? '.mp3'
        : ext;

    return 'remote_${slug}_$shaPrefix$safeExt';
  }

  @override
  Future<bool> isAudioDownloaded(String entryId) async {
    final storageDir = await storageService.getStorageDirectory();
    final files = storageDir.listSync().whereType<File>();
    final cleanSlug = entryId.replaceFirst('remote:', '').replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');

    for (final file in files) {
      final name = p.basename(file.path);
      if (name.startsWith('remote_${cleanSlug}_')) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<Either<AudioDownloadFailure, CustomAudioSource>> downloadAudio(
    AdhanCatalogEntry entry,
  ) async {
    if (_isDisposed) {
      return Left(AudioDownloadCancelledFailure(message: 'خدمة التنزيل مغلقة'));
    }

    // 1. Single-Task Concurrency Guard (Synchronous at method entry)
    if (_activeEntryId != null) {
      final failure = AudioDownloadConcurrencyFailure();
      _emit(AudioDownloadTask.failed(entryId: entry.id, failure: failure));
      return Left(failure);
    }

    _activeEntryId = entry.id;
    final token = _DownloadCancellationToken(++_tokenSequence);
    _activeToken = token;

    // 2. Atomic Quota Admission Guard (Guarantees effectiveRemoteUsageBytes + requestedBytes <= quota)
    if (quotaAdmissionGuard != null) {
      final quotaResult = await quotaAdmissionGuard!(entry.fileSizeBytes);
      if (!quotaResult.isAllowed) {
        _activeEntryId = null;
        _activeToken = null;
        final failure = AudioDownloadQuotaExceededFailure(
          requiredBytes: entry.fileSizeBytes,
          availableBytes: quotaResult.availableQuotaBytes,
        );
        _emit(AudioDownloadTask.failed(entryId: entry.id, failure: failure));
        return Left(failure);
      }
    }

    IOSink? sink;
    File? tempFile;
    int bytesWritten = 0;

    try {
      if (token.isCancelled) {
        throw AudioDownloadCancelledFailure();
      }

      // 2. URL Resolution & SSRF Guard
      final resolvedUrl = CatalogConfig.validateAndResolveUrl(
        entry.objectKey,
        customBaseUrl: customBaseUrl,
      );
      if (resolvedUrl == null) {
        throw AudioDownloadSecurityFailure();
      }

      // 3. Existing File Verification Check
      final storageDir = await storageService.getStorageDirectory();
      final targetFileName = buildTargetFileName(entry);
      final targetPath = p.normalize(p.join(storageDir.path, targetFileName));

      if (!targetPath.startsWith(storageDir.path)) {
        throw AudioDownloadSecurityFailure(message: 'مسار الملف غير آمن');
      }

      if (token.isCancelled) {
        throw AudioDownloadCancelledFailure();
      }

      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        final existingSize = await targetFile.length();
        if (existingSize == entry.fileSizeBytes) {
          final existingHash = await _calculateFileSha256(targetFile);
          if (existingHash == entry.sha256.toLowerCase()) {
            final customSource = CustomAudioSource(
              id: 'custom:${entry.id}',
              displayName: entry.displayName,
              localRelativePath: p.join('adhan_sounds', targetFileName),
              originalFileName: p.basename(entry.objectKey),
              fileSize: existingSize,
            );
            _emit(AudioDownloadTask.completed(entryId: entry.id, source: customSource));
            return Right(customSource);
          }
        }
        // Corrupt file exists with same name: safely delete it
        await targetFile.delete();
      }

      if (token.isCancelled) {
        throw AudioDownloadCancelledFailure();
      }

      // 4. Temp Directory Setup on the same filesystem
      final tempDir = Directory(p.join(storageDir.path, '.tmp'));
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      tempFile = File(p.join(
        tempDir.path,
        'dl_${token.id}_${DateTime.now().millisecondsSinceEpoch}.tmp',
      ));

      _emit(AudioDownloadTask.downloading(
        entryId: entry.id,
        progress: DownloadProgress.initial(totalBytes: entry.fileSizeBytes),
      ));

      final request = http.Request('GET', Uri.parse(resolvedUrl))
        ..followRedirects = false;

      final streamedResponse =
          await client.send(request).timeout(kAudioDownloadTimeout);

      if (streamedResponse.isRedirect ||
          streamedResponse.statusCode == 301 ||
          streamedResponse.statusCode == 302 ||
          streamedResponse.statusCode == 307 ||
          streamedResponse.statusCode == 308) {
        throw AudioDownloadSecurityFailure(message: 'تم حظر التحويل التلقائي لملف الصوت');
      }

      if (streamedResponse.statusCode == 404) {
        throw AudioDownloadNetworkFailure(message: 'ملف الصوت غير موجود على الخادم (404)');
      }

      if (streamedResponse.statusCode < 200 || streamedResponse.statusCode >= 300) {
        throw AudioDownloadNetworkFailure(
          message: 'فشل تحميل الصوت من الخادم (HTTP ${streamedResponse.statusCode})',
        );
      }

      sink = tempFile.openWrite();

      bytesWritten = 0;
      final completer = Completer<void>();
      token.streamCompleter = completer;

      late final StreamSubscription<List<int>> subscription;
      subscription = streamedResponse.stream.listen(
        (chunk) {
          if (token.isCancelled) {
            subscription.cancel();
            if (!completer.isCompleted) {
              completer.completeError(AudioDownloadCancelledFailure());
            }
            return;
          }

          bytesWritten += chunk.length;

          // Hard 30 MB Ceiling
          if (bytesWritten > kRemoteAudioMaxBytes) {
            subscription.cancel();
            if (!completer.isCompleted) {
              completer.completeError(
                AudioDownloadOversizedFailure(bytes: bytesWritten),
              );
            }
            return;
          }

          // Metadata size ceiling
          if (bytesWritten > entry.fileSizeBytes) {
            subscription.cancel();
            if (!completer.isCompleted) {
              completer.completeError(
                AudioDownloadSizeMismatchFailure(
                  actualBytes: bytesWritten,
                  expectedBytes: entry.fileSizeBytes,
                ),
              );
            }
            return;
          }

          sink?.add(chunk);

          _emit(AudioDownloadTask.downloading(
            entryId: entry.id,
            progress: DownloadProgress.determinate(
              receivedBytes: bytesWritten,
              totalBytes: entry.fileSizeBytes,
            ),
          ));
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      token.streamSub = subscription;

      await completer.future;

      await sink.flush();
      await sink.close();
      sink = null;

      if (token.isCancelled) {
        throw AudioDownloadCancelledFailure();
      }

      // 5. Verification
      if (token.isCancelled) {
        throw AudioDownloadCancelledFailure();
      }
      _emit(AudioDownloadTask.verifying(entry.id, bytesWritten));

      if (token.isCancelled) {
        throw AudioDownloadCancelledFailure();
      }

      if (bytesWritten != entry.fileSizeBytes) {
        if (token.isCancelled) {
          throw AudioDownloadCancelledFailure();
        }
        throw AudioDownloadSizeMismatchFailure(
          actualBytes: bytesWritten,
          expectedBytes: entry.fileSizeBytes,
        );
      }

      final digest = await sha256.bind(tempFile.openRead()).first;
      final calculatedHash = digest.toString().toLowerCase();
      if (calculatedHash != entry.sha256.toLowerCase()) {
        if (token.isCancelled) {
          throw AudioDownloadCancelledFailure();
        }
        throw AudioDownloadIntegrityFailure(
          actualHash: calculatedHash,
          expectedHash: entry.sha256.toLowerCase(),
        );
      }

      if (token.isCancelled) {
        throw AudioDownloadCancelledFailure();
      }

      // 6. Atomic File Promotion (File.rename on same filesystem)
      _emit(AudioDownloadTask.promoting(entry.id, bytesWritten));

      if (token.isCancelled) {
        throw AudioDownloadCancelledFailure();
      }

      await tempFile.rename(targetPath);

      if (token.isCancelled) {
        throw AudioDownloadCancelledFailure();
      }

      final customSource = CustomAudioSource(
        id: 'custom:${entry.id}',
        displayName: entry.displayName,
        localRelativePath: p.join('adhan_sounds', targetFileName),
        originalFileName: p.basename(entry.objectKey),
        fileSize: bytesWritten,
      );

      _emit(AudioDownloadTask.completed(entryId: entry.id, source: customSource));
      return Right(customSource);
    } on AudioDownloadCancelledFailure {
      _emit(AudioDownloadTask.cancelled(entry.id));
      return Left(AudioDownloadCancelledFailure());
    } on AudioDownloadFailure catch (e) {
      if (token.isCancelled) {
        _emit(AudioDownloadTask.cancelled(entry.id));
        return Left(AudioDownloadCancelledFailure());
      }
      _emit(AudioDownloadTask.failed(entryId: entry.id, failure: e));
      return Left(e);
    } on TimeoutException {
      if (token.isCancelled) {
        final failure = AudioDownloadCancelledFailure();
        _emit(AudioDownloadTask.cancelled(entry.id));
        return Left(failure);
      }
      final failure = AudioDownloadNetworkFailure(message: 'انتهت مهلة تنزيل الصوت');
      _emit(AudioDownloadTask.failed(entryId: entry.id, failure: failure));
      return Left(failure);
    } on SocketException catch (e) {
      if (token.isCancelled) {
        final failure = AudioDownloadCancelledFailure();
        _emit(AudioDownloadTask.cancelled(entry.id));
        return Left(failure);
      }
      if (bytesWritten > kRemoteAudioMaxBytes) {
        final failure = AudioDownloadOversizedFailure(bytes: bytesWritten);
        _emit(AudioDownloadTask.failed(entryId: entry.id, failure: failure));
        return Left(failure);
      }
      if (bytesWritten > entry.fileSizeBytes) {
        final failure = AudioDownloadSizeMismatchFailure(
          actualBytes: bytesWritten,
          expectedBytes: entry.fileSizeBytes,
        );
        _emit(AudioDownloadTask.failed(entryId: entry.id, failure: failure));
        return Left(failure);
      }
      final failure = AudioDownloadNetworkFailure(message: 'خطأ اتصال بالشبكة: ${e.message}');
      _emit(AudioDownloadTask.failed(entryId: entry.id, failure: failure));
      return Left(failure);
    } on http.ClientException catch (e) {
      if (token.isCancelled) {
        final failure = AudioDownloadCancelledFailure();
        _emit(AudioDownloadTask.cancelled(entry.id));
        return Left(failure);
      }
      if (bytesWritten > kRemoteAudioMaxBytes) {
        final failure = AudioDownloadOversizedFailure(bytes: bytesWritten);
        _emit(AudioDownloadTask.failed(entryId: entry.id, failure: failure));
        return Left(failure);
      }
      if (bytesWritten > entry.fileSizeBytes) {
        final failure = AudioDownloadSizeMismatchFailure(
          actualBytes: bytesWritten,
          expectedBytes: entry.fileSizeBytes,
        );
        _emit(AudioDownloadTask.failed(entryId: entry.id, failure: failure));
        return Left(failure);
      }
      final failure = AudioDownloadNetworkFailure(message: 'خطأ اتصال بالخادم: ${e.message}');
      _emit(AudioDownloadTask.failed(entryId: entry.id, failure: failure));
      return Left(failure);
    } on FileSystemException catch (e) {
      if (token.isCancelled) {
        final failure = AudioDownloadCancelledFailure();
        _emit(AudioDownloadTask.cancelled(entry.id));
        return Left(failure);
      }
      final failure = AudioDownloadStorageFailure(message: 'خطأ في التخزين المحلي: ${e.message}');
      _emit(AudioDownloadTask.failed(entryId: entry.id, failure: failure));
      return Left(failure);
    } catch (e) {
      if (token.isCancelled) {
        final failure = AudioDownloadCancelledFailure();
        _emit(AudioDownloadTask.cancelled(entry.id));
        return Left(failure);
      }
      final failure = AudioDownloadStorageFailure(message: 'خطأ غير متوقع: $e');
      _emit(AudioDownloadTask.failed(entryId: entry.id, failure: failure));
      return Left(failure);
    } finally {
      if (_activeEntryId == entry.id) {
        _activeEntryId = null;
        _activeToken = null;
      }
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  @override
  Future<void> cancelDownload(String entryId) async {
    final token = _activeToken;
    if (_activeEntryId == entryId && token != null) {
      token.cancel();
      _activeEntryId = null;
      _activeToken = null;
      _emit(AudioDownloadTask.cancelled(entryId));
    }
  }

  Future<String> _calculateFileSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    if (_activeToken != null) {
      _activeToken!.cancel();
      _activeToken = null;
      _activeEntryId = null;
    }
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
    _currentTasks.clear();
  }
}

extension _StreamConcatExtension<T> on Stream<T> {
  Stream<T> concatWith(Stream<T> other) async* {
    yield* this;
    yield* other;
  }
}
