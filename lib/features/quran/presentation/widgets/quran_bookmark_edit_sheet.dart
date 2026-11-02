import 'package:flutter/material.dart';
import '../../../../core/utils/app_colors.dart';
import '../../data/datasources/surah_names.dart';
import '../../domain/entities/ayah_id.dart';
import '../../domain/entities/quran_bookmark.dart';

/// Preset definition for Quran bookmarks
class QuranBookmarkPreset {
  final String name;
  final int colorCode;
  final IconData icon;

  const QuranBookmarkPreset({
    required this.name,
    required this.colorCode,
    required this.icon,
  });
}

const List<QuranBookmarkPreset> kQuranBookmarkPresets = [
  QuranBookmarkPreset(
    name: 'فاصل ورد التلاوة',
    colorCode: 0xFFD4AF37, // Royal Gold
    icon: Icons.menu_book_rounded,
  ),
  QuranBookmarkPreset(
    name: 'فاصل ورد الحفظ',
    colorCode: 0xFF2E7D32, // Emerald Green
    icon: Icons.school_rounded,
  ),
  QuranBookmarkPreset(
    name: 'فاصل ورد المراجعة',
    colorCode: 0xFF1E88E5, // Royal Blue
    icon: Icons.sync_rounded,
  ),
  QuranBookmarkPreset(
    name: 'فاصل التدبر',
    colorCode: 0xFF7B1FA2, // Purple
    icon: Icons.auto_awesome_rounded,
  ),
  QuranBookmarkPreset(
    name: 'فاصل قيام الليل',
    colorCode: 0xFFE65100, // Amber
    icon: Icons.nights_stay_rounded,
  ),
  QuranBookmarkPreset(
    name: 'فاصل التثبيت',
    colorCode: 0xFFC2185B, // Rose / Ruby
    icon: Icons.psychology_rounded,
  ),
];

const List<int> kQuranBookmarkColors = [
  0xFFD4AF37, // Royal Gold
  0xFF2E7D32, // Emerald Green
  0xFF1E88E5, // Royal Blue
  0xFF7B1FA2, // Purple
  0xFFE65100, // Amber
  0xFFC2185B, // Ruby
  0xFF00897B, // Teal
];

/// Interactive sheet to customize bookmark name and color
class QuranBookmarkEditSheet extends StatefulWidget {
  final AyahId ayahId;
  final int? pageNumber;
  final QuranBookmark? existingBookmark;
  final Future<void> Function(String name, int colorCode) onSave;
  final VoidCallback? onDelete;

  const QuranBookmarkEditSheet({
    super.key,
    required this.ayahId,
    this.pageNumber,
    this.existingBookmark,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<QuranBookmarkEditSheet> createState() => _QuranBookmarkEditSheetState();
}

class _QuranBookmarkEditSheetState extends State<QuranBookmarkEditSheet> {
  late TextEditingController _nameController;
  late int _selectedColorCode;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final defaultPreset = kQuranBookmarkPresets.first;
    _nameController = TextEditingController(
      text: widget.existingBookmark?.name ?? defaultPreset.name,
    );
    _selectedColorCode = widget.existingBookmark?.colorCode ?? defaultPreset.colorCode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _selectPreset(QuranBookmarkPreset preset) {
    setState(() {
      _nameController.text = preset.name;
      _selectedColorCode = preset.colorCode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E24) : Colors.white;
    final primaryTextColor = isDark ? Colors.white : AppColors.darkText;
    final subtextColor = isDark ? Colors.white70 : Colors.black54;
    final borderColor = isDark ? const Color(0xFF383842) : AppColors.secondaryGold.withValues(alpha: 0.25);
    final surahName = getSurahName(widget.ayahId.surahNumber);
    final activeColor = Color(_selectedColorCode);
    final isEditing = widget.existingBookmark != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Drag Handle
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                      ),

                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: activeColor.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.bookmark_rounded,
                                  color: activeColor,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isEditing ? 'تعديل الفاصلة' : 'حفظ فاصلة جديدة',
                                    style: TextStyle(
                                      fontFamily: 'Tajawal',
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: primaryTextColor,
                                    ),
                                  ),
                                  Text(
                                    'سورة $surahName • الآية ${widget.ayahId.ayahNumber}',
                                    style: TextStyle(
                                      fontFamily: 'Tajawal',
                                      fontSize: 12,
                                      color: subtextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            color: subtextColor,
                            tooltip: 'إغلاق',
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Section 1: Presets
                      Text(
                        'نماذج فواصل جاهزة',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: subtextColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: kQuranBookmarkPresets.map((preset) {
                          final isSelected = _nameController.text == preset.name &&
                              _selectedColorCode == preset.colorCode;
                          final presetColor = Color(preset.colorCode);

                          return ChoiceChip(
                            avatar: Icon(
                              preset.icon,
                              size: 16,
                              color: isSelected ? Colors.white : presetColor,
                            ),
                            label: Text(
                              preset.name,
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : primaryTextColor,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: presetColor,
                            backgroundColor: isDark
                                ? const Color(0xFF2B2B32)
                                : presetColor.withValues(alpha: 0.08),
                            side: BorderSide(
                              color: isSelected
                                  ? presetColor
                                  : borderColor,
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                _selectPreset(preset);
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Section 2: Name Input
                      Text(
                        'اسم الفاصلة',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: subtextColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                        ),
                        decoration: InputDecoration(
                          hintText: 'اكتب اسم الفاصلة...',
                          hintStyle: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 14,
                            color: subtextColor.withValues(alpha: 0.5),
                          ),
                          prefixIcon: Icon(
                            Icons.label_outline_rounded,
                            color: activeColor,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF26262E)
                              : const Color(0xFFF7F7FA),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: activeColor, width: 1.8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Section 3: Color Palette
                      Text(
                        'لون الفاصلة',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: subtextColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: kQuranBookmarkColors.map((code) {
                          final color = Color(code);
                          final isSelected = _selectedColorCode == code;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedColorCode = code;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? Colors.white : Colors.transparent,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  if (isSelected)
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                ],
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),

                      // Action Button (Save)
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: activeColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 2,
                          ),
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.bookmark_added_rounded, size: 20),
                          label: Text(
                            _isSaving
                                ? 'جاري الحفظ...'
                                : (isEditing ? 'تحديث الفاصلة' : 'حفظ الفاصلة'),
                            style: const TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  setState(() => _isSaving = true);
                                  try {
                                    final finalName = _nameController.text.trim().isNotEmpty
                                        ? _nameController.text.trim()
                                        : 'فاصل الحفظ';
                                    final navigator = Navigator.of(context);
                                    await widget.onSave(finalName, _selectedColorCode);
                                    if (mounted) {
                                      navigator.maybePop();
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isSaving = false);
                                    }
                                  }
                                },
                        ),
                      ),

                      // Optional Delete Button when editing
                      if (isEditing && widget.onDelete != null) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text(
                            'إزالة هذه الفاصلة',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).maybePop();
                            widget.onDelete!();
                          },
                        ),
                      ],
                      const SizedBox(height: 4),
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
}

