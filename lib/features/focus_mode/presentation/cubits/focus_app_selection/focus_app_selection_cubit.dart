import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/installed_app_info.dart';
import '../../../domain/services/focus_app_manager_coordinator.dart';
import 'focus_app_selection_state.dart';

class FocusAppSelectionCubit extends Cubit<FocusAppSelectionState> {
  final FocusAppManagerCoordinator appCoordinator;

  FocusAppSelectionCubit({required this.appCoordinator})
      : super(const FocusAppSelectionState());

  Future<void> loadApps() async {
    emit(state.copyWith(isLoading: true));
    try {
      final apps = await appCoordinator.getAppsWithExemptions();
      emit(state.copyWith(
        allApps: apps,
        displayedApps: _filterApps(apps, state.selectedTab, state.searchQuery),
        isLoading: false,
      ));
    } catch (_) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'فشل استرجاع قائمة تطبيقات الهاتف',
      ));
    }
  }

  void search(String query) {
    final filtered = _filterApps(state.allApps, state.selectedTab, query);
    emit(state.copyWith(
      searchQuery: query,
      displayedApps: filtered,
    ));
  }

  void filterByTab(AppFilterTab tab) {
    final filtered = _filterApps(state.allApps, tab, state.searchQuery);
    emit(state.copyWith(
      selectedTab: tab,
      displayedApps: filtered,
    ));
  }

  Future<void> toggleExemption(String packageName, bool isExempt) async {
    try {
      final app = state.allApps.firstWhere((a) => a.packageName == packageName);
      if (app.isSystemCritical) return;

      await appCoordinator.toggleAppExemption(
        packageName,
        isExempt,
        appName: app.appName,
      );

      final updatedAll = state.allApps.map((a) {
        if (a.packageName == packageName) {
          return a.copyWith(isExempt: isExempt);
        }
        return a;
      }).toList();

      emit(state.copyWith(
        allApps: updatedAll,
        displayedApps: _filterApps(updatedAll, state.selectedTab, state.searchQuery),
      ));
    } catch (_) {
      emit(state.copyWith(errorMessage: 'تعذر تعديل استثناء التطبيق'));
    }
  }

  List<InstalledAppInfo> _filterApps(
    List<InstalledAppInfo> apps,
    AppFilterTab tab,
    String query,
  ) {
    var result = apps;

    switch (tab) {
      case AppFilterTab.all:
        break;
      case AppFilterTab.exempt:
        result = result.where((a) => a.isExempt).toList();
        break;
      case AppFilterTab.critical:
        result = result.where((a) => a.isSystemCritical).toList();
        break;
    }

    if (query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      result = result
          .where((a) =>
              a.appName.toLowerCase().contains(q) ||
              a.packageName.toLowerCase().contains(q))
          .toList();
    }

    return result;
  }
}
