import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hafiz_al_ahd/core/theme/cubit/theme_cubit.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_text.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({Key? key}) : super(key: key);

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  Future<void> _launchWhatsApp(String phone) async {
    // Remove '+' and spaces
    final cleanPhone = phone.replaceAll('+', '').replaceAll(' ', '');
    final Uri url = Uri.parse('whatsapp://send?phone=$cleanPhone');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        // Fallback to web whatsapp
        final webUrl = Uri.parse('https://wa.me/$cleanPhone');
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeCubit>().state.isDark;
    final textColor = isDark ? AppColors.silverMarble : const Color(0xFF1A1208);
    final cardColor = isDark
        ? AppColors.deepBackground
        : const Color(0xFFFFF8EC);
    final dividerColor = isDark ? Colors.white12 : const Color(0xFFE8D9B5);

    return Scaffold(
      appBar: AppBar(
        title: GradientText(
          'عن التطبيق',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.secondaryGold),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // App Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.secondaryGold.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryGold.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Image.asset(
                      'assets/images/app_icon_transparent.png',
                      height: 90,
                      width: 90,
                      color: AppColors.secondaryGold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'حافظ العهد - مواقيت وأذكار',
                    style: GoogleFonts.cairo(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'تطبيق "حافظ العهد" هو رفيقك اليومي للحفاظ على صلواتك وأذكارك بكل سهولة وفي واجهة عصرية ومريحة للعين (تدعم الوضع الليلي والنهاري).',
                    style: GoogleFonts.cairo(
                      color: textColor.withOpacity(0.8),
                      fontSize: 14,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Features
            Text(
              'أهم المميزات:',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryGold,
              ),
            ),
            const SizedBox(height: 12),
            _buildFeatureItem(
              'مواقيت الصلاة الدقيقة',
              'حساب دقيق لأوقات الصلاة بناءً على موقعك الجغرافي.',
              Icons.access_time_filled_rounded,
              textColor,
            ),
            _buildFeatureItem(
              'القرآن الكريم',
              'مصحف المدينة المنورة مطابق تماماً للنسخة الورقية بخط واضح مع دعم القراءة الليلية.',
              Icons.auto_stories_rounded,
              textColor,
            ),
            _buildFeatureItem(
              'إشعارات وتنبيهات',
              'تنبيهات مخصصة لكل صلاة.',
              Icons.notifications_active_rounded,
              textColor,
            ),
            _buildFeatureItem(
              'اتجاه القبلة',
              'بوصلة دقيقة وسريعة لتحديد اتجاه القبلة أينما كنت.',
              Icons.explore_rounded,
              textColor,
            ),
            _buildFeatureItem(
              'الأذكار اليومية',
              'حصن المسلم من أذكار الصباح والمساء، وأذكار ما بعد الصلاة.',
              Icons.menu_book_rounded,
              textColor,
            ),
            _buildFeatureItem(
              'تصميم عصري',
              'واجهة مستخدم (UI/UX) نظيفة وسريعة توفر لك تجربة استخدام استثنائية.',
              Icons.palette_rounded,
              textColor,
            ),

            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.secondaryGold.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.secondaryGold.withOpacity(0.2),
                ),
              ),
              child: Text(
                'التطبيق مجاني بالكامل، ولا يحتوي على إعلانات مزعجة، صُمم ليكون صدقة جارية وعملاً خالصاً. نسألكم الدعاء.',
                style: GoogleFonts.cairo(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),

            // Details info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.secondaryGold.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  _buildDetailRow(
                    'المطور',
                    'Shady Atef',
                    textColor,
                    dividerColor,
                  ),
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final version = snapshot.hasData
                          ? snapshot.data!.version
                          : '...';
                      return _buildDetailRow(
                        'الإصدار',
                        version,
                        textColor,
                        dividerColor,
                      );
                    },
                  ),
                  _buildDetailRow(
                    'تاريخ الإصدار',
                    '06/04/2026',
                    textColor,
                    dividerColor,
                  ),
                  _buildDetailRow(
                    'تاريخ التحديث',
                    '07/09/2026',
                    textColor,
                    dividerColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Developer Links
            Text(
              'تواصل مع المطور',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryGold,
              ),
            ),
            const SizedBox(height: 12),

            // Website
            InkWell(
              onTap: () => _launchUrl('https://shadyatef.com'),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.secondaryGold.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.language_rounded,
                      color: AppColors.secondaryGold,
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الموقع الإلكتروني',
                            style: GoogleFonts.cairo(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'shadyatef.com',
                            style: GoogleFonts.cairo(
                              color: textColor.withOpacity(0.6),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: AppColors.secondaryGold,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // WhatsApp
            InkWell(
              onTap: () => _launchWhatsApp('+201220349096'),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.secondaryGold.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.support_agent_rounded,
                      color: AppColors.secondaryGold,
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'للشكاوي والمقترحات (واتساب)',
                            style: GoogleFonts.cairo(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: AppColors.secondaryGold,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(
    String title,
    String desc,
    IconData icon,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.secondaryGold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  desc,
                  style: GoogleFonts.cairo(
                    color: textColor.withOpacity(0.7),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String title,
    String value,
    Color textColor,
    Color dividerColor, {
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.cairo(
                  color: textColor.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.cairo(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(color: dividerColor, height: 1),
      ],
    );
  }
}
