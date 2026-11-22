import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/app_colors.dart';
import '../../domain/entities/installed_app_info.dart';

class FocusAppTile extends StatelessWidget {
  final InstalledAppInfo app;
  final ValueChanged<bool> onToggle;

  const FocusAppTile({
    super.key,
    required this.app,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    Uint8List? iconBytes;
    if (app.iconBase64 != null && app.iconBase64!.isNotEmpty) {
      try {
        iconBytes = base64Decode(app.iconBase64!);
      } catch (_) {
        iconBytes = null;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: app.isExempt
              ? AppColors.secondaryGold.withOpacity(0.3)
              : Colors.transparent,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: iconBytes != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    iconBytes,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
                )
              : const Icon(Icons.android, color: AppColors.secondaryGold, size: 28),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                app.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (app.isSystemCritical)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.secondaryGold.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock, size: 10, color: AppColors.lightGold),
                    const SizedBox(width: 3),
                    Text(
                      'سيادي',
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.lightGold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        subtitle: Text(
          app.packageName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.cairo(
            fontSize: 11,
            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
          ),
        ),
        trailing: app.isSystemCritical
            ? Tooltip(
                message: 'تطبيق سيادي للطوارئ والنظام لا يمكن حجبه',
                child: Switch(
                  value: true,
                  onChanged: null, // Disabled / locked
                  activeColor: AppColors.lightGold,
                ),
              )
            : Switch(
                value: app.isExempt,
                onChanged: onToggle,
                activeColor: AppColors.lightGold,
                activeTrackColor: AppColors.secondaryGold.withOpacity(0.5),
              ),
        ),
      ),
    );
  }
}
