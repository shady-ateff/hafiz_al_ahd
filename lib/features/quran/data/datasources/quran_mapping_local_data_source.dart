import 'dart:convert';
import 'package:flutter/services.dart';

/// Contract for the local data source responsible for loading and decoding
/// the raw Quran mapping JSON dataset.
abstract class BaseQuranMappingLocalDataSource {
  /// Loads and decodes the raw Quran mapping dataset into a Dart Map.
  Future<Map<String, dynamic>> loadRawMappingData();
}

/// Implementation of [BaseQuranMappingLocalDataSource] that loads the mapping
/// dataset from Flutter rootBundle assets or a custom data loader for testing.
class QuranMappingLocalDataSourceImpl implements BaseQuranMappingLocalDataSource {
  final String assetPath;
  final Future<String> Function()? customDataLoader;

  QuranMappingLocalDataSourceImpl({
    this.assetPath = 'assets/quran/mushaf/ayah_mapping.json',
    this.customDataLoader,
  });

  @override
  Future<Map<String, dynamic>> loadRawMappingData() async {
    try {
      final String rawJson;
      if (customDataLoader != null) {
        rawJson = await customDataLoader!();
      } else {
        rawJson = await rootBundle.loadString(assetPath);
      }

      if (rawJson.trim().isEmpty) {
        throw const FormatException('Quran mapping asset is empty');
      }

      final dynamic decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Quran mapping root JSON must be a Map<String, dynamic>');
      }

      // Top-level structure validation
      if (!decoded.containsKey('metadata') ||
          !decoded.containsKey('ayahs') ||
          !decoded.containsKey('pages')) {
        throw const FormatException(
          'Quran mapping dataset missing required top-level keys: metadata, ayahs, or pages',
        );
      }

      return decoded;
    } catch (e) {
      throw Exception('Failed to load Quran mapping asset "$assetPath": $e');
    }
  }
}

