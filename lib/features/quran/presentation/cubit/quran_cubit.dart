import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/DI/service_locator.dart';
import '../../domain/entities/ayah_id.dart';
import '../../domain/entities/quran_line_mapping.dart';
import '../../domain/repositories/base_quran_mapping_repository.dart';
import '../../domain/usecases/get_quran_page_use_case.dart';
import 'quran_state.dart';

class QuranCubit extends Cubit<QuranState> {
  final GetQuranPageUseCase getQuranPageUseCase;
  final BaseQuranMappingRepository? mappingRepository;

  // Cache loaded pages to avoid reloading from DB
  final Map<int, QuranState> _pagesCache = {};
  
  // Keep track of loaded fonts to avoid loading the same font multiple times
  final Set<int> _loadedFonts = {};

  bool _isUnzipping = false;
  bool _fontsReady = false;
  String _fontsDir = '';
  int _lastRequestedPage = 1;

  bool get fontsReady => _fontsReady;
  bool get isUnzipping => _isUnzipping;

  AyahId? get selectedAyahId {
    final s = state;
    if (s is QuranPageLoaded) {
      return s.selectedAyahId;
    }
    return null;
  }

  QuranCubit({
    required this.getQuranPageUseCase,
    this.mappingRepository,
  }) : super(QuranInitial()) {
    initFonts();
  }

  Future<void> initFonts() async {
    try {
      final prefs = sl<SharedPreferences>();
      final isExtracted = prefs.getBool('quran_fonts_extracted') ?? false;
      
      final docDir = await getApplicationDocumentsDirectory();
      _fontsDir = '${docDir.path}/quran_fonts';
      final dir = Directory(_fontsDir);

      if (isExtracted && await dir.exists()) {
        _fontsReady = true;
        log("✅ Quran fonts are already extracted at $_fontsDir");
        return;
      }

      if (isClosed) return;
      _isUnzipping = true;
      emit(const QuranDownloadingFonts(0.0));
      log("⏳ Starting Quran fonts download...");

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final zipPath = '${dir.path}/fonts.zip';
      final file = File(zipPath);

      // Download from internet
      final url = 'https://github.com/shady-ateff/hafiz_al_ahd/releases/download/v1.0.0/quran_fonts.zip';
      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 30);
      httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) {
        return host.contains('github.com') || host.contains('githubusercontent.com');
      };
      final request = await httpClient.getUrl(Uri.parse(url));
      request.followRedirects = true;
      final response = await request.close();
      
      if (response.statusCode != 200) {
        throw Exception('فشل تحميل الخطوط من السيرفر. كود الخطأ: ${response.statusCode}');
      }

      final raf = file.openSync(mode: FileMode.write);
      int downloaded = 0;
      final total = response.contentLength;
      
      await response.listen((data) {
        downloaded += data.length;
        raf.writeFromSync(data);
        
        if (total > 0 && !isClosed) {
          final double progress = downloaded / total;
          emit(QuranDownloadingFonts(progress));
        }
      }).asFuture();

      await raf.close();
      log("✅ Download finished. Now extracting fonts in background...");

      if (isClosed) return;
      emit(QuranLoading()); // Change state while extracting

      // Extract ZIP in background isolate to prevent UI freezing
      await compute(_extractZipFile, {
        'zipPath': zipPath,
        'destPath': dir.path,
      });

      _fontsReady = true;
      _isUnzipping = false;
      await prefs.setBool('quran_fonts_extracted', true);
      log("✅ Extraction complete! Fonts are ready.");

      if (isClosed) return;
      // Reload the last page after fonts are ready
      loadPage(_lastRequestedPage);
    } catch (e) {
      _isUnzipping = false;
      log("❌ Error initializing Quran fonts: $e");
      if (!isClosed) {
        emit(QuranError('حدث خطأ أثناء تحميل خطوط المصحف: يرجى التحقق من اتصال الإنترنت والمحاولة مرة أخرى.'));
      }
    }
  }

  /// Retries the font download process by cleaning up cache, state, and retrying initFonts.
  Future<void> retryFontsDownload() async {
    _fontsReady = false;
    _isUnzipping = false;
    _pagesCache.clear();
    _loadedFonts.clear();
    try {
      final prefs = sl<SharedPreferences>();
      await prefs.remove('quran_fonts_extracted');

      final docDir = await getApplicationDocumentsDirectory();
      final zipFile = File('${docDir.path}/quran_fonts/fonts.zip');
      if (await zipFile.exists()) {
        await zipFile.delete();
      }
    } catch (_) {}

    await initFonts();
  }

  static void _extractZipFile(Map<String, dynamic> args) {
    final zipPath = args['zipPath'] as String;
    final destPath = args['destPath'] as String;

    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        final outFile = File('$destPath/$filename');
        outFile.createSync(recursive: true);
        outFile.writeAsBytesSync(data);
      } else {
        Directory('$destPath/$filename').createSync(recursive: true);
      }
    }

    // Delete the zip file to save space
    File(zipPath).deleteSync();
  }

  QuranPageLoaded? getCachedPage(int pageNumber) {
    return _pagesCache[pageNumber] as QuranPageLoaded?;
  }

  void selectAyah(AyahId ayahId, {int? pageNumber}) {
    final targetPageNumber = pageNumber ??
        (state is QuranPageLoaded
            ? (state as QuranPageLoaded).page.pageNumber
            : _lastRequestedPage);

    final cached = _pagesCache[targetPageNumber];
    final targetState = (cached is QuranPageLoaded)
        ? cached
        : (state is QuranPageLoaded &&
                (state as QuranPageLoaded).page.pageNumber == targetPageNumber)
            ? state as QuranPageLoaded
            : null;

    if (targetState == null) return;

    if (targetState.selectedAyahId == ayahId) {
      return;
    }

    final updatedState = targetState.copyWith(
      selectedAyahId: ayahId,
      clearSelectedAyah: false,
    );

    _pagesCache[targetPageNumber] = updatedState;
    emit(updatedState);
  }

  void toggleAyahSelection(AyahId ayahId, {int? pageNumber}) {
    final targetPageNumber = pageNumber ??
        (state is QuranPageLoaded
            ? (state as QuranPageLoaded).page.pageNumber
            : _lastRequestedPage);

    final cached = _pagesCache[targetPageNumber];
    final targetState = (cached is QuranPageLoaded)
        ? cached
        : (state is QuranPageLoaded &&
                (state as QuranPageLoaded).page.pageNumber == targetPageNumber)
            ? state as QuranPageLoaded
            : null;

    if (targetState == null) return;

    final isSameAyah = targetState.selectedAyahId == ayahId;
    final updatedState = targetState.copyWith(
      selectedAyahId: isSameAyah ? null : ayahId,
      clearSelectedAyah: isSameAyah,
    );

    _pagesCache[targetPageNumber] = updatedState;
    emit(updatedState);
  }

  void clearSelection() {
    final currentState = state;
    if (currentState is! QuranPageLoaded) return;
    if (currentState.selectedAyahId == null) return;

    final updatedState = currentState.copyWith(clearSelectedAyah: true);
    _pagesCache[currentState.page.pageNumber] = updatedState;
    emit(updatedState);
  }

  Future<void> preloadPage(int pageNumber) async {
    if (_pagesCache.containsKey(pageNumber)) return;
    if (_isUnzipping) return;

    final failureOrPage = await getQuranPageUseCase(pageNumber);
    await failureOrPage.fold(
      (failure) async {},
      (page) async {
        bool isFontLoaded = await _loadFontForPage(pageNumber);
        await _loadFontForPage(1);

        List<QuranLineMapping>? lineMappings;
        if (mappingRepository != null) {
          try {
            await mappingRepository!.init();
            final mappingResult = await mappingRepository!.getPageMapping(pageNumber);
            lineMappings = mappingResult.getOrElse(() => []);
          } catch (_) {}
        }

        final state = QuranPageLoaded(
          page: page,
          isFontLoaded: isFontLoaded,
          lineMappings: lineMappings,
        );
        _pagesCache[pageNumber] = state;
        _preloadSurroundingFonts(pageNumber);
      },
    );
  }

  Future<void> loadPage(int pageNumber) async {
    _lastRequestedPage = pageNumber;
    
    if (_pagesCache.containsKey(pageNumber)) {
      final cachedState = _pagesCache[pageNumber]!;
      if (cachedState is QuranPageLoaded && cachedState.selectedAyahId != null) {
        final sanitizedState = cachedState.copyWith(clearSelectedAyah: true);
        _pagesCache[pageNumber] = sanitizedState;
        emit(sanitizedState);
        return;
      }
      emit(cachedState);
      return;
    }

    if (_isUnzipping) {
      emit(QuranLoading());
      return; // wait for extraction to complete
    }

    final failureOrPage = await getQuranPageUseCase(pageNumber);
    if (isClosed) return;

    await failureOrPage.fold(
      (failure) async {
        if (!isClosed) {
          emit(QuranError(failure.message));
        }
      },
      (page) async {
        // Load the specific QCF font for this page dynamically
        bool isFontLoaded = await _loadFontForPage(pageNumber);
        
        // Also always ensure QCF2001 is loaded, because we use it for the Basmalah!
        await _loadFontForPage(1);

        // Fetch page mappings if mapping repository is provided
        List<QuranLineMapping>? lineMappings;
        if (mappingRepository != null) {
          try {
            await mappingRepository!.init();
            final mappingResult = await mappingRepository!.getPageMapping(pageNumber);
            lineMappings = mappingResult.getOrElse(() => []);
          } catch (e) {
            log("⚠️ Failed to load mappings for page $pageNumber: $e");
          }
        }
        
        if (isClosed) return;

        final state = QuranPageLoaded(
          page: page,
          isFontLoaded: isFontLoaded,
          lineMappings: lineMappings,
        );
        _pagesCache[pageNumber] = state;
        emit(state);

        // Preload fonts for 4 pages before and after in an Isolate
        _preloadSurroundingFonts(pageNumber);
      },
    );
  }

  Future<bool> _loadFontForPage(int pageNumber) async {
    if (_loadedFonts.contains(pageNumber)) return true;
    if (!_fontsReady) return false;

    try {
      final String paddedNumber = pageNumber.toString().padLeft(3, '0');
      final String fontFamily = 'QCF2$paddedNumber';
      String fontPath = '$_fontsDir/fonts/$fontFamily.ttf';
      File fontFile = File(fontPath);

      if (!await fontFile.exists()) {
        // Fallback for flattened zip extraction
        fontPath = '$_fontsDir/$fontFamily.ttf';
        fontFile = File(fontPath);
        if (!await fontFile.exists()) {
          log("❌ Font file not found at: $fontPath");
          return false;
        }
      }

      final Uint8List fontBytes = await fontFile.readAsBytes();
      final ByteData byteData = ByteData.view(fontBytes.buffer);

      final FontLoader fontLoader = FontLoader(fontFamily);
      fontLoader.addFont(Future.value(byteData));
      await fontLoader.load();
      
      _loadedFonts.add(pageNumber);
      log("✅ Loaded font dynamically from local storage: $fontFamily");
      return true;
    } catch (e) {
      log("❌ Failed to load font for page $pageNumber: $e");
      return false;
    }
  }

  int? _lastPreloadedPage;

  Future<void> _preloadSurroundingFonts(int pageNumber) async {
    if (!_fontsReady) return;

    // Throttle the cache updating to every 4 pages to save CPU
    if (_lastPreloadedPage != null && (pageNumber - _lastPreloadedPage!).abs() < 4) {
      return;
    }
    _lastPreloadedPage = pageNumber;

    final pagesToLoad = <int>[];
    for (int i = 1; i <= 4; i++) {
      if (pageNumber + i <= 604 && !_loadedFonts.contains(pageNumber + i)) {
        pagesToLoad.add(pageNumber + i);
      }
      if (pageNumber - i >= 1 && !_loadedFonts.contains(pageNumber - i)) {
        pagesToLoad.add(pageNumber - i);
      }
    }

    if (pagesToLoad.isEmpty) return;

    try {
      // 1. Read files from disk in a background isolate
      final Map<int, Uint8List> fontBytesMap = await compute(_readFontsFromDisk, {
        'fontsDir': _fontsDir,
        'pages': pagesToLoad,
      });

      // 2. Register them with the Flutter engine in the main isolate
      for (final entry in fontBytesMap.entries) {
        final pNum = entry.key;
        final bytes = entry.value;
        if (_loadedFonts.contains(pNum)) continue;

        final String paddedNumber = pNum.toString().padLeft(3, '0');
        final String fontFamily = 'QCF2$paddedNumber';
        final FontLoader fontLoader = FontLoader(fontFamily);
        fontLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
        await fontLoader.load();
        _loadedFonts.add(pNum);
        log("✅ Preloaded font dynamically (Isolate): $fontFamily");
      }
    } catch (e) {
      log("❌ Failed to preload surrounding fonts: $e");
    }
  }

  static Map<int, Uint8List> _readFontsFromDisk(Map<String, dynamic> args) {
    final String fontsDir = args['fontsDir'];
    final List<int> pages = args['pages'];
    final Map<int, Uint8List> result = {};

    for (final p in pages) {
      final String paddedNumber = p.toString().padLeft(3, '0');
      String fontPath = '$fontsDir/fonts/QCF2$paddedNumber.ttf';
      File file = File(fontPath);

      if (!file.existsSync()) {
        fontPath = '$fontsDir/QCF2$paddedNumber.ttf';
        file = File(fontPath);
      }

      if (file.existsSync()) {
        result[p] = file.readAsBytesSync();
      }
    }
    return result;
  }

  /// Returns true if the QCF font for [pageNumber] has been loaded into the engine.
  bool isFontLoaded(int pageNumber) => _loadedFonts.contains(pageNumber);

  // Helper method for the UI to get the font family name
  static String getFontFamilyForPage(int pageNumber) {
    final String paddedNumber = pageNumber.toString().padLeft(3, '0');
    return 'QCF2$paddedNumber';
  }
}
