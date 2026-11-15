import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/config/catalog_developer_config.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/data/services/local_audio_hasher_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/domain/services/local_audio_hasher_service.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:path/path.dart' as p;

/// Modal dialog for adding or editing an [AdhanCatalogEntry] in the draft.
class CatalogDraftEntryDialog extends StatefulWidget {
  final AdhanCatalogEntry? initialEntry;
  final LocalAudioHasherService? hasherService;

  const CatalogDraftEntryDialog({
    super.key,
    this.initialEntry,
    this.hasherService,
  });

  @override
  State<CatalogDraftEntryDialog> createState() => _CatalogDraftEntryDialogState();
}

class _CatalogDraftEntryDialogState extends State<CatalogDraftEntryDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _idController;
  late final TextEditingController _sheikhNameController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _objectKeyController;
  late final TextEditingController _fileSizeController;
  late final TextEditingController _sha256Controller;
  late final TextEditingController _durationController;
  late final TextEditingController _previewOffsetController;
  late AdhanAudioType _selectedAudioType;

  static final RegExp _sha256Regex = RegExp(r'^[0-9a-f]{64}$');

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;
    _selectedAudioType = entry?.audioType ?? AdhanAudioType.general;
    _idController = TextEditingController(text: entry?.id ?? 'remote:');
    _sheikhNameController = TextEditingController(text: entry?.sheikhName ?? '');
    _displayNameController = TextEditingController(text: entry?.displayName ?? '');
    _objectKeyController = TextEditingController(text: entry?.objectKey ?? 'audio/');
    _fileSizeController = TextEditingController(text: entry != null ? entry.fileSizeBytes.toString() : '');
    _sha256Controller = TextEditingController(text: entry?.sha256 ?? '');
    _durationController = TextEditingController(text: entry != null ? entry.durationSeconds.toString() : '');
    _previewOffsetController = TextEditingController(text: entry != null ? entry.previewOffsetSeconds.toString() : '0');
  }

  @override
  void dispose() {
    _idController.dispose();
    _sheikhNameController.dispose();
    _displayNameController.dispose();
    _objectKeyController.dispose();
    _fileSizeController.dispose();
    _sha256Controller.dispose();
    _durationController.dispose();
    _previewOffsetController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final entry = AdhanCatalogEntry(
      id: _idController.text.trim(),
      sheikhName: _sheikhNameController.text.trim(),
      audioType: _selectedAudioType,
      displayName: _displayNameController.text.trim(),
      durationSeconds: int.parse(_durationController.text.trim()),
      objectKey: _objectKeyController.text.trim(),
      fileSizeBytes: int.parse(_fileSizeController.text.trim()),
      sha256: _sha256Controller.text.trim().toLowerCase(),
      previewOffsetSeconds: int.tryParse(_previewOffsetController.text.trim()) ?? 0,
    );

    Navigator.of(context).pop(entry);
  }

  Future<void> _importFromLocalFile() async {
    final pathController = TextEditingController();
    final file = await showDialog<File>(
      context: context,
      builder: (promptCtx) => AlertDialog(
        title: Text('اختيار ملف صوتي محلي', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'أدخل مسار الملف الصوتي على الجهاز (.mp3, .m4a, .wav):',
              style: GoogleFonts.cairo(fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pathController,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                hintText: r'C:\audio\fajr.mp3 أو /storage/fajr.mp3',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(promptCtx).pop(),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () {
              final text = pathController.text.trim();
              if (text.isNotEmpty) {
                Navigator.of(promptCtx).pop(File(text));
              }
            },
            child: Text('فحص وحساب البصمة', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );

    if (file == null) return;

    try {
      final hasher = widget.hasherService ??
          (sl.isRegistered<LocalAudioHasherService>() ? sl<LocalAudioHasherService>() : LocalAudioHasherServiceImpl());
      final result = await hasher.hashAudioFile(file);

      setState(() {
        _fileSizeController.text = result.fileSizeBytes.toString();
        _sha256Controller.text = result.sha256;
        _objectKeyController.text = 'audio/${result.fileName}';
        if (result.durationSeconds != null && result.durationSeconds! > 0) {
          _durationController.text = result.durationSeconds.toString();
        }
        if (_displayNameController.text.isEmpty) {
          _displayNameController.text = p.basenameWithoutExtension(result.fileName);
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حساب بصمة وحجم الملف بنجاح (${result.fileName})', style: GoogleFonts.cairo()),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تحليل الملف الصوتي: $e', style: GoogleFonts.cairo()),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialEntry != null;

    return AlertDialog(
      title: Text(
        isEditing ? 'تعديل صوت الأذان' : 'إضافة صوت أذان جديد',
        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        textAlign: TextAlign.right,
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: Form(
          key: _formKey,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Local file auto-hasher button
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondaryGold,
                      side: const BorderSide(color: AppColors.secondaryGold),
                    ),
                    icon: const Icon(Icons.audio_file_rounded),
                    label: Text(
                      'استيراد وحساب البصمة من ملف محلي',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _importFromLocalFile,
                  ),
                  const SizedBox(height: 12),
                  // Sheikh Name
                  TextFormField(
                    controller: _sheikhNameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الشيخ *',
                      hintText: 'مثال: الشيخ مشاري راشد العفاسي',
                    ),
                    validator: (val) =>
                        (val == null || val.trim().isEmpty) ? 'اسم الشيخ مطلوب' : null,
                  ),
                  const SizedBox(height: 12),

                  // Display Name
                  TextFormField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(
                      labelText: 'الاسم المعروض *',
                      hintText: 'مثال: أذان الفجر بصوت هادئ',
                    ),
                    validator: (val) =>
                        (val == null || val.trim().isEmpty) ? 'الاسم المعروض مطلوب' : null,
                  ),
                  const SizedBox(height: 12),

                  // Audio Type Dropdown
                  DropdownButtonFormField<AdhanAudioType>(
                    initialValue: _selectedAudioType,
                    decoration: const InputDecoration(labelText: 'نوع الأذان *'),
                    items: AdhanAudioType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.arabicLabel, style: GoogleFonts.cairo()),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedAudioType = val);
                    },
                  ),
                  const SizedBox(height: 12),

                  // ID
                  TextFormField(
                    controller: _idController,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'معرف الأذان (ID) *',
                      hintText: 'remote:sheikh_fajr',
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'المعرف مطلوب';
                      if (!val.startsWith('remote:')) return 'يجب أن يبدأ بـ "remote:"';
                      if (val.trim().length <= 'remote:'.length) return 'أدخل اسماً فريداً بعد remote:';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Object Key
                  TextFormField(
                    controller: _objectKeyController,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'مسار R2 (Object Key) *',
                      hintText: 'audio/mishary_fajr.mp3',
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'المسار مطلوب';
                      if (val.contains('..') || val.contains(r'\') || val.contains('://') || val.startsWith('/')) {
                        return 'مسار غير آمن (Path Traversal)';
                      }
                      final ext = p.extension(val).toLowerCase();
                      if (!CatalogDeveloperConfig.allowedAudioExtensions.contains(ext)) {
                        return 'امتداد غير مدعوم ($ext). المسموح: .mp3, .m4a, .wav';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // File Size (Bytes)
                  TextFormField(
                    controller: _fileSizeController,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'حجم الملف بالبايت *',
                      hintText: 'مثال: 2500000 (حتى 30 MiB = 31457280)',
                    ),
                    validator: (val) {
                      final n = int.tryParse(val ?? '');
                      if (n == null || n <= 0) return 'أدخل رقماً موجباً أكبر من 0';
                      if (n > kRemoteAudioMaxBytes) return 'يتجاوز الحد الأقصى 30 MiB';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // SHA-256
                  TextFormField(
                    controller: _sha256Controller,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'بصمة SHA-256 (64 hex) *',
                      hintText: '64 حرفاً صغيراً بالنظام الست عشري',
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'بصمة SHA-256 مطلوبة';
                      if (!_sha256Regex.hasMatch(val.trim())) {
                        return 'يجب أن تكون 64 حرفاً صغيراً hex (0-9, a-f)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Duration & Preview Offset Row
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _durationController,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            labelText: 'المدة (ثواني) *',
                            hintText: '180',
                          ),
                          validator: (val) {
                            final n = int.tryParse(val ?? '');
                            if (n == null || n <= 0) return 'يجب أن تكون > 0';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _previewOffsetController,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            labelText: 'بداية المعاينة (ث)',
                            hintText: '0',
                          ),
                          validator: (val) {
                            final n = int.tryParse(val ?? '0');
                            if (n == null || n < 0) return 'لا يمكن أن تكون سالبة';
                            final dur = int.tryParse(_durationController.text.trim()) ?? 0;
                            if (dur > 0 && n >= dur) return 'يجب أن تكون < المدة';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondaryGold,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: Text(isEditing ? 'حفظ التعديلات' : 'إضافة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
