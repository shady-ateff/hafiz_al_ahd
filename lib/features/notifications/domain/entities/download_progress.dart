import 'package:equatable/equatable.dart';

/// Represents byte-level download progress for a remote audio file.
///
/// Progress strictly reflects actual physical bytes received from the network
/// stream. It is never an estimated ratio based on duration.
class DownloadProgress extends Equatable {
  /// Bytes received from the network so far.
  final int receivedBytes;

  /// Expected total bytes, if known via Content-Length or catalog metadata.
  final int? totalBytes;

  const DownloadProgress({
    required this.receivedBytes,
    this.totalBytes,
  });

  /// Factory for initial zero-byte state.
  factory DownloadProgress.initial({int? totalBytes}) => DownloadProgress(
        receivedBytes: 0,
        totalBytes: totalBytes,
      );

  /// Factory for determinate progress when totalBytes is known and > 0.
  factory DownloadProgress.determinate({
    required int receivedBytes,
    required int totalBytes,
  }) =>
      DownloadProgress(
        receivedBytes: receivedBytes,
        totalBytes: totalBytes,
      );

  /// Factory for indeterminate progress when total size is unknown.
  factory DownloadProgress.indeterminate({required int receivedBytes}) =>
      DownloadProgress(
        receivedBytes: receivedBytes,
        totalBytes: null,
      );

  /// Whether the total size is unknown, requiring indeterminate UI display.
  bool get isIndeterminate => totalBytes == null || totalBytes! <= 0;

  /// Progress fraction clamped between 0.0 and 1.0, or null if indeterminate.
  double? get fraction {
    if (isIndeterminate) return null;
    if (totalBytes! == 0) return 1.0;
    return (receivedBytes / totalBytes!).clamp(0.0, 1.0);
  }

  /// Percentage integer (0 to 100), or null if indeterminate.
  int? get percentage => fraction != null ? (fraction! * 100).toInt() : null;

  @override
  List<Object?> get props => [receivedBytes, totalBytes];

  @override
  String toString() => isIndeterminate
      ? 'DownloadProgress(received: $receivedBytes bytes, indeterminate)'
      : 'DownloadProgress(received: $receivedBytes / $totalBytes bytes, ${(fraction! * 100).toStringAsFixed(1)}%)';
}

