import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/app_colors.dart';

/// Prominent In-App Disclosure Dialog for `PACKAGE_USAGE_STATS`.
///
/// Complies with Google Play User Data & Permissions policy by explicitly
/// informing the user how and why usage data is evaluated locally before
/// redirecting to system settings.
class FocusProminentDisclosureDialog extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  const FocusProminentDisclosureDialog({
    super.key,
    required this.onConfirm,
    this.onCancel,
  });

  static Future<bool?> show(
    BuildContext context, {
    required VoidCallback onConfirm,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FocusProminentDisclosureDialog(
        onConfirm: onConfirm,
        onCancel: () => Navigator.of(context).pop(false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1208);

    return AlertDialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.secondaryGold.withValues(alpha: 0.3)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.secondaryGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.privacy_tip_outlined,
              color: AppColors.secondaryGold,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'إفصاح إذن الوصول لبيانات الاستخدام',
              style: GoogleFonts.cairo(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'يطلب تطبيق «حافظ العهد» إذن الوصول لبيانات الاستخدام (Usage Access) لتحقيق الغرض الحصري التالي:',
              style: GoogleFonts.cairo(
                color: textColor.withValues(alpha: 0.9),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            _buildBulletPoint(
              context,
              icon: Icons.shield_outlined,
              title: 'حجب المشتتات أثناء الورد:',
              description:
                  'التحقق من التطبيق المفتوح حالياً في واجهة الهاتف أثناء جلسة التركيز النشطة فقط، لإظهار درع الحماية عند فتح تطبيق غير مستثنى.',
              textColor: textColor,
            ),
            const SizedBox(height: 10),
            _buildBulletPoint(
              context,
              icon: Icons.lock_outline,
              title: 'معالجة محلية آمنة 100%:',
              description:
                  'تتم المعالجة بالكامل داخل جهازك دون تسجيل أو جمع أو إرسال أي سجلات تصفح أو إحصائيات استخدام إلى أي خادم خارجي.',
              textColor: textColor,
            ),
            const SizedBox(height: 10),
            _buildBulletPoint(
              context,
              icon: Icons.phonelink_lock_outlined,
              title: 'حماية التطبيقات المهمة:',
              description:
                  'تطبيقات الطوارئ والهاتف والواجهة الرئيسية مستثناة دائماً ولا يتم حجبها تحت أي ظرف.',
              textColor: textColor,
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: () {
            if (onCancel != null) {
              onCancel!();
            } else {
              Navigator.of(context).pop(false);
            }
          },
          child: Text(
            'ليس الآن',
            style: GoogleFonts.cairo(
              color: textColor.withValues(alpha: 0.6),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(true);
            onConfirm();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondaryGold,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          child: Text(
            'متابعة وتفعيل الإذن',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildBulletPoint(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color textColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.secondaryGold),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: GoogleFonts.cairo(
                color: textColor.withValues(alpha: 0.85),
                fontSize: 13,
                height: 1.4,
              ),
              children: [
                TextSpan(
                  text: '$title ',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
