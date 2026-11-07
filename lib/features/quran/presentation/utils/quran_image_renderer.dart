import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/quran_ayah.dart';

/// Utility responsible for capturing the Quran Ayah card widget to a high-resolution PNG,
/// saving it to the platform temporary directory, and managing file cleanup.
class QuranImageRenderer {
  /// Captures a [RepaintBoundary] identified by [globalKey] to PNG byte data,
  /// scaling to [targetWidth] (default 1080px) to achieve a 1080×1350 4:5 image.
  static Future<Uint8List> captureBoundaryToPng(
    GlobalKey globalKey, {
    double targetWidth = 1080.0,
  }) async {
    final boundary = globalKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('RepaintBoundary not found for provided GlobalKey');
    }

    final double currentWidth = boundary.size.width;
    final double pixelRatio = currentWidth > 0 ? (targetWidth / currentWidth) : 2.0;

    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Failed to encode image to PNG format');
    }
    return byteData.buffer.asUint8List();
  }

  /// Saves [pngBytes] to a temporary PNG file and returns the file path.
  static Future<String> saveTempImageFile({
    required QuranAyah ayah,
    required Uint8List pngBytes,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final fileName =
        'hafiz_ayah_${ayah.id.surahNumber}_${ayah.id.ayahNumber}_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(pngBytes, flush: true);
    return file.path;
  }

  /// Cleans up a temporary file safely if it exists.
  static Future<void> cleanupTempFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore cleanup failures
    }
  }
}

