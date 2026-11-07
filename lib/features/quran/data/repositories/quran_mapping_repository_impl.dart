import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:hafiz_al_ahd/core/errors/failure.dart';
import '../../domain/entities/quran_mapping_entities.dart';
import '../../domain/repositories/base_quran_mapping_repository.dart';
import '../datasources/quran_mapping_local_data_source.dart';

/// Production implementation of [BaseQuranMappingRepository] that loads and indexes
/// the Quran ayah mapping dataset into high-performance in-memory hash maps.
class QuranMappingRepositoryImpl implements BaseQuranMappingRepository {
  final BaseQuranMappingLocalDataSource localDataSource;

  QuranMappingRepositoryImpl({required this.localDataSource});

  // In-memory indexes for O(1) lookups
  final Map<int, List<QuranLineMapping>> _pagesIndex = {};
  final Map<AyahId, QuranAyah> _ayahsIndex = {};
  final Map<AyahId, List<AyahSegment>> _ayahSegmentsIndex = {};
  final Map<WordLocation, QuranWord> _wordsIndex = {};

  bool _isInitialized = false;
  Future<Either<Failure, void>>? _initFuture;

  /// Returns true if the repository has successfully parsed and indexed the dataset.
  bool get isInitialized => _isInitialized;

  @override
  Future<Either<Failure, void>> init() async {
    if (_isInitialized) {
      return const Right(null);
    }

    if (_initFuture != null) {
      return await _initFuture!;
    }

    _initFuture = _doInit();
    final result = await _initFuture!;
    if (result.isLeft()) {
      // Allow retrying if initialization failed
      _initFuture = null;
    }
    return result;
  }

  Future<Either<Failure, void>> _doInit() async {
    try {
      final rawJson = await localDataSource.loadRawMappingJsonString();

      final parsedData = await compute(
        _parseAndIndexQuranMapping,
        rawJson,
        debugLabel: 'QuranMappingParser',
      );

      _pagesIndex.clear();
      _ayahsIndex.clear();
      _ayahSegmentsIndex.clear();
      _wordsIndex.clear();

      _pagesIndex.addAll(parsedData.pagesIndex);
      _ayahsIndex.addAll(parsedData.ayahsIndex);
      _ayahSegmentsIndex.addAll(parsedData.ayahSegmentsIndex);
      _wordsIndex.addAll(parsedData.wordsIndex);

      _isInitialized = true;
      return const Right(null);
    } catch (e) {
      _isInitialized = false;
      return Left(CacheFailure(message: 'Failed to initialize Quran mapping repository: $e'));
    }
  }

  @override
  Future<Either<Failure, List<QuranLineMapping>>> getPageMapping(int pageNumber) async {
    if (!_isInitialized) {
      return Left(CacheFailure(
        message: 'QuranMappingRepository is not initialized. Call init() first.',
      ));
    }

    if (pageNumber < 1 || pageNumber > 604) {
      return Left(CacheFailure(
        message: 'Invalid page number: $pageNumber. Page must be between 1 and 604.',
      ));
    }

    final lines = _pagesIndex[pageNumber];
    if (lines == null || lines.isEmpty) {
      return Left(CacheFailure(
        message: 'No mapping found for page $pageNumber.',
      ));
    }

    return Right(lines);
  }

  @override
  Future<Either<Failure, QuranAyah>> getAyah(AyahId ayahId) async {
    if (!_isInitialized) {
      return Left(CacheFailure(
        message: 'QuranMappingRepository is not initialized. Call init() first.',
      ));
    }

    final ayah = _ayahsIndex[ayahId];
    if (ayah == null) {
      return Left(CacheFailure(
        message: 'Ayah not found: $ayahId',
      ));
    }

    return Right(ayah);
  }

  @override
  Future<Either<Failure, List<AyahSegment>>> getAyahSegments(AyahId ayahId) async {
    if (!_isInitialized) {
      return Left(CacheFailure(
        message: 'QuranMappingRepository is not initialized. Call init() first.',
      ));
    }

    final segments = _ayahSegmentsIndex[ayahId];
    if (segments == null || segments.isEmpty) {
      return Left(CacheFailure(
        message: 'No segments found for Ayah $ayahId',
      ));
    }

    return Right(segments);
  }

  @override
  Future<Either<Failure, QuranWord>> getWord(WordLocation location) async {
    if (!_isInitialized) {
      return Left(CacheFailure(
        message: 'QuranMappingRepository is not initialized. Call init() first.',
      ));
    }

    final word = _wordsIndex[location];
    if (word == null) {
      return Left(CacheFailure(
        message: 'Word not found at location: $location',
      ));
    }

    return Right(word);
  }
}

/// Internal immutable transfer container holding the indexed Quran mapping dataset
/// constructed in a background isolate and transferred to the main repository.
class QuranMappingParsedData {
  final Map<int, List<QuranLineMapping>> pagesIndex;
  final Map<AyahId, QuranAyah> ayahsIndex;
  final Map<AyahId, List<AyahSegment>> ayahSegmentsIndex;
  final Map<WordLocation, QuranWord> wordsIndex;

  QuranMappingParsedData({
    required this.pagesIndex,
    required this.ayahsIndex,
    required this.ayahSegmentsIndex,
    required this.wordsIndex,
  });
}

/// Top-level isolate computation function for decoding, parsing, and indexing
/// the 11.5 MB Quran ayah mapping dataset.
/// Executed strictly off the main UI thread via [compute] to eliminate UI frame freezes.
QuranMappingParsedData _parseAndIndexQuranMapping(String rawJson) {
  if (rawJson.trim().isEmpty) {
    throw const FormatException('Quran mapping asset is empty');
  }

  final dynamic decoded = jsonDecode(rawJson);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Quran mapping root JSON must be a Map<String, dynamic>');
  }

  if (!decoded.containsKey('metadata') ||
      !decoded.containsKey('ayahs') ||
      !decoded.containsKey('pages')) {
    throw const FormatException(
      'Quran mapping dataset missing required top-level keys: metadata, ayahs, or pages',
    );
  }

  final rawPages = decoded['pages'] as Map<String, dynamic>;
  final rawAyahs = decoded['ayahs'] as Map<String, dynamic>;

  final Map<int, List<QuranLineMapping>> pagesIndex = {};
  final Map<AyahId, QuranAyah> ayahsIndex = {};
  final Map<AyahId, List<AyahSegment>> ayahSegmentsIndex = {};
  final Map<WordLocation, QuranWord> wordsIndex = {};

  // 1. Index Pages and Words
  for (final entry in rawPages.entries) {
    final int pageNumber = int.parse(entry.key);
    final List<dynamic> linesList = entry.value as List<dynamic>;

    final List<QuranLineMapping> pageLines = [];

    for (final lineObj in linesList) {
      final int lineNumber = lineObj['line'] as int;
      final List<dynamic> wordsList = lineObj['words'] as List<dynamic>;

      final List<QuranWord> lineWords = [];

      for (final wordObj in wordsList) {
        final int surah = wordObj['surah'] as int;
        final int ayah = wordObj['ayah'] as int;
        final int wordIndex = wordObj['word_index'] as int;
        final String uthmani = wordObj['uthmani'] as String;
        final String qcf = wordObj['qcf'] as String;

        final location = WordLocation(
          surahNumber: surah,
          ayahNumber: ayah,
          wordIndex: wordIndex,
        );

        final word = QuranWord(
          location: location,
          uthmaniText: uthmani,
          qcfText: qcf,
        );

        wordsIndex[location] = word;
        lineWords.add(word);
      }

      final lineMapping = QuranLineMapping(
        pageNumber: pageNumber,
        lineNumber: lineNumber,
        words: lineWords,
      );

      pageLines.add(lineMapping);
    }

    // Sort lines by physical line number ascending
    pageLines.sort((a, b) => a.lineNumber.compareTo(b.lineNumber));
    pagesIndex[pageNumber] = List<QuranLineMapping>.unmodifiable(pageLines);
  }

  // 2. Index Ayahs and Segments
  for (final entry in rawAyahs.entries) {
    final AyahId ayahId = AyahId.fromString(entry.key);
    final Map<String, dynamic> ayahData = entry.value as Map<String, dynamic>;

    final int page = ayahData['page'] as int;
    final int endPage = ayahData['end_page'] as int;
    final String uthmani = ayahData['uthmani'] as String;
    final int wordsCount = ayahData['words_count'] as int;
    final List<dynamic> rawSegments = ayahData['segments'] as List<dynamic>;

    final List<AyahSegment> ayahSegments = [];

    for (final segObj in rawSegments) {
      final int segPage = segObj['page'] as int;
      final int segLine = segObj['line'] as int;
      final int wordStart = segObj['word_start'] as int;
      final int wordEnd = segObj['word_end'] as int;

      final pageLines = pagesIndex[segPage];
      if (pageLines == null) {
        throw FormatException('Segment references unknown page $segPage for Ayah $ayahId');
      }

      final line = pageLines.firstWhere(
        (l) => l.lineNumber == segLine,
        orElse: () => throw FormatException(
          'Segment references unknown line $segLine on page $segPage for Ayah $ayahId',
        ),
      );

      if (wordStart < 0 || wordEnd >= line.words.length || wordStart > wordEnd) {
        throw FormatException(
          'Segment word slice [$wordStart..$wordEnd] out of bounds on page $segPage line $segLine (line words: ${line.words.length})',
        );
      }

      final sliceWords = line.words.sublist(wordStart, wordEnd + 1);
      final String qcfText = sliceWords.map((w) => w.qcfText).join(' ');

      final segment = AyahSegment(
        ayahId: ayahId,
        pageNumber: segPage,
        lineNumber: segLine,
        wordStart: wordStart,
        wordEnd: wordEnd,
        qcfText: qcfText,
      );

      ayahSegments.add(segment);
    }

    final unmodifiableSegments = List<AyahSegment>.unmodifiable(ayahSegments);
    ayahSegmentsIndex[ayahId] = unmodifiableSegments;

    final quranAyah = QuranAyah(
      id: ayahId,
      pageNumber: page,
      endPageNumber: endPage,
      uthmaniText: uthmani,
      wordsCount: wordsCount,
      segments: unmodifiableSegments,
    );

    ayahsIndex[ayahId] = quranAyah;
  }

  return QuranMappingParsedData(
    pagesIndex: pagesIndex,
    ayahsIndex: ayahsIndex,
    ayahSegmentsIndex: ayahSegmentsIndex,
    wordsIndex: wordsIndex,
  );
}

