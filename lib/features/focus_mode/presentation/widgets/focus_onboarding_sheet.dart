import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/app_colors.dart';

class FocusOnboardingSheet extends StatelessWidget {
  const FocusOnboardingSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FocusOnboardingSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.secondaryGold.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Image.asset(
                'assets/images/app_icon_transparent.png',
                width: 36,
                height: 36,
              ),
              const SizedBox(width: 10),
              Text(
                'حافظ على عهدك مع الله',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.lightGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'وضع التركيز يساعدك على صيانة وقت أورادك وأذكارك ومنع التشتت والانشغال بالهاتف حتى تفرغ من عهدك.',
            style: GoogleFonts.cairo(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 18),
          const _OnboardingFeature(
            icon: Icons.shield,
            title: 'حجب ذكي مؤقت للمشتتات',
            subtitle: 'يظهر درع التركيز إذا فتحت تطبيقًا آخر غير مستثنى أثناء جلسة الورد ليذكرك بالعودة.',
          ),
          const _OnboardingFeature(
            icon: Icons.access_time_filled,
            title: 'مواعيد دقيقة غير قابلة للإلغاء التلقائي',
            subtitle: 'الجلسة لا تنتهي بالوقت، بل بإتمامك الفعلي للورد أو قراءة المقدار المحدد من القرآن.',
          ),
          const _OnboardingFeature(
            icon: Icons.phone_in_talk,
            title: 'أمان كامل لمكالمات الطوارئ والنظام',
            subtitle: 'تطبيقات الهاتف والاتصال والشاشة الرئيسية مسموحة دائمًا ويستحيل حجبها تحت أي ظرف.',
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondaryGold,
                foregroundColor: AppColors.darkText,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'فهمت، البدء في ضبط الأوراد',
                style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _OnboardingFeature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _OnboardingFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.secondaryGold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.lightGold, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    height: 1.3,
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
