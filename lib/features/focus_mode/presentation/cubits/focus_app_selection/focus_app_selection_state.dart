import 'package:equatable/equatable.dart';
import '../../../domain/entities/installed_app_info.dart';

enum AppFilterTab {
  all,
  exempt,
  critical,
}

class FocusAppSelectionState extends Equatable {
  final List<InstalledAppInfo> allApps;
  final List<InstalledAppInfo> displayedApps;
  final AppFilterTab selectedTab;
  final String searchQuery;
  final bool isLoading;
  final String? errorMessage;

  const FocusAppSelectionState({
    this.allApps = const [],
    this.displayedApps = const [],
    this.selectedTab = AppFilterTab.all,
    this.searchQuery = '',
    this.isLoading = false,
    this.errorMessage,
  });

  int get exemptCount => allApps.where((a) => a.isExempt).length;
  int get criticalCount => allApps.where((a) => a.isSystemCritical).length;

  FocusAppSelectionState copyWith({
    List<InstalledAppInfo>? allApps,
    List<InstalledAppInfo>? displayedApps,
    AppFilterTab? selectedTab,
    String? searchQuery,
    bool? isLoading,
    String? errorMessage,
  }) {
    return FocusAppSelectionState(
      allApps: allApps ?? this.allApps,
      displayedApps: displayedApps ?? this.displayedApps,
      selectedTab: selectedTab ?? this.selectedTab,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        allApps,
        displayedApps,
        selectedTab,
        searchQuery,
        isLoading,
        errorMessage,
      ];
}
