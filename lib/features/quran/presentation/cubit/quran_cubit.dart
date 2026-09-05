import 'dart:developer';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/get_quran_page_use_case.dart';
import 'quran_state.dart';

class QuranCubit extends Cubit<QuranState> {
  final GetQuranPageUseCase getQuranPageUseCase;

  // Cache loaded pages to avoid reloading from DB
  final Map<int, QuranState> _pagesCache = {};
  
  // Keep track of loaded fonts to avoid loading the same font multiple times
  final Set<int> _loadedFonts = {};

  QuranCubit({required this.getQuranPageUseCase}) : super(QuranInitial());

  Future<void> loadPage(int pageNumber) async {
    if (_pagesCache.containsKey(pageNumber)) {
      emit(_pagesCache[pageNumber]!);
      return;
    }

    // emit(QuranLoading());

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
      },
    );
  }

  Future<bool> _loadFontForPage(int pageNumber) async {
    if (_loadedFonts.contains(pageNumber)) return true;

    try {
      final String paddedNumber = pageNumber.toString().padLeft(3, '0');
      final String fontFamily = 'QCF2$paddedNumber';
      final String fontPath = 'assets/quran/fonts/$fontFamily.ttf';

      final FontLoader fontLoader = FontLoader(fontFamily);
      fontLoader.addFont(rootBundle.load(fontPath));
      await fontLoader.load();
      
      _loadedFonts.add(pageNumber);
      log("✅ Loaded font dynamically: $fontFamily");
      return true;
    } catch (e) {
      log("❌ Failed to load font for page $pageNumber: $e");
      return false;
    }
  }

  // Helper method for the UI to get the font family name
  static String getFontFamilyForPage(int pageNumber) {
    final String paddedNumber = pageNumber.toString().padLeft(3, '0');
    return 'QCF2$paddedNumber';
  }
}
