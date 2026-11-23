import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/app_colors.dart';
import '../cubits/focus_permissions/focus_permissions_cubit.dart';
import '../cubits/focus_permissions/focus_permissions_state.dart';
import 'focus_oem_guide_sheet.dart';
import 'focus_prominent_disclosure_dialog.dart';

class FocusPermissionCard extends StatelessWidget {
  final FocusPermissionsState state;
  final FocusPermissionsCubit cubit;

  const FocusPermissionCard({
    super.key,
    required this.state,
    required this.cubit,
  });

  @override
  Widget build(BuildContext context) {
    if (state.isAllGranted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.successColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.successColor.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Icons.verified,
                  color: AppColors.successColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'صلاحيات الحماية مكتملة',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppColors.successColor,
                        ),
                      ),
                      Text(
                        'وضع التركيز جاهز لحجب المشتتات بدقة في مواعيد أورادك',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => FocusOEMGuideSheet.show(context),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: AppColors.secondaryGold,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'إرشادات استقرار الخدمة (شاومي، سامسونج...)',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: AppColors.secondaryGold,
                      // decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF380808), // deep red
            Color(0xFF1E0505), // darker red-black
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE53935).withValues(alpha: 0.7),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE53935).withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFFF5252),
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'تنبيه: يلزم تفعيل الصلاحيات لعمل الدرع',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.refresh,
                  color: Color(0xFFFF8A80),
                  size: 20,
                ),
                onPressed: () => cubit.checkPermissions(),
                tooltip: 'إعادة الفحص',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'لكي يتمكن التطبيق من إطلاق الجلسات في موعدها وحجب التطبيقات الأخرى أثناء الورد، يرجى منح الأذونات التالية:',
            style: GoogleFonts.cairo(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 12),
          _PermissionRow(
            title: 'إمكانية الوصول لبيانات الاستخدام',
            isGranted: state.hasUsageAccess,
            onTap: () {
              FocusProminentDisclosureDialog.show(
                context,
                onConfirm: cubit.openUsageAccessSettings,
              );
            },
          ),
          const Divider(color: Colors.white24, height: 16),
          _PermissionRow(
            title: 'الظهور فوق التطبيقات الأخرى (الدرع)',
            isGranted: state.hasOverlayPermission,
            onTap: cubit.openOverlaySettings,
          ),
          const Divider(color: Colors.white24, height: 16),
          _PermissionRow(
            title: 'المنبهات الدقيقة (بدء الورد في وقته)',
            isGranted: state.canScheduleExactAlarms,
            onTap: cubit.openExactAlarmSettings,
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => FocusOEMGuideSheet.show(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.help_outline,
                  size: 15,
                  color: Color(0xFFFFAB91),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'إرشادات تثبيت الخدمة لأجهزة شاومي وسامسونج وغيرها',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: const Color(0xFFFFAB91),
                      decoration: TextDecoration.underline,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final String title;
  final bool isGranted;
  final VoidCallback onTap;

  const _PermissionRow({
    required this.title,
    required this.isGranted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isGranted ? Icons.check_circle : Icons.error_outline,
          color: isGranted ? AppColors.successColor : AppColors.warningColor,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.cairo(fontSize: 13, color: AppColors.lightText),
          ),
        ),
        if (!isGranted)
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondaryGold,
              foregroundColor: AppColors.darkText,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'تفعيل',
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}
