import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/focus_mode_poc/data/focus_poc_channel.dart';

class PoCStatusCard extends StatelessWidget {
  final FocusPoCPermissionStatus permissions;
  final bool isServiceRunning;
  final String currentApp;
  final bool isAppExempted;
  final VoidCallback onRefreshPermissions;
  final VoidCallback onOpenUsageSettings;
  final VoidCallback onOpenOverlaySettings;
  final VoidCallback onOpenExactAlarmSettings;

  const PoCStatusCard({
    super.key,
    required this.permissions,
    required this.isServiceRunning,
    required this.currentApp,
    required this.isAppExempted,
    required this.onRefreshPermissions,
    required this.onOpenUsageSettings,
    required this.onOpenOverlaySettings,
    required this.onOpenExactAlarmSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E232A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isServiceRunning ? AppColors.secondaryGold : Colors.white12,
          width: isServiceRunning ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isServiceRunning ? Colors.greenAccent : Colors.redAccent,
                      boxShadow: isServiceRunning
                          ? [
                              BoxShadow(
                                color: Colors.greenAccent.withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              )
                            ]
                          : [],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isServiceRunning ? 'الخدمة نشطة (Monitoring)' : 'الخدمة متوقفة (Idle)',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppColors.secondaryGold),
                onPressed: onRefreshPermissions,
                tooltip: 'تحديث الحالة',
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 24),
          Text(
            'حالة الصلاحيات الأساسية:',
            style: GoogleFonts.cairo(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          _buildPermissionRow(
            title: 'الوصول لبيانات الاستخدام (Usage Access)',
            isGranted: permissions.hasUsageAccess,
            onTap: onOpenUsageSettings,
          ),
          const SizedBox(height: 8),
          _buildPermissionRow(
            title: 'الظهور فوق التطبيقات (Display Over Apps)',
            isGranted: permissions.hasOverlayPermission,
            onTap: onOpenOverlaySettings,
          ),
          const SizedBox(height: 8),
          _buildPermissionRow(
            title: 'المنبهات الدقيقة (Alarms & Reminders)',
            isGranted: permissions.canScheduleExactAlarms,
            onTap: onOpenExactAlarmSettings,
          ),
          const Divider(color: Colors.white12, height: 24),
          Row(
            children: [
              const Icon(Icons.apps_rounded, color: AppColors.secondaryGold, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'التطبيق النشط حالياً:',
                      style: GoogleFonts.cairo(color: Colors.white54, fontSize: 11),
                    ),
                    Text(
                      currentApp.isEmpty ? 'جاري الفحص...' : currentApp,
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isAppExempted
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isAppExempted ? Colors.green : Colors.orange,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  isAppExempted ? 'مستثنى (آمن)' : 'مقيّد (يُحظر)',
                  style: GoogleFonts.cairo(
                    color: isAppExempted ? Colors.greenAccent : Colors.orangeAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionRow({
    required String title,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    return Row(
      children: [
        Icon(
          isGranted ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: isGranted ? Colors.greenAccent : Colors.redAccent,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.cairo(
              color: isGranted ? Colors.white : Colors.white60,
              fontSize: 12,
            ),
          ),
        ),
        if (!isGranted)
          InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.secondaryGold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.secondaryGold, width: 0.8),
              ),
              child: Text(
                'تفعيل',
                style: GoogleFonts.cairo(
                  color: AppColors.secondaryGold,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
