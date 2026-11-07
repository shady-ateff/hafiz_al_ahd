import 'package:equatable/equatable.dart';
import '../../domain/entities/ayah_id.dart';
import '../../domain/entities/quran_tafseer.dart';

/// Base state for [QuranTafseerCubit].
abstract class QuranTafseerState extends Equatable {
  const QuranTafseerState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any Tafseer request has been dispatched.
class QuranTafseerInitial extends QuranTafseerState {
  const QuranTafseerInitial();
}

/// State emitted while loading the Tafseer commentary for a specific [ayahId].
class QuranTafseerLoading extends QuranTafseerState {
  /// The Ayah whose Tafseer is currently being retrieved and parsed.
  final AyahId ayahId;

  const QuranTafseerLoading(this.ayahId);

  @override
  List<Object?> get props => [ayahId];
}

/// State emitted when the Tafseer commentary has loaded and parsed successfully.
class QuranTafseerLoaded extends QuranTafseerState {
  /// The loaded and structured Tafseer entity.
  final QuranTafseer tafseer;

  const QuranTafseerLoaded(this.tafseer);

  /// Convenience getter for the associated [AyahId].
  AyahId get ayahId => tafseer.ayahId;

  @override
  List<Object?> get props => [tafseer];
}

/// State emitted when retrieving or parsing Tafseer commentary fails.
class QuranTafseerError extends QuranTafseerState {
  /// The Ayah for which the request failed.
  final AyahId ayahId;

  /// User-friendly error message.
  final String message;

  const QuranTafseerError({required this.ayahId, required this.message});

  @override
  List<Object?> get props => [ayahId, message];
}
