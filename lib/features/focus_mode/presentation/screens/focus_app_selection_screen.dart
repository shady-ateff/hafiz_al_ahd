import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/app_colors.dart';
import '../cubits/focus_app_selection/focus_app_selection_cubit.dart';
import '../cubits/focus_app_selection/focus_app_selection_state.dart';
import '../widgets/focus_app_tile.dart';

class FocusAppSelectionScreen extends StatefulWidget {
  const FocusAppSelectionScreen({super.key});

  @override
  State<FocusAppSelectionScreen> createState() =>
      _FocusAppSelectionScreenState();
}

class _FocusAppSelectionScreenState extends State<FocusAppSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<FocusAppSelectionCubit>().loadApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'التطبيقات المستثناة أثناء الورد',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: BlocConsumer<FocusAppSelectionCubit, FocusAppSelectionState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: AppColors.errorColor,
              ),
            );
          }
        },
        builder: (context, state) {
          final cubit = context.read<FocusAppSelectionCubit>();

          return Column(
            children: [
              // Search Input
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: cubit.search,
                  style: GoogleFonts.cairo(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'ابحث باسم التطبيق أو الحزمة...',
                    hintStyle: GoogleFonts.cairo(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.secondaryGold,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              cubit.search('');
                            },
                            padding: EdgeInsets.zero,

                            style: IconButton.styleFrom(
                              foregroundColor: AppColors.secondaryGold,
                              padding: EdgeInsets.zero,
                              iconSize: 20,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: AppColors.lightGold,
                                  width: 1.0,
                                ),
                              ),
                            ),
                          )
                        : null,
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.secondaryGold.withOpacity(0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.lightGold),
                    ),
                  ),
                ),
              ),

              // Filter Tabs
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'الكل (${state.allApps.length})',
                      isSelected: state.selectedTab == AppFilterTab.all,
                      onTap: () => cubit.filterByTab(AppFilterTab.all),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'المستثناة (${state.exemptCount})',
                      isSelected: state.selectedTab == AppFilterTab.exempt,
                      onTap: () => cubit.filterByTab(AppFilterTab.exempt),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'السيادية (${state.criticalCount})',
                      isSelected: state.selectedTab == AppFilterTab.critical,
                      onTap: () => cubit.filterByTab(AppFilterTab.critical),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 6),

              // Apps List / Loader
              Expanded(
                child: state.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.lightGold,
                        ),
                      )
                    : state.displayedApps.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 48,
                              color: Colors.grey.withOpacity(0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'لا توجد تطبيقات مطابقة',
                              style: GoogleFonts.cairo(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: state.displayedApps.length,
                        itemBuilder: (context, index) {
                          final app = state.displayedApps[index];
                          return FocusAppTile(
                            app: app,
                            onToggle: (val) =>
                                cubit.toggleExemption(app.packageName, val),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isSelected ? AppColors.goldenGradient : null,
            color: isSelected ? null : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? Colors.transparent : Colors.white12,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected
                  ? AppColors.darkText
                  : Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ),
    );
  }
}
