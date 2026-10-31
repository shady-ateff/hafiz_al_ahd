import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../domain/entities/quran_line_mapping.dart';
import '../../domain/entities/quran_word.dart';

/// Renders a single physical Quran line with word-level interactivity while
/// preserving the exact QCF typography, layout scaling, and font metrics.
class QuranInteractiveLineWidget extends StatefulWidget {
  final QuranLineMapping line;
  final String fontFamily;
  final double dynamicHeight;
  final Color textColor;
  final ValueChanged<QuranWord>? onWordTapped;
  final ValueChanged<QuranWord>? onWordLongPressed;

  const QuranInteractiveLineWidget({
    super.key,
    required this.line,
    required this.fontFamily,
    required this.dynamicHeight,
    required this.textColor,
    this.onWordTapped,
    this.onWordLongPressed,
  });

  @override
  State<QuranInteractiveLineWidget> createState() =>
      _QuranInteractiveLineWidgetState();
}

class _QuranInteractiveLineWidgetState
    extends State<QuranInteractiveLineWidget> {
  final List<GestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _rebuildRecognizers();
  }

  @override
  void didUpdateWidget(QuranInteractiveLineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.line != oldWidget.line ||
        widget.onWordTapped != oldWidget.onWordTapped ||
        widget.onWordLongPressed != oldWidget.onWordLongPressed) {
      _rebuildRecognizers();
    }
  }

  void _rebuildRecognizers() {
    _disposeRecognizers();
    for (final word in widget.line.words) {
      if (widget.onWordLongPressed != null) {
        final recognizer = LongPressGestureRecognizer()
          ..onLongPress = () {
            widget.onWordLongPressed?.call(word);
          };
        _recognizers.add(recognizer);
      } else if (widget.onWordTapped != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            widget.onWordTapped?.call(word);
          };
        _recognizers.add(recognizer);
      }
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rootStyle = TextStyle(
      fontFamily: widget.fontFamily,
      fontSize: 40,
      color: widget.textColor,
      height: widget.dynamicHeight,
      wordSpacing: -3.5,
      letterSpacing: -0.5,
    );

    final words = widget.line.words;
    final List<InlineSpan> spans = [];

    for (int i = 0; i < words.length; i++) {
      // 1. Interactive Word Span
      spans.add(
        TextSpan(
          text: words[i].qcfText,
          recognizer: i < _recognizers.length ? _recognizers[i] : null,
        ),
      );

      // 2. Inter-word space (No recognizer attached -> whitespace ignores interaction)
      if (i < words.length - 1) {
        spans.add(const TextSpan(text: ' '));
      }
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: RichText(
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        text: TextSpan(
          style: rootStyle,
          children: spans,
        ),
      ),
    );
  }
}
