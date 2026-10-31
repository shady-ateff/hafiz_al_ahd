import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../domain/entities/quran_line_mapping.dart';
import '../../domain/entities/quran_word.dart';

/// An isolated prototype widget for rendering a single physical Quran line with
/// word-level interactivity while preserving the exact QCF typography and layout.
class QuranInteractiveLinePrototype extends StatefulWidget {
  final QuranLineMapping line;
  final String fontFamily;
  final double dynamicHeight;
  final Color textColor;
  final ValueChanged<QuranWord>? onWordTapped;

  const QuranInteractiveLinePrototype({
    super.key,
    required this.line,
    required this.fontFamily,
    required this.dynamicHeight,
    required this.textColor,
    this.onWordTapped,
  });

  @override
  State<QuranInteractiveLinePrototype> createState() =>
      _QuranInteractiveLinePrototypeState();
}

class _QuranInteractiveLinePrototypeState
    extends State<QuranInteractiveLinePrototype> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _rebuildRecognizers();
  }

  @override
  void didUpdateWidget(QuranInteractiveLinePrototype oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only recreate recognizers if the underlying word list changes
    if (widget.line != oldWidget.line) {
      _rebuildRecognizers();
    }
  }

  void _rebuildRecognizers() {
    _disposeRecognizers();
    for (final word in widget.line.words) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          widget.onWordTapped?.call(word);
        };
      _recognizers.add(recognizer);
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

      // 2. Inter-word space (No recognizer attached -> whitespace ignores tap)
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
