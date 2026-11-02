import 'package:equatable/equatable.dart';
import '../../domain/entities/ayah_id.dart';
import '../../domain/entities/quran_page.dart';
import '../../domain/entities/quran_line_mapping.dart';

abstract class QuranState extends Equatable {
  const QuranState();

  @override
  List<Object?> get props => [];
}

class QuranInitial extends QuranState {}

class QuranLoading extends QuranState {}

class QuranDownloadingFonts extends QuranState {
  final double progress;
  const QuranDownloadingFonts(this.progress);

  @override
  List<Object?> get props => [progress];
}

class QuranPageLoaded extends QuranState {
  static const Object _unset = Object();

  final QuranPage page;
  final bool isFontLoaded;
  final List<QuranLineMapping>? lineMappings;
  final AyahId? selectedAyahId;

  const QuranPageLoaded({
    required this.page,
    this.isFontLoaded = false,
    this.lineMappings,
    this.selectedAyahId,
  });

  QuranPageLoaded copyWith({
    QuranPage? page,
    bool? isFontLoaded,
    List<QuranLineMapping>? lineMappings,
    Object? selectedAyahId = _unset,
    bool clearSelectedAyah = false,
  }) {
    final AyahId? resolvedAyahId;
    if (clearSelectedAyah) {
      resolvedAyahId = null;
    } else if (!identical(selectedAyahId, _unset)) {
      resolvedAyahId = selectedAyahId as AyahId?;
    } else {
      resolvedAyahId = this.selectedAyahId;
    }

    return QuranPageLoaded(
      page: page ?? this.page,
      isFontLoaded: isFontLoaded ?? this.isFontLoaded,
      lineMappings: lineMappings ?? this.lineMappings,
      selectedAyahId: resolvedAyahId,
    );
  }

  @override
  List<Object?> get props => [page, isFontLoaded, lineMappings, selectedAyahId];
}

class QuranError extends QuranState {
  final String message;

  const QuranError(this.message);

  @override
  List<Object?> get props => [message];
}
