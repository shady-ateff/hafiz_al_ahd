import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../domain/entities/ayah_id.dart';
import '../../domain/entities/quran_line_mapping.dart';
import '../../domain/entities/quran_word.dart';

/// Renders a single physical Quran line with word-level interactivity while
/// preserving the exact QCF typography, layout scaling, and font metrics.
class QuranInteractiveLineWidget extends StatefulWidget {
  final QuranLineMapping line;
  final String fontFamily;
  final double dynamicHeight;
  final Color textColor;
  final AyahId? selectedAyahId;
  final Color? highlightColor;
  final ValueChanged<QuranWord>? onWordTapped;
  final ValueChanged<QuranWord>? onWordLongPressed;

  const QuranInteractiveLineWidget({
    super.key,
    required this.line,
    required this.fontFamily,
    required this.dynamicHeight,
    required this.textColor,
    this.selectedAyahId,
    this.highlightColor,
    this.onWordTapped,
    this.onWordLongPressed,
  });

  @override
  State<QuranInteractiveLineWidget> createState() =>
      _QuranInteractiveLineWidgetState();
}

class _QuranInteractiveLineWidgetState
    extends State<QuranInteractiveLineWidget> {
  final List<GestureRecognizer?> _recognizers = [];

  bool _containsAyah(AyahId? id) {
    if (id == null) return false;
    for (final w in widget.line.words) {
      if (w.ayahId == id) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _syncRecognizers();
  }

  @override
  void didUpdateWidget(QuranInteractiveLineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final lineChanged = widget.line != oldWidget.line;
    final callbacksChanged = widget.onWordTapped != oldWidget.onWordTapped ||
        widget.onWordLongPressed != oldWidget.onWordLongPressed;
    final selectionAffectsThisLine =
        widget.selectedAyahId != oldWidget.selectedAyahId &&
            (_containsAyah(widget.selectedAyahId) ||
                _containsAyah(oldWidget.selectedAyahId));

    if (lineChanged || callbacksChanged || selectionAffectsThisLine) {
      _syncRecognizers();
    }
  }

  /// Synchronizes gesture recognizers in-place to avoid recreation overhead.
  /// Recognizers for words whose selection state did not change are preserved as-is.
  void _syncRecognizers() {
    final words = widget.line.words;
    final selectedId = widget.selectedAyahId;

    while (_recognizers.length < words.length) {
      _recognizers.add(null);
    }
    while (_recognizers.length > words.length) {
      _recognizers.removeLast()?.dispose();
    }

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final isSelected = selectedId != null && word.ayahId == selectedId;
      final current = _recognizers[i];

      if (isSelected) {
        if (current is QuranWordTapGestureRecognizer) {
          // Re-use existing recognizer and update callbacks in-place
          current.onTap = widget.onWordTapped != null
              ? () => widget.onWordTapped?.call(word)
              : null;
          current.onLongPress = widget.onWordLongPressed != null
              ? () => widget.onWordLongPressed?.call(word)
              : null;
        } else {
          current?.dispose();
          _recognizers[i] = QuranWordTapGestureRecognizer(
            onTap: widget.onWordTapped != null
                ? () => widget.onWordTapped?.call(word)
                : null,
            onLongPress: widget.onWordLongPressed != null
                ? () => widget.onWordLongPressed?.call(word)
                : null,
          );
        }
      } else {
        if (widget.onWordLongPressed != null) {
          if (current is LongPressGestureRecognizer &&
              current is! QuranWordTapGestureRecognizer) {
            // Re-use existing recognizer and update callback in-place
            current.onLongPress = () {
              widget.onWordLongPressed?.call(word);
            };
          } else {
            current?.dispose();
            _recognizers[i] = LongPressGestureRecognizer()
              ..onLongPress = () {
                widget.onWordLongPressed?.call(word);
              };
          }
        } else {
          current?.dispose();
          _recognizers[i] = null;
        }
      }
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer?.dispose();
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
    final selectedId = widget.selectedAyahId;
    final highlight = widget.highlightColor;

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final isSelected = selectedId != null && word.ayahId == selectedId;
      final wordStyle = (isSelected && highlight != null)
          ? TextStyle(backgroundColor: highlight)
          : null;

      // 1. Interactive Word Span
      spans.add(
        TextSpan(
          text: word.qcfText,
          style: wordStyle,
          recognizer: i < _recognizers.length ? _recognizers[i] : null,
        ),
      );

      // 2. Inter-word space (highlighted only if both this word and the next word belong to the selected Ayah)
      if (i < words.length - 1) {
        final nextWord = words[i + 1];
        final nextIsSelected =
            selectedId != null && nextWord.ayahId == selectedId;
        final spaceStyle = (isSelected && nextIsSelected && highlight != null)
            ? TextStyle(backgroundColor: highlight)
            : null;

        spans.add(
          TextSpan(
            text: ' ',
            style: spaceStyle,
          ),
        );
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

/// Recognizer for selected Quran words that extends [TapGestureRecognizer] so that Flutter's
/// [RenderParagraph.assembleSemanticsNode] natively recognizes it without throwing an assertion error.
/// It dispatches [onTap] on quick tap release, and [onLongPress] if held for [kLongPressTimeout].
class QuranWordTapGestureRecognizer extends TapGestureRecognizer {
  VoidCallback? onLongPress;
  Timer? _longPressTimer;
  bool _longPressFired = false;

  QuranWordTapGestureRecognizer({
    VoidCallback? onTap,
    this.onLongPress,
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
  }) {
    this.onTap = onTap;
  }

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (onLongPress != null && (event.buttons & kPrimaryButton != 0)) {
      return (supportedDevices == null || supportedDevices!.contains(event.kind)) &&
          allowedButtonsFilter(event.buttons);
    }
    return super.isPointerAllowed(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _longPressFired = false;
    _longPressTimer?.cancel();
    if (onLongPress != null) {
      _longPressTimer = Timer(kLongPressTimeout, () {
        _longPressFired = true;
        resolve(GestureDisposition.accepted);
        onLongPress?.call();
      });
    }
    super.addAllowedPointer(event);
  }

  @override
  void handleTapUp({required PointerDownEvent down, required PointerUpEvent up}) {
    final wasLongPress = _longPressFired;
    _longPressTimer?.cancel();
    _longPressFired = false;
    if (!wasLongPress) {
      super.handleTapUp(down: down, up: up);
    }
  }

  @override
  void handleTapCancel({
    required PointerDownEvent down,
    PointerCancelEvent? cancel,
    required String reason,
  }) {
    _longPressTimer?.cancel();
    _longPressFired = false;
    super.handleTapCancel(down: down, cancel: cancel, reason: reason);
  }

  @override
  void rejectGesture(int pointer) {
    _longPressTimer?.cancel();
    _longPressFired = false;
    super.rejectGesture(pointer);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  String get debugDescription => 'QuranWordTapGestureRecognizer';
}
