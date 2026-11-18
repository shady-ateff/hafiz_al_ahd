import 'package:equatable/equatable.dart';

/// Summary report of physical storage reconciliation against the SQLite database registry.
class StorageReconciliationSummary extends Equatable {
  final int discoveredFiles;
  final int missingFiles;
  final int cleanedTempFiles;

  const StorageReconciliationSummary({
    required this.discoveredFiles,
    required this.missingFiles,
    required this.cleanedTempFiles,
  });

  @override
  List<Object?> get props => [discoveredFiles, missingFiles, cleanedTempFiles];
}
