import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/quran_settings_cubit.dart';
import '../cubit/quran_settings_state.dart';

class QuranThemeBottomSheet extends StatelessWidget {
  const QuranThemeBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 5,
            width: 50,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'مظهر المصحف',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFamily: 'Tajawal',
            ),
          ),
          const SizedBox(height: 20),
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
                ],
              );
            },
          ),
          const SizedBox(height: 20),
        ],
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
      leading: Icon(
        icon,
        color: isSelected ? const Color(0xffD4AF37) : Colors.grey,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontFamily: 'Tajawal',
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? const Color(0xffD4AF37) : null,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Color(0xffD4AF37))
          : null,
      onTap: () {
        context.read<QuranSettingsCubit>().setQuranTheme(mode);
        Navigator.pop(context);
      },
    );
  }
}
