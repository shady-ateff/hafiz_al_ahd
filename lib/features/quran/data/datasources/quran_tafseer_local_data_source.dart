import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../../core/errors/exception.dart';
import '../../domain/entities/ayah_id.dart';

/// Contract for the local data source responsible for reading and in-memory caching
/// of the offline Tafseer dataset.
abstract class BaseQuranTafseerLocalDataSource {
  /// Retrieves the raw Tafseer commentary string for the specified [ayahId].
  ///
  /// Throws [CacheException] if the Ayah does not exist in the dataset,
  /// or an [Exception] if reading/decoding the underlying asset fails.
  Future<String> getTafseerText(AyahId ayahId);

  /// Returns true if the dataset has already been loaded and cached in memory.
  bool get isLoaded;
}

/// Asset-backed implementation of [BaseQuranTafseerLocalDataSource].
///
/// Features:
/// 1. Lazy loading: Asset is loaded only on the first Tafseer request.
/// 2. In-memory dictionary caching: Decoded once and indexed by `surah:ayah`.
/// 3. Concurrency protection: Employs a shared initialization [Future] to ensure
///    that concurrent requests do not trigger redundant I/O or JSON decoding.
/// 4. Resilient retry: Clears in-flight Future on error to allow subsequent attempts.
/// 5. Dependency inversion: Accepts an optional [customDataLoader] to enable pure Dart testing.
class QuranTafseerLocalDataSourceImpl implements BaseQuranTafseerLocalDataSource {
  final String assetPath;
  final Future<String> Function()? customDataLoader;

  QuranTafseerLocalDataSourceImpl({
    this.assetPath = 'assets/quran/tafseer/tafseer_mouaser.json',
    this.customDataLoader,
  });

  Map<String, String>? _cachedTafseer;
  Future<Map<String, String>>? _loadingFuture;

  @override
  bool get isLoaded => _cachedTafseer != null;

  /// Returns the in-memory Tafseer dictionary, loading it lazily if not already present.
  Future<Map<String, String>> _getOrLoadMap() {
    if (_cachedTafseer != null) {
      return Future.value(_cachedTafseer!);
    }

    if (_loadingFuture != null) {
      return _loadingFuture!;
    }

    _loadingFuture = _loadData();
    return _loadingFuture!;
  }

  Future<Map<String, String>> _loadData() async {
    try {
      final String rawJson;
      if (customDataLoader != null) {
        rawJson = await customDataLoader!();
      } else {
        rawJson = await rootBundle.loadString(assetPath);
      }

      final map = await compute(
        _parseTafseerJsonInBackground,
        rawJson,
        debugLabel: 'TafseerJsonParser',
      );

      _cachedTafseer = map;
      return map;
    } catch (e) {
      // Clear in-flight future to allow retry on subsequent requests
      _loadingFuture = null;
      rethrow;
    }
  }

  @override
  Future<String> getTafseerText(AyahId ayahId) async {
    final map = await _getOrLoadMap();
    final text = map[ayahId.formatted];
    if (text == null) {
      throw CacheException();
    }
    return text;
  }
}

/// Top-level isolate computation function for decoding and parsing the Tafseer JSON dataset.
/// Executed strictly off the main UI thread via [compute] to preserve 60/120Hz frame budgets.
Map<String, String> _parseTafseerJsonInBackground(String rawJson) {
  if (rawJson.trim().isEmpty) {
    throw const FormatException('Tafseer asset is empty');
  }

  final dynamic decoded = jsonDecode(rawJson);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Tafseer root JSON must be a Map<String, dynamic>');
  }

  final dynamic rawMap = decoded['tafseer'];
  if (rawMap is! Map<String, dynamic>) {
    throw const FormatException('Tafseer asset missing or invalid "tafseer" key');
  }

  final map = <String, String>{};
  for (final entry in rawMap.entries) {
    final val = entry.value;
    if (val is String) {
      map[entry.key] = val;
    }
  }

  return map;
}

