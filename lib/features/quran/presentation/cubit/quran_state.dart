import 'package:equatable/equatable.dart';
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
  final QuranPage page;
  final bool isFontLoaded;
  final List<QuranLineMapping>? lineMappings;

  const QuranPageLoaded({
    required this.page,
    this.isFontLoaded = false,
    this.lineMappings,
  });

  @override
  List<Object?> get props => [page, isFontLoaded, lineMappings];
}

class QuranError extends QuranState {
  final String message;

  const QuranError(this.message);

  @override
  List<Object?> get props => [message];
}
