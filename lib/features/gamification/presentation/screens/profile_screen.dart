import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/theme/theme_helper.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/widgets/gradient_text.dart';
import 'package:hafiz_al_ahd/features/gamification/presentation/cubit/gamification_cubit.dart';
import 'package:hafiz_al_ahd/features/gamification/presentation/cubit/gamification_state.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.screenBg,
      appBar: AppBar(
        backgroundColor: context.screenBg,
        elevation: 0,
        title: GradientText(
          'إنجازاتي',
          style: GoogleFonts.cairo(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: context.primaryText,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: BlocBuilder<GamificationCubit, GamificationState>(
        builder: (context, state) {
          if (state is GamificationLoading || state is GamificationInitial) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.secondaryGold),
            );
          }

          if (state is GamificationLoaded) {
            final profile = state.profile;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLevelCard(context, profile.level, profile.xp),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          context,
                          'السلسلة الحالية',
                          '${profile.currentStreak} أيام',
                          Icons.local_fire_department_rounded,
                          Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          context,
                          'أعلى سلسلة',
                          '${profile.bestStreak} أيام',
                          Icons.emoji_events_rounded,
                          AppColors.secondaryGold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'معرض الأوسمة',
                    style: GoogleFonts.cairo(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: context.primaryText,
                    ),
                  ),
                  const SizedBox(height: 16),
                  profile.badges.isEmpty
                      ? Center(
                          child: Text(
                            'لم تحصل على أوسمة بعد. واصل الذكر!',
                            style: GoogleFonts.cairo(
                              color: context.secondaryText,
                            ),
                          ),
                        )
                      : GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: profile.badges.length,
                          itemBuilder: (context, index) {
                            final badge = profile.badges[index];
                            return _buildBadgeCard(context, badge.name, badge.description);
                          },
                        ),
                ],
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildLevelCard(BuildContext context, int level, int xp) {
    int nextLevelXp = level * 100;
    double progress = xp / nextLevelXp;
    if (progress > 1.0) progress = 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.secondaryGold.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondaryGold.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'المستوى $level',
                style: GoogleFonts.cairo(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: context.primaryText,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.secondaryGold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$xp / $nextLevelXp XP',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondaryGold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: context.borderSubtle,
              color: AppColors.secondaryGold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: context.primaryText,
            ),
          ),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: context.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeCard(BuildContext context, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondaryGold.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondaryGold.withOpacity(0.1),
            blurRadius: 10,
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.military_tech_rounded, color: AppColors.secondaryGold, size: 48),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.primaryText,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              description,
              style: GoogleFonts.cairo(
                fontSize: 12,
                color: context.secondaryText,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
