import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/helpers/helper_functions.dart';
import 'package:hafiz_al_ahd/core/theme/theme_helper.dart'; // 👈 الـ Helper
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_text.dart';
import 'package:hafiz_al_ahd/features/azkar/domain/entities/azkar_item.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/cubit/azkar_cubit.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/cubit/azkar_state.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/screens/azkar_list_screen.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/screens/misbaha_screen.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/widgets/category_card.dart';
import 'package:hafiz_al_ahd/features/azkar/presentation/widgets/daily_azkar_card.dart';
import 'package:hafiz_al_ahd/features/gamification/presentation/screens/profile_screen.dart';
import 'package:hafiz_al_ahd/features/gamification/presentation/cubit/gamification_cubit.dart';
import 'package:hafiz_al_ahd/features/gamification/presentation/cubit/gamification_state.dart';

class AzkarScreen extends StatefulWidget {
  const AzkarScreen({super.key});

  @override
  State<AzkarScreen> createState() => _AzkarScreenState();
}

class _AzkarScreenState extends State<AzkarScreen> {
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
        backgroundColor: context.screenBg,
        appBar: AppBar(
          backgroundColor: context.screenBg,
          elevation: 0,
          title: GradientText(
            'الأذكار',
            style: GoogleFonts.cairo(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(Icons.workspace_premium_rounded, color: AppColors.secondaryGold, size: 30),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
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
                        style: GoogleFonts.cairo(
                          color: context.primaryText,
                        ), // 👈 لون دايناميك بدل الأبيض
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

                List<AzkarItem> searchResults = [];
                if (_searchQuery.isNotEmpty) {
                  String normalizedQuery = normalizeArabicText(
                    _searchQuery.trim(),
                  );

                  azkarMap.forEach((category, list) {
                    searchResults.addAll(
                      list.where((item) {
                        String normalizedItemText = normalizeArabicText(
                          item.text,
                        );
                        return normalizedItemText.contains(normalizedQuery);
                      }),
                    );
                  });
                }

                final categories = [
                  const _CategoryConfig(
                    'أذكار بعد السلام من الصلاة المفروضة',
                    'بعد الصلاة',
                    'أدعية ما بعد الفريضة',
                    Icons.brightness_high_rounded,
                  ),
                  const _CategoryConfig(
                    'أذكار النوم',
                    'أذكار النوم',
                    'تحصين النفس قبل المنام',
                    CupertinoIcons.moon_fill,
                  ),
                  const _CategoryConfig(
                    'أدعية الأنبياء',
                    'أدعية الأنبياء',
                    'من أفضل الأدعية المأثورة',
                    Icons.star_rounded,
                  ),
                  const _CategoryConfig(
                    'أدعية قرآنية',
                    'أدعية قرآنية',
                    'مختارات من القرآن الكريم',
                    CupertinoIcons.book_fill,
                  ),
                  const _CategoryConfig(
                    'تسابيح',
                    'التسابيح',
                    'كنوز الذكر والتسبيح',
                    CupertinoIcons.infinite,
                  ),
                  const _CategoryConfig(
                    'أذكار الاستيقاظ',
                    'أذكار الاستيقاظ',
                    'ابدأ يومك بالذكر',
                    Icons.wb_sunny_rounded,
                  ),
                ];

                return Column(
                  children: [
                    BlocBuilder<GamificationCubit, GamificationState>(
                      builder: (context, gamificationState) {
                        if (gamificationState is GamificationLoaded || gamificationState is LevelUpState || gamificationState is AchievementUnlockedState) {
                          dynamic stateObj = gamificationState;
                          int level = stateObj.profile.level;
                          int xp = stateObj.profile.xp;
                          int nextLevelXp = level * 100;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                            child: Row(
                              children: [
                                Icon(Icons.star_rounded, color: AppColors.secondaryGold),
                                const SizedBox(width: 8),
                                Text(
                                  'المستوى $level',
                                  style: GoogleFonts.cairo(
                                    color: context.primaryText,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: LinearProgressIndicator(
                                      value: xp / nextLevelXp,
                                      backgroundColor: AppColors.secondaryGold.withOpacity(0.2),
                                      color: AppColors.secondaryGold,
                                      minHeight: 6,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$xp XP',
                                  style: GoogleFonts.cairo(
                                    color: AppColors.secondaryGold,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 16.0,
                      ),
                      child: TextField(
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                        style: TextStyle(color: context.primaryText),
                        decoration: InputDecoration(
                          hintText: 'ابحث عن ذكر محدد...',
                          hintStyle: GoogleFonts.cairo(
                            color: context.secondaryText,
                          ),
                          filled: true,
                          fillColor: context.cardBg,
                          prefixIcon: const Icon(
                            CupertinoIcons.search,
                            color: AppColors.secondaryGold,
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

                    Expanded(
                      child: _searchQuery.isNotEmpty
                          ? _buildSearchResults(searchResults)
                          : _buildMainLayout(context, azkarMap, categories),
                    ),
                  ],
                );
              }

              return const SizedBox.shrink();
            },
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'misbaha_fab',
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

  Widget _buildSearchResults(List<AzkarItem> results) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          'لم يتم العثور على أذكار مطابقة',
          style: GoogleFonts.cairo(
            color: context.secondaryText,
            fontSize: 16,
          ), // 👈 لون دايناميك
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100),
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        return AzkarItemCard(item: results[index]);
      },
    );
  }

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
                  color: AppColors.secondaryGold,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'الأذكار اليومية',
                style: GoogleFonts.cairo(
                  color: context.primaryText, // 👈 لون دايناميك بدل الأبيض
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
              color: context.primaryText, // 👈 لون دايناميك بدل الأبيض
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
