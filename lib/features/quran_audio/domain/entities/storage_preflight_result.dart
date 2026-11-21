import 'package:equatable/equatable.dart';

/// Represents the status outcome of the full-Quran storage preflight calculation.
enum StoragePreflightStatus {
  /// Available space is strictly greater than required bytes (including 25 MB safety floor).
  sufficient,

  /// Available space is less than required bytes.
  insufficient,

  /// At least one pending Surah track has indeterminate size (null expected bytes).
  indeterminate,
}

/// Represents the evaluated storage feasibility result before starting a full-Quran download queue.
class StoragePreflightResult extends Equatable {
  final StoragePreflightStatus status;
  final int? requiredBytes;
  final int? availableBytes;
  final String? message;

  const StoragePreflightResult({
    required this.status,
    this.requiredBytes,
    this.availableBytes,
    this.message,
  });

  bool get isSufficient => status == StoragePreflightStatus.sufficient;
  bool get isInsufficient => status == StoragePreflightStatus.insufficient;
  bool get isIndeterminate => status == StoragePreflightStatus.indeterminate;

  /// Factory for sufficient storage capacity.
  factory StoragePreflightResult.sufficient({
    required int requiredBytes,
    int? availableBytes,
  }) {
    return StoragePreflightResult(
      status: StoragePreflightStatus.sufficient,
      requiredBytes: requiredBytes,
      availableBytes: availableBytes,
    );
  }

  /// Factory for insufficient storage capacity.
  factory StoragePreflightResult.insufficient({
    required int requiredBytes,
    required int availableBytes,
    String? message,
  }) {
    return StoragePreflightResult(
      status: StoragePreflightStatus.insufficient,
      requiredBytes: requiredBytes,
      availableBytes: availableBytes,
      message: message ?? 'المساحة التخزينية المتاحة غير كافية لتحميل المصحف كاملاً.',
    );
  }

  /// Factory for indeterminate storage sizing (advisory warning dialog).
  factory StoragePreflightResult.indeterminate({
    int? availableBytes,
    String? message,
  }) {
    return StoragePreflightResult(
      status: StoragePreflightStatus.indeterminate,
      availableBytes: availableBytes,
      message: message ??
          'حجم بعض السور غير محدد مسبقًا. لا يمكن حساب المساحة الإجمالية بدقة. هل ترغب في المتابعة؟',
    );
  }

  @override
  List<Object?> get props => [status, requiredBytes, availableBytes, message];
}
