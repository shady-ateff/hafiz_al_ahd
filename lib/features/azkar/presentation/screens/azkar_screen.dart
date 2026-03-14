import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/helpers/helper_functions.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_text.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/entities/azkar_item.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/cubit/azkar_cubit.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/cubit/azkar_state.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/screens/azkar_list_screen.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/screens/misbaha_screen.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/widgets/category_card.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/widgets/daily_azkar_card.dart';

class AzkarScreen extends StatefulWidget {
  const AzkarScreen({super.key});

  @override
  State<AzkarScreen> createState() => _AzkarScreenState();
}

class _AzkarScreenState extends State<AzkarScreen> {
  // 👈 متغير عشان نحفظ فيه كلمة البحث
  String _searchQuery = '';

  void _navigateToCategory(
    BuildContext context,
    String title,
    List<AzkarItem> azkarList,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AzkarListScreen(categoryTitle: title, azkarList: azkarList),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
          child: BlocBuilder<AzkarCubit, AzkarState>(
            builder: (context, state) {
              if (state is AzkarLoading || state is AzkarInitial) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.secondaryGold,
                  ),
                );
              }

              if (state is AzkarError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.lightGold,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        state.message,
                        style: GoogleFonts.cairo(color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context.read<AzkarCubit>().loadAzkar(),
                        child: Text(
                          'إعادة المحاولة',
                          style: GoogleFonts.cairo(),
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (state is AzkarLoaded) {
                final azkarMap = state.azkarMap;

                // 🔍 لوجيك البحث: تجميع الأذكار اللي بتحتوي على الكلمة
                List<AzkarItem> searchResults = [];
                if (_searchQuery.isNotEmpty) {
                  String normalizedQuery = normalizeArabicText(
                    _searchQuery.trim(),
                  );

                  azkarMap.forEach((category, list) {
                    searchResults.addAll(
                      list.where((item) {
                        // وبننظف نص الذكر نفسه قبل ما نقارنهم ببعض
                        String normalizedItemText = normalizeArabicText(
                          item.text,
                        );
                        return normalizedItemText.contains(normalizedQuery);
                      }),
                    );
                  });
                }

                final categories = [
                  _CategoryConfig(
                    'أذكار بعد السلام من الصلاة المفروضة',
                    'بعد الصلاة',
                    'أدعية ما بعد الفريضة',
                    Icons.brightness_high_rounded,
                  ),
                  _CategoryConfig(
                    'أذكار النوم',
                    'أذكار النوم',
                    'تحصين النفس قبل المنام',
                    CupertinoIcons.moon_fill,
                  ),
                  _CategoryConfig(
                    'أدعية الأنبياء',
                    'أدعية الأنبياء',
                    'من أفضل الأدعية المأثورة',
                    Icons.star_rounded,
                  ),
                  _CategoryConfig(
                    'أدعية قرآنية',
                    'أدعية قرآنية',
                    'مختارات من القرآن الكريم',
                    CupertinoIcons.book_fill,
                  ),
                  _CategoryConfig(
                    'تسابيح',
                    'التسابيح',
                    'كنوز الذكر والتسبيح',
                    CupertinoIcons.infinite,
                  ),
                  _CategoryConfig(
                    'أذكار الاستيقاظ',
                    'أذكار الاستيقاظ',
                    'ابدأ يومك بالذكر',
                    Icons.wb_sunny_rounded,
                  ),
                ];

                return Column(
                  children: [
                    // شريط البحث (ثابت فوق)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 16.0,
                      ),
                      child: TextField(
                        onChanged: (value) {
                          setState(() {
                            _searchQuery =
                                value; // 👈 تحديث الشاشة مع كل حرف يتكتب
                          });
                        },
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
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                        ),
                      ),
                    ),

                    // 👈 عرض نتيجة البحث أو عرض الكروت العادية
                    Expanded(
                      child: _searchQuery.isNotEmpty
                          ? _buildSearchResults(searchResults) // شاشة البحث
                          : _buildMainLayout(
                              context,
                              azkarMap,
                              categories,
                            ), // الشاشة الرئيسية
                    ),
                  ],
                );
              }

              return const SizedBox.shrink();
            },
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

  // ويدجت لعرض نتائج البحث مباشرة
  Widget _buildSearchResults(List<AzkarItem> results) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          'لم يتم العثور على أذكار مطابقة',
          style: GoogleFonts.cairo(color: AppColors.silverMarble, fontSize: 16),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100),
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        return AzkarItemCard(
          item: results[index],
        ); // بنستخدم نفس كارت الذكر اللي عملناه
      },
    );
  }

  // التصميم الأساسي للشاشة (الكروت)
  Widget _buildMainLayout(
    BuildContext context,
    Map<String, List<AzkarItem>> azkarMap,
    List<_CategoryConfig> categories,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 100.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Row(
            children: [
              Expanded(
                child: DailyAzkarCard(
                  title: 'أذكار الصباح',
                  count: '${azkarMap['أذكار الصباح']?.length ?? 0} ذكر',
                  icon: CupertinoIcons.sun_max_fill,
                  onTap: () => _navigateToCategory(
                    context,
                    'أذكار الصباح',
                    azkarMap['أذكار الصباح'] ?? [],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DailyAzkarCard(
                  title: 'أذكار المساء',
                  count: '${azkarMap['أذكار المساء']?.length ?? 0} ذكر',
                  icon: CupertinoIcons.moon_fill,
                  onTap: () => _navigateToCategory(
                    context,
                    'أذكار المساء',
                    azkarMap['أذكار المساء'] ?? [],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
          Text(
            'كافة التصنيفات',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...categories.map((cat) {
            final list = azkarMap[cat.key] ?? [];
            return CategoryCard(
              title: cat.displayTitle,
              subtitle: cat.subtitle,
              countBadge: '${list.length} ذكر',
              icon: cat.icon,
              onTap: list.isNotEmpty
                  ? () => _navigateToCategory(context, cat.displayTitle, list)
                  : null,
            );
          }),
        ],
      ),
    );
  }
}

class _CategoryConfig {
  final String key;
  final String displayTitle;
  final String subtitle;
  final IconData icon;

  const _CategoryConfig(this.key, this.displayTitle, this.subtitle, this.icon);
}
