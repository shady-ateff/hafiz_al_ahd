import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/DI/service_locator.dart';
import '../../../../core/utils/app_colors.dart';
import '../../domain/entities/focus_schedule.dart';
import '../cubits/focus_app_selection/focus_app_selection_cubit.dart';
import '../cubits/focus_permissions/focus_permissions_cubit.dart';
import '../cubits/focus_permissions/focus_permissions_state.dart';
import '../cubits/focus_settings/focus_settings_cubit.dart';
import '../cubits/focus_settings/focus_settings_state.dart';
import '../widgets/focus_active_session_card.dart';
import '../widgets/focus_onboarding_sheet.dart';
import '../widgets/focus_permission_card.dart';
import '../widgets/focus_schedule_card.dart';
import 'focus_app_selection_screen.dart';

class FocusModeSettingsScreen extends StatelessWidget {
  const FocusModeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<FocusPermissionsCubit>(
          create: (_) => sl<FocusPermissionsCubit>()..checkPermissions(),
        ),
        BlocProvider<FocusSettingsCubit>(
          create: (_) => sl<FocusSettingsCubit>()..loadSettings(),
        ),
      ],
      child: const _FocusModeSettingsView(),
    );
  }
}

class _FocusModeSettingsView extends StatelessWidget {
  const _FocusModeSettingsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'وضع التركيز',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: AppColors.lightGold),
            tooltip: 'دليل وضع التركيز',
            onPressed: () => FocusOnboardingSheet.show(context),
          ),
        ],
      ),
      body: BlocConsumer<FocusSettingsCubit, FocusSettingsState>(
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
        builder: (context, settingsState) {
          final settingsCubit = context.read<FocusSettingsCubit>();
          final permissionsCubit = context.read<FocusPermissionsCubit>();

          return BlocBuilder<FocusPermissionsCubit, FocusPermissionsState>(
            builder: (context, permissionsState) {
              if (settingsState.isLoading && settingsState.schedules.isEmpty) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.lightGold),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  await permissionsCubit.checkPermissions();
                  await settingsCubit.loadSettings();
                },
                color: AppColors.lightGold,
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  children: [
                    // Header Banner with Gold Gradient & Logo
                    _buildHeaderBanner(context),
                    const SizedBox(height: 16),

                    // Master Feature Toggle Switch Card
                    _buildMasterToggleCard(context, settingsState, settingsCubit),
                    const SizedBox(height: 16),

                    // Active session indicator (if running and master enabled)
                    if (settingsState.isFocusModeMasterEnabled && settingsState.hasActiveSession) ...[
                      FocusActiveSessionCard(
                        session: settingsState.activeSession!,
                        onSnooze: () => settingsCubit.snoozeActiveSession(),
                        onCancel: () =>
                            _confirmCancelSession(context, settingsCubit),
                      ),
                    ],

                    // Permissions Readiness Card
                    FocusPermissionCard(
                      state: permissionsState,
                      cubit: permissionsCubit,
                    ),
                    const SizedBox(height: 20),

                    // Scheduled Wards & Settings Section (Disabled/Dimmed when Master Switch is OFF)
                    Opacity(
                      opacity: settingsState.isFocusModeMasterEnabled ? 1.0 : 0.45,
                      child: IgnorePointer(
                        ignoring: !settingsState.isFocusModeMasterEnabled,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Scheduled Wards Section
                            _buildSectionTitle(
                              title: 'أورادك اليومية المجدولة',
                              subtitle: settingsState.isFocusModeMasterEnabled
                                  ? 'يبدأ الدرع تلقائيًا في هذه المواعيد لحمايتك من التشتت'
                                  : 'الميزة معطّلة حالياً - فعّل المفتاح أعلاه لتشغيل الجداول والدرع',
                            ),
                            const SizedBox(height: 10),

                            ...settingsState.schedules.map((schedule) {
                              return FocusScheduleCard(
                                schedule: schedule,
                                onToggle: (enabled) =>
                                    settingsCubit.toggleSchedule(schedule.id, enabled),
                                onEditTime: () =>
                                    _pickScheduleTime(context, schedule, settingsCubit),
                                onEditGoal: schedule.targetQuranGoal != null
                                    ? () => _showQuranGoalDialog(context, schedule, settingsCubit)
                                    : null,
                              );
                            }),

                            const SizedBox(height: 16),

                            // App Exemptions Entry Tile
                            _buildSectionTitle(
                              title: 'الاستثناءات',
                              subtitle: 'حدد التطبيقات المسموحة أثناء جلسة الورد',
                            ),
                            const SizedBox(height: 10),

                            Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.secondaryGold.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.apps,
                                      color: AppColors.lightGold,
                                      size: 24,
                                    ),
                                  ),
                                  title: Text(
                                    'التطبيقات المستثناة أثناء الورد',
                                    style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${settingsState.exemptAppsCount} تطبيق مسموح به حاليًا',
                                    style: GoogleFonts.cairo(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.color,
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: AppColors.secondaryGold,
                                  ),
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            BlocProvider<FocusAppSelectionCubit>(
                                              create: (_) =>
                                                  sl<FocusAppSelectionCubit>(),
                                              child: const FocusAppSelectionScreen(),
                                            ),
                                      ),
                                    );
                                    // Refresh count upon returning
                                    settingsCubit.loadSettings();
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMasterToggleCard(
    BuildContext context,
    FocusSettingsState state,
    FocusSettingsCubit cubit,
  ) {
    final isEnabled = state.isFocusModeMasterEnabled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEnabled
              ? AppColors.secondaryGold.withValues(alpha: 0.6)
              : Colors.white12,
          width: 1.5,
        ),
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: AppColors.secondaryGold.withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isEnabled
                  ? AppColors.secondaryGold.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isEnabled ? Icons.shield_rounded : Icons.shield_outlined,
              color: isEnabled ? AppColors.lightGold : Colors.grey,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تفعيل وضع التركيز',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isEnabled ? AppColors.lightGold : AppColors.lightText,
                  ),
                ),
                Text(
                  isEnabled
                      ? 'الوضع مفعل لحجب المشتتات أثناء الأوراد'
                      : 'الوضع معطّل بالكامل (الافتراضي)',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isEnabled,
            onChanged: (val) => cubit.toggleMasterSwitch(val),
            activeThumbColor: AppColors.lightGold,
            activeTrackColor: AppColors.secondaryGold.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlack,
            AppColors.secondaryGold.withValues(alpha: 0.25),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.secondaryGold.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/images/app_icon_transparent.png',
            width: 52,
            height: 52,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'حافظ على عهدك مع الله',
                  style: GoogleFonts.cairo(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.lightGold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'صيانة وقت أذكارك وأورادك من مشتتات الهاتف حتى تفرغ من وردك.',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: AppColors.silverMarble,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle({required String title, required String subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  void _showQuranGoalDialog(
    BuildContext context,
    FocusSchedule schedule,
    FocusSettingsCubit cubit,
  ) {
    int selectedPages = schedule.targetQuranGoal?.targetValue ?? 2;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF181D24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFBC8C15), width: 1.5),
          ),
          title: Text(
            'تحديد ورد القرآن الكريم',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'اختر عدد الصفحات المطلوبة لإنهاء جلسة التركيز:',
                style: GoogleFonts.cairo(
                  color: const Color(0xFFD1D5DB),
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: selectedPages > 1
                        ? () => setDialogState(() => selectedPages--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline, color: AppColors.secondaryGold, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF241D12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBC8C15)),
                    ),
                    child: Text(
                      '$selectedPages',
                      style: GoogleFonts.cairo(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.lightGold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: selectedPages < 30
                        ? () => setDialogState(() => selectedPages++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline, color: AppColors.secondaryGold, size: 32),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                selectedPages == 1 ? 'صفحة واحدة' : '$selectedPages صفحات',
                style: GoogleFonts.cairo(
                  color: AppColors.lightGold,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'إلغاء',
                style: GoogleFonts.cairo(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                cubit.updateScheduleQuranGoal(schedule.id, selectedPages);
                Navigator.of(ctx).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondaryGold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'حفظ',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickScheduleTime(
    BuildContext context,
    FocusSchedule schedule,
    FocusSettingsCubit cubit,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: schedule.hour, minute: schedule.minute),
      helpText: 'تحديد موعد الورد',
      confirmText: 'تأكيد',
      cancelText: 'إلغاء',
      hourLabelText: 'الساعة',
      minuteLabelText: 'الدقيقة',
      errorInvalidText: 'وقت غير صالح',
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: isDark
                  ? const ColorScheme.dark(
                      primary: AppColors.secondaryGold,
                      onPrimary: Colors.white,
                      surface: AppColors.primaryBlack,
                      onSurface: AppColors.lightText,
                    )
                  : const ColorScheme.light(
                      primary: AppColors.secondaryGold,
                      onPrimary: Colors.white,
                      surface: Color(0xFFFFFDF8),
                      onSurface: Color(0xFF1A1208),
                    ),
            ),
            child: child!,
          ),
        );
      },
    );

    if (pickedTime != null) {
      await cubit.updateScheduleTime(
        schedule.id,
        pickedTime.hour,
        pickedTime.minute,
      );
    }
  }

  void _confirmCancelSession(BuildContext context, FocusSettingsCubit cubit) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.primaryBlack,
        title: Text(
          'إلغاء جلسة التركيز؟',
          style: GoogleFonts.cairo(
            color: AppColors.lightGold,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'هل تريد بالفعل إلغاء الجلسة الحالية وفك الحماية قبل إتمام الورد؟',
          style: GoogleFonts.cairo(color: AppColors.silverMarble),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'متابعة الورد',
              style: GoogleFonts.cairo(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              cubit.cancelActiveSession();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorColor,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'إلغاء الجلسة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
