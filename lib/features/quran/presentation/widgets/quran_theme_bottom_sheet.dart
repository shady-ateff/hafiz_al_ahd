import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/app_colors.dart';
import '../cubit/quran_settings_cubit.dart';
import '../cubit/quran_settings_state.dart';
import '../screens/quran_screen.dart';

class QuranThemeBottomSheet extends StatelessWidget {
  const QuranThemeBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBgColor =
        isDark ? AppColors.primaryBlack : Theme.of(context).scaffoldBackgroundColor;
    final borderColor = AppColors.secondaryGold.withValues(alpha: 0.3);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Container(
            decoration: BoxDecoration(
              color: sheetBgColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: borderColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: Material(
                color: sheetBgColor,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag Handle
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Header with title and close button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.palette_outlined,
                                color: AppColors.secondaryGold,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'مظهر المصحف',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Tajawal',
                                  color: AppColors.secondaryGold,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            color: isDark ? Colors.white70 : Colors.black54,
                            tooltip: 'إغلاق',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(),

                      BlocBuilder<QuranSettingsCubit, QuranSettingsState>(
                        builder: (context, state) {
                          return Column(
                            children: [
                              _buildThemeOption(
                                context: context,
                                title: 'وضع النهار',
                                icon: Icons.wb_sunny_rounded,
                                mode: ThemeMode.light,
                                currentMode: state.quranThemeMode,
                              ),
                              const Divider(),
                              _buildThemeOption(
                                context: context,
                                title: 'وضع الليل',
                                icon: Icons.nights_stay_rounded,
                                mode: ThemeMode.dark,
                                currentMode: state.quranThemeMode,
                              ),
                              const Divider(),
                              _buildThemeOption(
                                context: context,
                                title: 'يتبع النظام (تلقائي)',
                                icon: Icons.brightness_auto_rounded,
                                mode: ThemeMode.system,
                                currentMode: state.quranThemeMode,
                              ),
                              const Divider(),
                              ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.secondaryGold
                                        .withValues(alpha: 0.12),
                                  ),
                                  child: const Icon(
                                    Icons.help_outline_rounded,
                                    color: AppColors.secondaryGold,
                                    size: 20,
                                  ),
                                ),
                                title: const Text(
                                  'تعليمات التفاعل مع المصحف',
                                  style: TextStyle(
                                    fontFamily: 'Tajawal',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  QuranScreen.showInstructionsDialog(context);
                                },
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeOption({
    required BuildContext context,
    required String title,
    required IconData icon,
    required ThemeMode mode,
    required ThemeMode currentMode,
  }) {
    final isSelected = mode == currentMode;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected
              ? AppColors.secondaryGold.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
        child: Icon(
          icon,
          color: isSelected ? AppColors.secondaryGold : Colors.grey,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontFamily: 'Tajawal',
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppColors.secondaryGold : null,
          fontSize: 15,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle_rounded,
              color: AppColors.secondaryGold, size: 22)
          : null,
      onTap: () {
        context.read<QuranSettingsCubit>().setQuranTheme(mode);
        Navigator.pop(context);
      },
    );
  }
}
