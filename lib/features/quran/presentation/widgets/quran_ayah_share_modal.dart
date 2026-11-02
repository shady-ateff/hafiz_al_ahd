import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/app_colors.dart';
import '../cubit/quran_settings_cubit.dart';
import '../../data/datasources/surah_names.dart';
import '../../domain/entities/quran_ayah.dart';
import 'quran_ayah_share_card.dart';

/// Interactive modal sheet allowing the user to choose between sharing the Ayah
/// as formatted canonical text, or previewing and sharing an ornate golden branded image.
class QuranAyahShareModal extends StatefulWidget {
  final QuranAyah ayah;
  final VoidCallback onShareText;
  final Future<void> Function(GlobalKey cardKey) onShareImage;
  final VoidCallback? onClose;

  const QuranAyahShareModal({
    super.key,
    required this.ayah,
    required this.onShareText,
    required this.onShareImage,
    this.onClose,
  });

  @override
  State<QuranAyahShareModal> createState() => _QuranAyahShareModalState();
}

class _QuranAyahShareModalState extends State<QuranAyahShareModal> {
  final GlobalKey _cardKey = GlobalKey();
  bool _showImagePreview = false;
  bool _isProcessingImage = false;
  bool _useQcfFont = true;
  bool? _isDarkCardOverride;

  bool _resolveDarkMode(BuildContext context) {
    if (_isDarkCardOverride != null) return _isDarkCardOverride!;
    try {
      final cubit = context.read<QuranSettingsCubit>();
      if (cubit.state.quranThemeMode == ThemeMode.dark) return true;
      if (cubit.state.quranThemeMode == ThemeMode.light) return false;
    } catch (_) {}
    return Theme.of(context).brightness == Brightness.dark;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDarkCard = _resolveDarkMode(context);
    final bgColor = isDark ? AppColors.primaryBlack : Colors.white;
    final subtextColor = isDark ? Colors.white70 : Colors.black54;
    final borderColor = AppColors.secondaryGold.withValues(alpha: 0.35);
    final surahName = getSurahName(widget.ayah.id.surahNumber);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: borderColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag Handle
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (_showImagePreview)
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 18,
                              ),
                              color: AppColors.secondaryGold,
                              tooltip: 'رجوع للخيارات',
                              onPressed: () {
                                setState(() {
                                  _showImagePreview = false;
                                });
                              },
                            )
                          else
                            const SizedBox(width: 40),
                          Text(
                            _showImagePreview
                                ? 'معاينة البطاقة القرآنية'
                                : 'مشاركة الآية الكريمة',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondaryGold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            color: subtextColor,
                            tooltip: 'إغلاق',
                            onPressed:
                                widget.onClose ??
                                () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'سورة $surahName • الآية ${widget.ayah.id.ayahNumber}',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 13,
                          color: subtextColor,
                        ),
                      ),
                      const Divider(height: 20),

                      if (!_showImagePreview) ...[
                        // Option 1: Share as Text
                        _buildShareOptionTile(
                          context: context,
                          icon: Icons.text_snippet_outlined,
                          title: 'مشاركة كنص',
                          subtitle:
                              'نسخ ومشاركة الآية الكريمة كنص عبر التطبيقات',
                          onTap: widget.onShareText,
                        ),
                        const SizedBox(height: 12),

                        // Option 2: Share as Image
                        _buildShareOptionTile(
                          context: context,
                          icon: Icons.image_outlined,
                          title: 'مشاركة كصورة',
                          subtitle:
                              'بطاقة قرآنية مذهبة بشعار حافظ العهد بدقة عالية',
                          onTap: () {
                            setState(() {
                              _showImagePreview = true;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                      ] else ...[
                        // Style & Theme controls row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            runAlignment: WrapAlignment.center,

                            // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Font selection chips (QCF vs Amiri)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ChoiceChip(
                                    backgroundColor: Colors.transparent,
                                    avatar: _useQcfFont
                                        ? const Icon(
                                            Icons.check,
                                            size: 15,
                                            color: AppColors.secondaryGold,
                                          )
                                        : null,
                                    label: const Text(
                                      'خط المصحف',
                                      style: TextStyle(
                                        fontFamily: 'Tajawal',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    selected: _useQcfFont,
                                    onSelected: (val) {
                                      if (val) {
                                        setState(() => _useQcfFont = true);
                                      }
                                    },
                                    selectedColor: AppColors.secondaryGold,
                                    side: BorderSide(
                                      color: _useQcfFont
                                          ? AppColors.secondaryGold
                                          : borderColor,
                                    ),
                                  ),
                                  const SizedBox(width: 15),
                                  ChoiceChip(
                                    avatar: !_useQcfFont
                                        ? const Icon(
                                            Icons.check,
                                            size: 15,
                                            color: AppColors.secondaryGold,
                                          )
                                        : null,
                                    label: const Text(
                                      'خط النسخ',
                                      style: TextStyle(
                                        fontFamily: 'Tajawal',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    selected: !_useQcfFont,
                                    onSelected: (val) {
                                      if (val) {
                                        setState(() => _useQcfFont = false);
                                      }
                                    },
                                    selectedColor: AppColors.secondaryGold,
                                    side: BorderSide(
                                      color: !_useQcfFont
                                          ? AppColors.secondaryGold
                                          : borderColor,
                                    ),
                                  ),
                                ],
                              ),

                              // Night / Day Mode Switch button
                              Row(
                                children: [
                                  Icon(
                                    isDarkCard
                                        ? Icons.dark_mode_rounded
                                        : Icons.light_mode_rounded,
                                    size: 18,
                                    color: isDarkCard
                                        ? const Color(0xFFD6D6DC)
                                        : AppColors.secondaryGold,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isDarkCard ? 'ليلي' : 'نهاري',
                                    style: TextStyle(
                                      fontFamily: 'Tajawal',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDarkCard
                                          ? const Color(0xFFD6D6DC)
                                          : AppColors.secondaryGold,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Transform.scale(
                                    scale: 0.82,
                                    child: Switch.adaptive(
                                      value: isDarkCard,
                                      activeThumbColor: const Color(0xFFD6D6DC),
                                      activeTrackColor: Colors.white24,
                                      inactiveThumbColor:
                                          AppColors.secondaryGold,
                                      inactiveTrackColor: AppColors
                                          .secondaryGold
                                          .withValues(alpha: 0.35),
                                      onChanged: (val) {
                                        setState(() {
                                          _isDarkCardOverride = val;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Image Preview Section
                        Container(
                          height: 380,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D0D0D),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor),
                          ),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: RepaintBoundary(
                                  key: _cardKey,
                                  child: QuranAyahShareCard(
                                    ayah: widget.ayah,
                                    useQcf: _useQcfFont,
                                    isDarkMode: isDarkCard,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Share Image Button
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.secondaryGold,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 2,
                            ),
                            icon: _isProcessingImage
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.share_rounded, size: 20),
                            label: Text(
                              _isProcessingImage
                                  ? 'جاري تجهيز الصورة...'
                                  : 'مشاركة الصورة الآن',
                              style: const TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: _isProcessingImage
                                ? null
                                : () async {
                                    setState(() {
                                      _isProcessingImage = true;
                                    });
                                    try {
                                      await widget.onShareImage(_cardKey);
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _isProcessingImage = false;
                                        });
                                      }
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShareOptionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBgColor = isDark
        ? const Color(0xFF262626)
        : AppColors.secondaryGold.withValues(alpha: 0.05);
    final borderColor = AppColors.secondaryGold.withValues(alpha: 0.25);
    final textColor = isDark ? Colors.white : AppColors.darkText;
    final subtextColor = isDark ? Colors.white70 : Colors.black54;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondaryGold.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: AppColors.secondaryGold, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12,
                      color: subtextColor,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.secondaryGold,
            ),
          ],
        ),
      ),
    );
  }
}
