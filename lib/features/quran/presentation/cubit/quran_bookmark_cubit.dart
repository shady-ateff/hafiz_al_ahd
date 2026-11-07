import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/ayah_id.dart';
import '../../domain/entities/quran_bookmark.dart';
import '../../domain/usecases/add_quran_bookmark_use_case.dart';
import '../../domain/usecases/get_quran_bookmarks_use_case.dart';
import '../../domain/usecases/remove_quran_bookmark_use_case.dart';
import '../../domain/usecases/toggle_quran_bookmark_use_case.dart';
import 'quran_bookmark_state.dart';

class QuranBookmarkCubit extends Cubit<QuranBookmarkState> {
  final GetQuranBookmarksUseCase getBookmarksUseCase;
  final ToggleQuranBookmarkUseCase toggleBookmarkUseCase;
  final RemoveQuranBookmarkUseCase removeBookmarkUseCase;
  final AddQuranBookmarkUseCase? addBookmarkUseCase;

  QuranBookmarkCubit({
    required this.getBookmarksUseCase,
    required this.toggleBookmarkUseCase,
    required this.removeBookmarkUseCase,
    this.addBookmarkUseCase,
  }) : super(QuranBookmarkInitial());

  /// Checks synchronously in O(1) time whether an [AyahId] is bookmarked.
  bool isAyahBookmarked(AyahId ayahId) {
    final currentState = state;
    if (currentState is QuranBookmarkLoaded) {
      return currentState.isBookmarked(ayahId);
    }
    return false;
  }

  /// Retrieves a specific bookmark by [AyahId] if loaded.
  QuranBookmark? getBookmark(AyahId ayahId) {
    final currentState = state;
    if (currentState is QuranBookmarkLoaded) {
      final matches = currentState.bookmarks.where((b) => b.ayahId == ayahId);
      return matches.isNotEmpty ? matches.first : null;
    }
    return null;
  }

  /// Loads all bookmarks from repository and emits [QuranBookmarkLoaded].
  Future<void> loadBookmarks() async {
    emit(QuranBookmarkLoading());
    final result = await getBookmarksUseCase();
    result.fold(
      (failure) => emit(QuranBookmarkError(failure.message)),
      (bookmarks) => emit(QuranBookmarkLoaded(bookmarks)),
    );
  }

  /// Toggles the bookmark status for an Ayah.
  /// Returns `true` if bookmarked (added), `false` if unbookmarked (removed), or `null` on failure.
  Future<bool?> toggleBookmark(
    AyahId ayahId, {
    int? pageNumber,
    String? name,
    int? colorCode,
  }) async {
    final result = await toggleBookmarkUseCase(
      ayahId: ayahId,
      pageNumber: pageNumber,
      name: name,
      colorCode: colorCode,
    );

    return await result.fold(
      (failure) async {
        emit(QuranBookmarkError(failure.message));
        return null;
      },
      (isNowBookmarked) async {
        // Refresh the loaded list to synchronize state
        final refreshed = await getBookmarksUseCase();
        refreshed.fold(
          (failure) => emit(QuranBookmarkError(failure.message)),
          (bookmarks) => emit(QuranBookmarkLoaded(bookmarks)),
        );
        return isNowBookmarked;
      },
    );
  }

  /// Adds or updates a bookmark with custom [name], [colorCode], and optional [createdAt].
  Future<QuranBookmark?> saveBookmark({
    required AyahId ayahId,
    int? pageNumber,
    DateTime? createdAt,
    String? name,
    int? colorCode,
  }) async {
    if (addBookmarkUseCase != null) {
      final result = await addBookmarkUseCase!(
        ayahId: ayahId,
        pageNumber: pageNumber,
        createdAt: createdAt,
        name: name,
        colorCode: colorCode,
      );

      return await result.fold(
        (failure) async {
          emit(QuranBookmarkError(failure.message));
          return null;
        },
        (savedBookmark) async {
          final refreshed = await getBookmarksUseCase();
          refreshed.fold(
            (failure) => emit(QuranBookmarkError(failure.message)),
            (bookmarks) => emit(QuranBookmarkLoaded(bookmarks)),
          );
          return savedBookmark;
        },
      );
    }
    return null;
  }

  /// Restores multiple bookmarks at once (e.g. during Undo) preserving their original [createdAt].
  Future<void> restoreBookmarks(List<QuranBookmark> bookmarks) async {
    if (addBookmarkUseCase != null && bookmarks.isNotEmpty) {
      for (final bookmark in bookmarks) {
        await addBookmarkUseCase!(
          ayahId: bookmark.ayahId,
          pageNumber: bookmark.pageNumber,
          createdAt: bookmark.createdAt,
          name: bookmark.name,
          colorCode: bookmark.colorCode,
        );
      }
      final refreshed = await getBookmarksUseCase();
      refreshed.fold(
        (failure) => emit(QuranBookmarkError(failure.message)),
        (loaded) => emit(QuranBookmarkLoaded(loaded)),
      );
    }
  }

  /// Removes a bookmark directly.
  Future<void> removeBookmark(AyahId ayahId) async {
    final result = await removeBookmarkUseCase(ayahId);
    await result.fold(
      (failure) async => emit(QuranBookmarkError(failure.message)),
      (_) async {
        final refreshed = await getBookmarksUseCase();
        refreshed.fold(
          (failure) => emit(QuranBookmarkError(failure.message)),
          (bookmarks) => emit(QuranBookmarkLoaded(bookmarks)),
        );
      },
    );
  }
}
