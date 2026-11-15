import 'package:bloc/bloc.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/adhan_catalog_validator.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/catalog_draft_manager_service.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/presentation/cubit/adhan_catalog_developer_state.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/repos/adhan_catalog_repository.dart';

/// Cubit responsible for Developer Catalog Management:
/// live inspection, local draft mutation, atomic persistence, and JSON export.
class AdhanCatalogDeveloperCubit extends Cubit<AdhanCatalogDeveloperState> {
  final BaseAdhanCatalogRepository _catalogRepository;
  final CatalogDraftManagerService _draftManager;
  final AdhanCatalogValidator _validator;

  AdhanCatalogDeveloperCubit({
    required BaseAdhanCatalogRepository catalogRepository,
    required CatalogDraftManagerService draftManager,
    AdhanCatalogValidator? validator,
  })  : _catalogRepository = catalogRepository,
        _draftManager = draftManager,
        _validator = validator ?? const AdhanCatalogValidator(),
        super(
          AdhanCatalogDeveloperState(
            draftCatalog: AdhanCatalog(
              schemaVersion: 1,
              generatedAt: DateTime.now().toUtc().toIso8601String(),
              entries: const [],
            ),
          ),
        );

  /// Initializes developer data by loading live catalog and active local draft.
  Future<void> loadDeveloperData() async {
    emit(state.copyWith(isLoading: true, clearNotice: true, clearError: true));

    // 1. Fetch live or cached catalog for inspector
    AdhanCatalog? liveCatalog;
    String sourceLabel = 'غير متوفر';

    try {
      final liveResult = await _catalogRepository.getCatalog(forceRefresh: false);
      liveResult.fold(
        (failure) {
          sourceLabel = 'فشل الاتصال بالخادم';
        },
        (catalog) {
          liveCatalog = catalog;
          sourceLabel = 'متاح (R2 / التخزين المؤقت)';
        },
      );
    } catch (_) {
      sourceLabel = 'خطأ أثناء الاتصال';
    }

    // 2. Load active draft from local storage
    AdhanCatalog? draft;
    bool hasUnsaved = false;

    try {
      draft = await _draftManager.loadDraft();
    } catch (e) {
      emit(
        state.copyWith(
          userError: 'تعذر قراءة ملف المسودة المحفوظ (قد يكون تالفاً): $e',
        ),
      );
    }

    // 3. Fallback: Seed from live catalog if no draft on disk
    if (draft == null) {
      final safeLive = liveCatalog;
      if (safeLive != null && !safeLive.isCompletelyCorrupt) {
        draft = AdhanCatalog(
          schemaVersion: safeLive.schemaVersion,
          generatedAt: safeLive.generatedAt,
          entries: List<AdhanCatalogEntry>.from(safeLive.entries),
        );
      } else {
        draft = AdhanCatalog(
          schemaVersion: 1,
          generatedAt: DateTime.now().toUtc().toIso8601String(),
          entries: const [],
        );
      }
    }

    // 4. Validate initial draft
    final errors = _validator.validateCatalog(draft);

    emit(
      state.copyWith(
        isLoading: false,
        liveCatalog: liveCatalog,
        liveSourceLabel: sourceLabel,
        draftCatalog: draft,
        validationErrors: errors,
        hasUnsavedChanges: hasUnsaved,
      ),
    );
  }

  void switchTab(int index) {
    if (state.activeTab == index) return;
    emit(state.copyWith(activeTab: index));
  }

  void addEntry(AdhanCatalogEntry entry) {
    final updatedEntries = List<AdhanCatalogEntry>.from(state.draftCatalog.entries)..add(entry);
    _updateDraftEntries(updatedEntries);
  }

  void updateEntry(int index, AdhanCatalogEntry entry) {
    if (index < 0 || index >= state.draftCatalog.entries.length) return;
    final updatedEntries = List<AdhanCatalogEntry>.from(state.draftCatalog.entries);
    updatedEntries[index] = entry;
    _updateDraftEntries(updatedEntries);
  }

  void removeEntry(int index) {
    if (index < 0 || index >= state.draftCatalog.entries.length) return;
    final updatedEntries = List<AdhanCatalogEntry>.from(state.draftCatalog.entries)..removeAt(index);
    _updateDraftEntries(updatedEntries);
  }

  void reorderEntries(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.draftCatalog.entries.length) return;
    final updatedEntries = List<AdhanCatalogEntry>.from(state.draftCatalog.entries);
    final item = updatedEntries.removeAt(oldIndex);
    final targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    updatedEntries.insert(targetIndex, item);
    _updateDraftEntries(updatedEntries);
  }

  void updateMetadata({int? schemaVersion, String? generatedAt}) {
    final updatedDraft = AdhanCatalog(
      schemaVersion: schemaVersion ?? state.draftCatalog.schemaVersion,
      generatedAt: generatedAt ?? state.draftCatalog.generatedAt,
      entries: state.draftCatalog.entries,
    );
    final errors = _validator.validateCatalog(updatedDraft);
    emit(
      state.copyWith(
        draftCatalog: updatedDraft,
        validationErrors: errors,
        hasUnsavedChanges: true,
      ),
    );
  }

  void _updateDraftEntries(List<AdhanCatalogEntry> updatedEntries) {
    final updatedDraft = AdhanCatalog(
      schemaVersion: state.draftCatalog.schemaVersion,
      generatedAt: state.draftCatalog.generatedAt,
      entries: updatedEntries,
    );
    final errors = _validator.validateCatalog(updatedDraft);
    emit(
      state.copyWith(
        draftCatalog: updatedDraft,
        validationErrors: errors,
        hasUnsavedChanges: true,
      ),
    );
  }

  /// Atomically saves the current draft to local device storage.
  Future<void> saveDraft() async {
    if (state.isLoading || state.isSaving) return; // Prevent concurrent saves or pre-load saving

    emit(state.copyWith(isSaving: true, clearNotice: true, clearError: true));

    try {
      await _draftManager.saveDraft(state.draftCatalog);
      emit(
        state.copyWith(
          isSaving: false,
          hasUnsavedChanges: false,
          userNotice: 'تم حفظ مسودة الكتالوج بنجاح على الجهاز.',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isSaving: false,
          userError: 'فشل حفظ المسودة: $e',
        ),
      );
    }
  }

  /// Safely resets the draft to the live or cached catalog after explicit user confirmation.
  Future<void> resetDraftToLive({required bool confirmReset}) async {
    if (state.isLoading || state.isResetting) return; // Prevent concurrent resets or pre-load resets
    if (!confirmReset) return;

    emit(state.copyWith(isResetting: true, clearNotice: true, clearError: true));

    try {
      final resetCatalog = await _draftManager.resetDraftToLive(confirmReset: true);
      final errors = _validator.validateCatalog(resetCatalog);

      emit(
        state.copyWith(
          isResetting: false,
          draftCatalog: resetCatalog,
          validationErrors: errors,
          hasUnsavedChanges: false,
          userNotice: 'تم استعادة المسودة بنجاح من أحدث كتالوج صالح.',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isResetting: false,
          userError: 'فشلت استعادة المسودة: $e',
        ),
      );
    }
  }

  /// Exports the current draft to formatted JSON string.
  /// Returns null and sets error if draft fails validation.
  String? exportDraftJson() {
    if (state.isLoading) return null;
    final errors = _validator.validateCatalog(state.draftCatalog);
    if (errors.isNotEmpty) {
      emit(
        state.copyWith(
          validationErrors: errors,
          userError: 'لا يمكن تصدير الكتالوج: توجد ${errors.length} أخطاء تحقق في المخطط.',
          clearNotice: true,
        ),
      );
      return null;
    }

    try {
      final jsonString = _draftManager.exportDraftJson(state.draftCatalog);
      emit(
        state.copyWith(
          userNotice: 'تم تجهيز نص الـ JSON بنجاح للتصدير.',
          clearError: true,
        ),
      );
      return jsonString;
    } catch (e) {
      emit(
        state.copyWith(
          userError: 'خطأ أثناء التصدير: $e',
          clearNotice: true,
        ),
      );
      return null;
    }
  }

  void clearNotice() => emit(state.copyWith(clearNotice: true));
  void clearError() => emit(state.copyWith(clearError: true));
}
