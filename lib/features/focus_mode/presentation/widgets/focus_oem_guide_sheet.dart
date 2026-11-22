import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/app_colors.dart';

/// Modal bottom sheet providing OEM-specific guidance for background persistence
/// (Xiaomi/HyperOS, Samsung OneUI, Huawei, Oppo, Vivo, etc.).
class FocusOEMGuideSheet extends StatefulWidget {
  const FocusOEMGuideSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FocusOEMGuideSheet(),
    );
  }

  @override
  State<FocusOEMGuideSheet> createState() => _FocusOEMGuideSheetState();
}

class _FocusOEMGuideSheetState extends State<FocusOEMGuideSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<_OEMGuideData> _guides = const [
    _OEMGuideData(
      brandName: 'شاومي / بوكو',
      systemName: 'MIUI / HyperOS',
      icon: Icons.phone_android,
      steps: [
        'افتح "إعدادات الجهاز" ثم اختر "التطبيقات" > "إدارة التطبيقات".',
        'ابحث عن تطبيق "حافظ العهد".',
        'فعّل خيار "التشغيل التلقائي" (Autostart).',
        'ادخل إلى "موفر البطارية" واختر "لا توجد قيود" (No restrictions).',
        'من شاشة التطبيقات الحديثة (Recent Apps)، اسحب بطاقة التطبيق للأسفل واضغط على رمز القفل لتثبيته في الذاكرة.',
      ],
    ),
    _OEMGuideData(
      brandName: 'سامسونج',
      systemName: 'One UI',
      icon: Icons.smartphone,
      steps: [
        'افتح "الضبط" > "العناية بالجهاز" > "البطارية".',
        'اختر "حدود استخدام الخلفية".',
        'أضف "حافظ العهد" إلى قائمة "التطبيقات التي لا يتم وضعها في وضع السكون أبدًا" (Never sleeping apps).',
        'في معلومات التطبيق، ادخل إلى "البطارية" واختر "غير مقيّد" (Unrestricted).',
      ],
    ),
    _OEMGuideData(
      brandName: 'هواوي / هونر',
      systemName: 'EMUI / MagicOS',
      icon: Icons.phone_iphone,
      steps: [
        'افتح "الإعدادات" > "البطارية" > "تشغيل التطبيقات" (App Launch).',
        'ابحث عن "حافظ العهد" وعطّل خيار "إدارة تلقائية".',
        'فعّل يدويًا كلاً من: "تشغيل تلقائي"، و"تشغيل ثانوي"، و"تشغيل في الخلفية".',
      ],
    ),
    _OEMGuideData(
      brandName: 'أوبو / ريلمي',
      systemName: 'ColorOS / Realme UI',
      icon: Icons.devices,
      steps: [
        'افتح "الإعدادات" > "إدارة التطبيقات" > "حافظ العهد".',
        'ادخل إلى "استهلاك طاقة البطارية" وفعّل "السماح بالنشاط في الخلفية" و"السماح بالتشغيل التلقائي".',
        'ثبّت التطبيق في شاشة المهام الأخيرة عبر رمز القفل.',
      ],
    ),
    _OEMGuideData(
      brandName: 'فيفو',
      systemName: 'Funtouch / OriginOS',
      icon: Icons.mobile_friendly,
      steps: [
        'افتح "الإعدادات" > "البطارية" > "إدارة استهلاك الطاقة في الخلفية".',
        'حدد "حافظ العهد" واختر "السماح باستهلاك طاقة مرتفع في الخلفية".',
        'فعّل "التشغيل التلقائي" من إعدادات الأمان.',
      ],
    ),
    _OEMGuideData(
      brandName: 'أجهزة أخرى',
      systemName: 'Stock Android / Pixel',
      icon: Icons.settings_suggest,
      steps: [
        'افتح "الإعدادات" > "التطبيقات" > "حافظ العهد" > "البطارية".',
        'اختر "غير مقيّد" (Unrestricted) لتفادي إيقاف التنبيهات أثناء وضع الخمول Doze Mode.',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _guides.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1208);

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.battery_alert_outlined,
                    color: AppColors.secondaryGold,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إرشادات تثبيت الخدمة وحماية البطارية',
                        style: GoogleFonts.cairo(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'خطوات مخصصة لمنع النظام من إيقاف درع التركيز أثناء الورد',
                        style: GoogleFonts.cairo(
                          color: textColor.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // TabBar of OEMs
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: AppColors.secondaryGold,
            labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
            unselectedLabelColor: textColor.withValues(alpha: 0.6),
            unselectedLabelStyle: GoogleFonts.cairo(fontSize: 13),
            indicatorColor: AppColors.secondaryGold,
            tabAlignment: TabAlignment.start,
            tabs: _guides.map((g) => Tab(text: g.brandName)).toList(),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _guides.map((guide) {
                return _buildGuideContent(guide, textColor);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideContent(_OEMGuideData guide, Color textColor) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.secondaryGold.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.secondaryGold.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Icon(guide.icon, color: AppColors.secondaryGold, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      guide.brandName,
                      style: GoogleFonts.cairo(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'نظام التشغيل: ${guide.systemName}',
                      style: GoogleFonts.cairo(
                        color: textColor.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'خطوات الضبط الموصى بها:',
          style: GoogleFonts.cairo(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        ...guide.steps.asMap().entries.map((entry) {
          final index = entry.key + 1;
          final step = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppColors.secondaryGold,
                  child: Text(
                    '$index',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    step,
                    style: GoogleFonts.cairo(
                      color: textColor.withValues(alpha: 0.85),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _OEMGuideData {
  final String brandName;
  final String systemName;
  final IconData icon;
  final List<String> steps;

  const _OEMGuideData({
    required this.brandName,
    required this.systemName,
    required this.icon,
    required this.steps,
  });
}
