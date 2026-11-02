import 'package:equatable/equatable.dart';
import '../../domain/entities/ayah_id.dart';
import '../../domain/entities/quran_bookmark.dart';

abstract class QuranBookmarkState extends Equatable {
  const QuranBookmarkState();

  @override
  List<Object?> get props => [];
}

class QuranBookmarkInitial extends QuranBookmarkState {}

class QuranBookmarkLoading extends QuranBookmarkState {}

class QuranBookmarkLoaded extends QuranBookmarkState {
  final List<QuranBookmark> bookmarks;
  final Set<AyahId> bookmarkedIds;

  QuranBookmarkLoaded(this.bookmarks)
      : bookmarkedIds = Set.unmodifiable(bookmarks.map((b) => b.ayahId));

  bool isBookmarked(AyahId ayahId) => bookmarkedIds.contains(ayahId);

  @override
  List<Object?> get props => [bookmarks, bookmarkedIds];
}

class QuranBookmarkError extends QuranBookmarkState {
  final String message;

  const QuranBookmarkError(this.message);

  @override
  List<Object?> get props => [message];
}

