import 'package:flutter/foundation.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/entities/catalog_validation_error.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';

/// State representation for Developer Catalog Management.
@immutable
class AdhanCatalogDeveloperState {
  final bool isLoading;
  final bool isSaving;
  final bool isResetting;
  final int activeTab; // 0: Live Inspector, 1: Draft Editor
  final AdhanCatalog? liveCatalog;
  final String liveSourceLabel; // 'مباشر (R2)', 'نسخة مخزنة مؤقتاً', 'غير متوفر'
  final AdhanCatalog draftCatalog;
  final List<CatalogValidationError> validationErrors;
  final bool hasUnsavedChanges;
  final String? userNotice;
  final String? userError;

  const AdhanCatalogDeveloperState({
    this.isLoading = false,
    this.isSaving = false,
    this.isResetting = false,
    this.activeTab = 0,
    this.liveCatalog,
    this.liveSourceLabel = 'جاري التحميل...',
    required this.draftCatalog,
    this.validationErrors = const [],
    this.hasUnsavedChanges = false,
    this.userNotice,
    this.userError,
  });

  bool get isValid => validationErrors.isEmpty;

  AdhanCatalogDeveloperState copyWith({
    bool? isLoading,
    bool? isSaving,
    bool? isResetting,
    int? activeTab,
    AdhanCatalog? liveCatalog,
    String? liveSourceLabel,
    AdhanCatalog? draftCatalog,
    List<CatalogValidationError>? validationErrors,
    bool? hasUnsavedChanges,
    String? userNotice,
    String? userError,
    bool clearNotice = false,
    bool clearError = false,
  }) {
    return AdhanCatalogDeveloperState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isResetting: isResetting ?? this.isResetting,
      activeTab: activeTab ?? this.activeTab,
      liveCatalog: liveCatalog ?? this.liveCatalog,
      liveSourceLabel: liveSourceLabel ?? this.liveSourceLabel,
      draftCatalog: draftCatalog ?? this.draftCatalog,
      validationErrors: validationErrors ?? this.validationErrors,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      userNotice: clearNotice ? null : (userNotice ?? this.userNotice),
      userError: clearError ? null : (userError ?? this.userError),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdhanCatalogDeveloperState &&
          runtimeType == other.runtimeType &&
          isLoading == other.isLoading &&
          isSaving == other.isSaving &&
          isResetting == other.isResetting &&
          activeTab == other.activeTab &&
          liveCatalog == other.liveCatalog &&
          liveSourceLabel == other.liveSourceLabel &&
          draftCatalog == other.draftCatalog &&
          listEquals(validationErrors, other.validationErrors) &&
          hasUnsavedChanges == other.hasUnsavedChanges &&
          userNotice == other.userNotice &&
          userError == other.userError;

  @override
  int get hashCode => Object.hash(
        isLoading,
        isSaving,
        isResetting,
        activeTab,
        liveCatalog,
        liveSourceLabel,
        draftCatalog,
        Object.hashAll(validationErrors),
        hasUnsavedChanges,
        userNotice,
        userError,
      );
}

