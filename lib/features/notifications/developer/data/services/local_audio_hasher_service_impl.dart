import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/config/catalog_developer_config.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/local_audio_hasher_service.dart';
import 'package:path/path.dart' as p;

/// Implementation of [LocalAudioHasherService] with streaming SHA-256 calculation
/// and resilient duration probing.
class LocalAudioHasherServiceImpl implements LocalAudioHasherService {
  final Future<Duration?> Function(String filePath)? _durationProbe;

  LocalAudioHasherServiceImpl({
    Future<Duration?> Function(String filePath)? durationProbe,
  }) : _durationProbe = durationProbe;

  @override
  Future<LocalAudioHashResult> hashAudioFile(File file) async {
    // 1. File existence check
    if (!await file.exists()) {
      throw FileSystemException('الملف الصوتي المحدد غير موجود على القرص: ${file.path}');
    }

    // 2. Extension validation
    final ext = p.extension(file.path).toLowerCase();
    if (!CatalogDeveloperConfig.allowedAudioExtensions.contains(ext)) {
      throw FormatException(
        'صيغة الملف "$ext" غير مدعومة. الصيغ المدعومة هي: ${CatalogDeveloperConfig.allowedAudioExtensions.join(", ")}',
      );
    }

    // 3. File size boundary check (<= 30 MiB)
    final initialLength = await file.length();
    if (initialLength <= 0) {
      throw const FormatException('الملف الصوتي فارغ (حجمه 0 بايت).');
    }
    if (initialLength > kRemoteAudioMaxBytes) {
      final maxMiB = kRemoteAudioMaxBytes ~/ (1024 * 1024);
      throw FormatException(
        'حجم الملف (${(initialLength / (1024 * 1024)).toStringAsFixed(2)} MiB) يتجاوز الحد الأقصى المسموح به ($maxMiB MiB).',
      );
    }

    // 4. Streaming SHA-256 computation with byte counting & concurrent mutation check
    int totalBytesRead = 0;
    final countingStream = file.openRead().map((chunk) {
      totalBytesRead += chunk.length;
      if (totalBytesRead > kRemoteAudioMaxBytes) {
        throw FormatException(
          'حجم بيانات الملف أثناء القراءة تجاوز الحد الأقصى المسموح به (${kRemoteAudioMaxBytes ~/ (1024 * 1024)} MiB).',
        );
      }
      return chunk;
    });

    final digest = await crypto.sha256.bind(countingStream).first;
    final sha256Hex = digest.toString().toLowerCase();

    // Post-read mutation verification
    final postLength = await file.length();
    if (totalBytesRead != initialLength || postLength != initialLength) {
      throw FileSystemException(
        'تم تعديل الملف الصوتي أثناء عملية الحساب والتجزئة (تغير الحجم: البداية $initialLength بايت، المقروء $totalBytesRead بايت، النهاية $postLength بايت).',
        file.path,
      );
    }

    // 5. Audio Duration extraction (resilient: never fails hashing)
    int? durationSeconds;
    try {
      final duration = _durationProbe != null
          ? await _durationProbe(file.path)
          : await _probeDurationWithAudioPlayer(file.path);
      if (duration != null && duration.inSeconds > 0) {
        durationSeconds = duration.inSeconds;
      }
    } catch (_) {
      // Audio metadata extraction failure must never abort hashing
      durationSeconds = null;
    }

    final fileName = p.basename(file.path);

    return LocalAudioHashResult(
      filePath: file.path,
      fileName: fileName,
      fileSizeBytes: initialLength,
      sha256: sha256Hex,
      durationSeconds: durationSeconds,
    );
  }

  static Future<Duration?> _probeDurationWithAudioPlayer(String filePath) async {
    AudioPlayer? player;
    try {
      player = AudioPlayer();
      await player.setSource(DeviceFileSource(filePath)).timeout(const Duration(seconds: 4));
      final duration = await player.getDuration().timeout(const Duration(seconds: 4));
      return duration;
    } catch (_) {
      return null;
    } finally {
      try {
        await player?.stop();
      } catch (_) {}
      try {
        await player?.dispose();
      } catch (_) {}
    }
  }
}

