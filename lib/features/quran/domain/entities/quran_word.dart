import 'package:equatable/equatable.dart';
import 'ayah_id.dart';
import 'word_location.dart';

/// Represents an individual word in the Mushaf layout.
class QuranWord extends Equatable {
  final WordLocation location;
  final String uthmaniText;
  final String qcfText;

  QuranWord({
    required this.location,
    required this.uthmaniText,
    required this.qcfText,
  }) {
    if (uthmaniText.trim().isEmpty) {
      throw ArgumentError.value(
        uthmaniText,
        'uthmaniText',
        'uthmaniText cannot be empty',
      );
    }
    if (qcfText.trim().isEmpty) {
      throw ArgumentError.value(
        qcfText,
        'qcfText',
        'qcfText cannot be empty',
      );
    }
  }

  /// Convenience getter for the parent [AyahId].
  AyahId get ayahId => location.ayahId;

  /// Convenience getter for the Surah number.
  int get surahNumber => location.surahNumber;

  /// Convenience getter for the Ayah number.
  int get ayahNumber => location.ayahNumber;

  /// Convenience getter for the 1-based word index within the Ayah.
  int get wordIndex => location.wordIndex;

  @override
  String toString() =>
      'QuranWord($location, uthmani: "$uthmaniText", qcf: "$qcfText")';

  @override
  List<Object?> get props => [location, uthmaniText, qcfText];
}
