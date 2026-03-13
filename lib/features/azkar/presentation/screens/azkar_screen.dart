import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_text.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/screens/misbaha_screen.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/widgets/category_card.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/widgets/daily_azkar_card.dart';

class AzkarScreen extends StatelessWidget {
  const AzkarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 👈 1. إخفاء الكيبورد لما اليوزر يدوس في أي مكان فاضي
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.amoledBackground,
        appBar: AppBar(
          backgroundColor: AppColors.amoledBackground,
          title: GradientText(
            'الأذكار',
            style: GoogleFonts.cairo(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            // 👈 2. زودنا البادينج تحت لـ 100 عشان الـ FAB ميغطيش على آخر كارت
            padding: const EdgeInsets.only(
              left: 20.0,
              right: 20.0,
              top: 16.0,
              bottom: 100.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search Bar
                TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن ذكر محدد...',
                    hintStyle: GoogleFonts.cairo(
                      color: AppColors.silverMarble.withOpacity(0.5),
                    ),
                    filled: true,
                    fillColor: AppColors.deepBackground,
                    prefixIcon: const Icon(
                      CupertinoIcons.search,
                      color: AppColors.lightGold,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 32),

                // Daily Azkar Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'عرض الكل',
                      style: GoogleFonts.cairo(
                        color: AppColors.lightGold,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'الأذكار اليومية',
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Daily Azkar Cards
                Row(
                  children: [
                    // 👈 3. عكسنا الترتيب هنا عشان "الصباح" يظهر على اليمين في الـ RTL
                    Expanded(
                      child: DailyAzkarCard(
                        title: 'أذكار الصباح',
                        count: '24 ذكر',
                        icon: CupertinoIcons.sun_max_fill,
                        onTap: () {},
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: DailyAzkarCard(
                        title: 'أذكار المساء',
                        count: '30 ذكر',
                        icon: CupertinoIcons.moon_fill,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 36),

                // All Categories Header
                Text(
                  'كافة التصنيفات',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Categories List
                CategoryCard(
                  title: 'بعد الصلاة',
                  subtitle: 'أدعية ما بعد الفريضة',
                  countBadge: '12 ذكر',
                  icon: Icons.brightness_high_rounded,
                  onTap: () {},
                ),
                const CategoryCard(
                  title: 'أذكار النوم',
                  subtitle: 'تحصين النفس قبل المنام',
                  countBadge: '18 ذكر',
                  icon: CupertinoIcons.moon_fill,
                ),
                const CategoryCard(
                  title: 'أدعية السفر',
                  subtitle: 'الحفظ في الحل والترحال',
                  countBadge: '8 أذكار',
                  icon: Icons.map_outlined,
                ),
                const CategoryCard(
                  title: 'أدعية عامة',
                  subtitle: 'مختارات من الأدعية المأثورة',
                  countBadge: '45 ذكر',
                  icon: CupertinoIcons.book_fill,
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const MisbahaScreen()),
            );
          },
          backgroundColor: AppColors.secondaryGold,
          icon: const Icon(
            Icons.fingerprint_rounded,
            color: AppColors.primaryBlack,
          ),
          label: Text(
            'المسبحة',
            style: GoogleFonts.cairo(
              color: AppColors.primaryBlack,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
