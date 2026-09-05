import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/DI/service_locator.dart';
import '../../domain/usecases/get_quran_page_use_case.dart';
import 'quran_state.dart';

class QuranCubit extends Cubit<QuranState> {
  final GetQuranPageUseCase getQuranPageUseCase;

  // Cache loaded pages to avoid reloading from DB
  final Map<int, QuranState> _pagesCache = {};
  
  // Keep track of loaded fonts to avoid loading the same font multiple times
  final Set<int> _loadedFonts = {};

  bool _isUnzipping = false;
  bool _fontsReady = false;
  String _fontsDir = '';
  int _lastRequestedPage = 1;

  bool get fontsReady => _fontsReady;

  QuranCubit({required this.getQuranPageUseCase}) : super(QuranInitial()) {
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
      final request = await httpClient.getUrl(Uri.parse(url));
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
        
        if (total > 0) {
          final double progress = downloaded / total;
          emit(QuranDownloadingFonts(progress));
        }
      }).asFuture();
      
      raf.closeSync();
      log("✅ Download complete, extracting...");
      emit(QuranLoading()); // Switching to extraction mode

      // Extract in background isolate to avoid UI freeze
      await compute(_extractZip, {'zipPath': zipPath, 'destPath': _fontsDir});

      await prefs.setBool('quran_fonts_extracted', true);
      _fontsReady = true;
      _isUnzipping = false;
      log("✅ Quran fonts extracted successfully!");
      
      // Reload the requested page
      loadPage(_lastRequestedPage);
    } catch (e) {
      _isUnzipping = false;
      log("❌ Error extracting fonts: $e");
      emit(QuranError("فشل في تهيئة خطوط المصحف. تأكد من اتصالك بالإنترنت."));
    }
  }

  static void _extractZip(Map<String, dynamic> args) {
    final String zipPath = args['zipPath'];
    final String destPath = args['destPath'];
    
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      if (file.isFile) {
        final data = file.content as List<int>;
        File('$destPath/${file.name}')
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      }
    }
    // Delete the zip file to save space
    File(zipPath).deleteSync();
  }

  QuranPageLoaded? getCachedPage(int pageNumber) {
    return _pagesCache[pageNumber] as QuranPageLoaded?;
  }

  Future<void> loadPage(int pageNumber) async {
    _lastRequestedPage = pageNumber;
    
    if (_pagesCache.containsKey(pageNumber)) {
      emit(_pagesCache[pageNumber]!);
      return;
    }

    if (_isUnzipping) {
      emit(QuranLoading());
      return; // wait for extraction to complete
    }

    final failureOrPage = await getQuranPageUseCase(pageNumber);

    failureOrPage.fold(
      (failure) {
        emit(QuranError(failure.message));
      },
      (page) async {
        // Load the specific QCF font for this page dynamically
        bool isFontLoaded = await _loadFontForPage(pageNumber);
        
        // Also always ensure QCF2001 is loaded, because we use it for the Basmalah!
        await _loadFontForPage(1);
        
        final state = QuranPageLoaded(page: page, isFontLoaded: isFontLoaded);
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
      final String fontPath = '$_fontsDir/fonts/$fontFamily.ttf';
      final File fontFile = File(fontPath);

      if (!await fontFile.exists()) {
        log("❌ Font file not found at: $fontPath");
        return false;
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
      final String fontPath = '$fontsDir/fonts/QCF2$paddedNumber.ttf';
      final file = File(fontPath);
      if (file.existsSync()) {
        result[p] = file.readAsBytesSync();
      }
    }
    return result;
  }

  // Helper method for the UI to get the font family name
  static String getFontFamilyForPage(int pageNumber) {
    final String paddedNumber = pageNumber.toString().padLeft(3, '0');
    return 'QCF2$paddedNumber';
  }
}
