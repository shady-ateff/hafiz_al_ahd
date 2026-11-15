import 'package:flutter/foundation.dart';

/// Base class for all storage deletion and eviction failures.
@immutable
sealed class StorageDeletionFailure {
  final String message;
  const StorageDeletionFailure(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when attempting to delete an audio file currently assigned to one or more prayer alarms.
class StorageDeletionActiveAlarmFailure extends StorageDeletionFailure {
  final List<String> prayerNames;
  StorageDeletionActiveAlarmFailure(this.prayerNames)
      : super('لا يمكن حذف الملف لأنه مستخدم في منبه: ${prayerNames.join('، ')}');
}

/// Thrown when attempting to delete a protected file (user custom audio or unmanaged).
class StorageDeletionProtectedFailure extends StorageDeletionFailure {
  const StorageDeletionProtectedFailure(String reason)
      : super('الملف محمي من الحذف: $reason');
}

/// Thrown when path traversal, symlink escape, or path outside storage root is detected.
class StorageDeletionSecurityFailure extends StorageDeletionFailure {
  const StorageDeletionSecurityFailure([super.message = 'مسار الملف غير آمن أو خارج مجلد الأصوات المعتمد']);
}

/// Thrown when the target file does not exist on disk.
class StorageDeletionNotFoundFailure extends StorageDeletionFailure {
  const StorageDeletionNotFoundFailure([super.message = 'الملف المطلوب حذفه غير موجود']);
}

/// Thrown when an underlying I/O or filesystem error occurs during deletion.
class StorageDeletionIoFailure extends StorageDeletionFailure {
  const StorageDeletionIoFailure(String message)
      : super('خطأ أثناء حذف الملف من التخزين المحلي: $message');
}

/// Summary report after executing a temporary storage cleanup sweep.
@immutable
class StorageCleanupSummary {
  final int deletedCount;
  final int freedBytes;
  final List<String> deletedFileNames;

  const StorageCleanupSummary({
    required this.deletedCount,
    required this.freedBytes,
    required this.deletedFileNames,
  });

  static const StorageCleanupSummary zero = StorageCleanupSummary(
    deletedCount: 0,
    freedBytes: 0,
    deletedFileNames: [],
  );

  @override
  String toString() =>
      'StorageCleanupSummary(deleted: $deletedCount, freed: $freedBytes bytes)';
}
