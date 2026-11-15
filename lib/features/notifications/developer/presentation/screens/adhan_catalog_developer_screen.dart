import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/widgets/app_loader.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/presentation/cubit/adhan_catalog_developer_cubit.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/presentation/cubit/adhan_catalog_developer_state.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/presentation/widgets/catalog_draft_entry_dialog.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';

/// Developer-only screen for inspecting live catalog, editing local drafts,
/// validating schema constraints, and exporting production JSON.
class AdhanCatalogDeveloperScreen extends StatelessWidget {
  const AdhanCatalogDeveloperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AdhanCatalogDeveloperCubit>()..loadDeveloperData(),
      child: const _AdhanCatalogDeveloperScaffold(),
    );
  }
}

class _AdhanCatalogDeveloperScaffold extends StatefulWidget {
  const _AdhanCatalogDeveloperScaffold();

  @override
  State<_AdhanCatalogDeveloperScaffold> createState() => _AdhanCatalogDeveloperScaffoldState();
}

class _AdhanCatalogDeveloperScaffoldState extends State<_AdhanCatalogDeveloperScaffold>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showResetConfirmation(BuildContext context) {
    final cubit = context.read<AdhanCatalogDeveloperCubit>();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          'تأكيد استعادة المسودة',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          textAlign: TextAlign.right,
        ),
        content: Text(
          'تحذير: سيتم حذف جميع التعديلات المحلية غير المحفوظة في المسودة واستبدالها بنسخة الكتالوج المباشر الصالح (أو المخزن مؤقتاً).\n\nهل أنت متأكد من المتابعة؟',
          style: GoogleFonts.cairo(),
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              cubit.resetDraftToLive(confirmReset: true);
            },
            child: Text('تأكيد الاستعادة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteEntryConfirmation(BuildContext context, int index, String entryName) {
    final cubit = context.read<AdhanCatalogDeveloperCubit>();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          'حذف الصوت من المسودة',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          textAlign: TextAlign.right,
        ),
        content: Text(
          'هل تريد حذف "$entryName" من مسودة الكتالوج؟',
          style: GoogleFonts.cairo(),
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              cubit.removeEntry(index);
            },
            child: Text('حذف', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handleExport(BuildContext context, AdhanCatalogDeveloperState state) {
    final cubit = context.read<AdhanCatalogDeveloperCubit>();
    final jsonString = cubit.exportDraftJson();
    if (jsonString == null) return;

    Clipboard.setData(ClipboardData(text: jsonString));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                  ),
                  Text(
                    'تصدير الكتالوج (JSON)',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: 'نسخ إلى الحافظة',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: jsonString));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم نسخ الـ JSON إلى الحافظة', style: GoogleFonts.cairo()),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: SelectableText(
                      jsonString,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.lightGreenAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondaryGold,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.copy),
                label: Text('نسخ كامل الكود إلى الحافظة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: jsonString));
                  Navigator.of(sheetCtx).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F9FA);

    return BlocConsumer<AdhanCatalogDeveloperCubit, AdhanCatalogDeveloperState>(
      listener: (context, state) {
        if (state.userNotice != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.userNotice!, style: GoogleFonts.cairo()),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.read<AdhanCatalogDeveloperCubit>().clearNotice();
        }
        if (state.userError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.userError!, style: GoogleFonts.cairo()),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.read<AdhanCatalogDeveloperCubit>().clearError();
        }
      },
      builder: (context, state) {
        final cubit = context.read<AdhanCatalogDeveloperCubit>();

        return Scaffold(
          backgroundColor: backgroundColor,
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'DEV',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'إدارة كتالوج الأذان',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            centerTitle: true,
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'محرر المسودة (Draft)'),
                Tab(text: 'الكتالوج المباشر (Live)'),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'إعادة تحميل',
                onPressed: () => cubit.loadDeveloperData(),
              ),
            ],
          ),
          body: state.isLoading
              ? const Center(child: AppLoader())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDraftEditorTab(context, state, cubit),
                    _buildLiveInspectorTab(context, state),
                  ],
                ),
          floatingActionButton: _tabController.index == 0
              ? FloatingActionButton.extended(
                  backgroundColor: AppColors.secondaryGold,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add),
                  label: Text('إضافة صوت', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    final newEntry = await showDialog<AdhanCatalogEntry>(
                      context: context,
                      builder: (_) => const CatalogDraftEntryDialog(),
                    );
                    if (newEntry != null) {
                      cubit.addEntry(newEntry);
                    }
                  },
                )
              : null,
          bottomNavigationBar: _buildBottomActionBar(context, state, cubit),
        );
      },
    );
  }

  Widget _buildDraftEditorTab(
    BuildContext context,
    AdhanCatalogDeveloperState state,
    AdhanCatalogDeveloperCubit cubit,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Validation Panel
          _buildValidationPanel(state),
          const SizedBox(height: 12),

          // Metadata Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'بيانات المخطط (Schema Metadata)',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      ),
                      if (state.hasUnsavedChanges)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'تعديلات غير محفوظة',
                            style: GoogleFonts.cairo(fontSize: 11, color: Colors.orange.shade800),
                          ),
                        ),
                    ],
                  ),
                  const Divider(),
                  Text('إصدار المخطط: ${state.draftCatalog.schemaVersion}', style: GoogleFonts.cairo()),
                  Text('تاريخ الإنشاء: ${state.draftCatalog.generatedAt ?? "غير محدد"}', style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey)),
                  Text('عدد الأصوات في المسودة: ${state.draftCatalog.entries.length}', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Entries List
          Text(
            'قائمة الأصوات في المسودة:',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 8),

          if (state.draftCatalog.entries.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'لا توجد أصوات في المسودة حالياً.\nاضغط على "إضافة صوت" لبدء إنشاء الكتالوج.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(color: Colors.grey),
                  ),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: state.draftCatalog.entries.length,
              itemBuilder: (context, index) {
                final entry = state.draftCatalog.entries[index];
                return _buildDraftEntryCard(context, index, entry, cubit);
              },
            ),
          const SizedBox(height: 80), // Padding for FAB
        ],
      ),
    );
  }

  Widget _buildValidationPanel(AdhanCatalogDeveloperState state) {
    if (state.isValid) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.shade600),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '✓ المسودة صالحة ومطابقة لجميع قواعد المخطط بنسبة 100%.',
                style: GoogleFonts.cairo(color: Colors.green.shade800, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'توجد ${state.validationErrors.length} أخطاء تحقق تمنع تصدير الكتالوج:',
                  style: GoogleFonts.cairo(color: Colors.red.shade800, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...state.validationErrors.map((err) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${err.toString()}',
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildDraftEntryCard(
    BuildContext context,
    int index,
    AdhanCatalogEntry entry,
    AdhanCatalogDeveloperCubit cubit,
  ) {
    final sizeMb = (entry.fileSizeBytes / (1024 * 1024)).toStringAsFixed(2);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.displayName,
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        entry.sheikhName,
                        style: GoogleFonts.cairo(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryGold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.audioType.arabicLabel,
                    style: GoogleFonts.cairo(fontSize: 11, color: AppColors.secondaryGold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'تعديل',
                  onPressed: () async {
                    final edited = await showDialog<AdhanCatalogEntry>(
                      context: context,
                      builder: (_) => CatalogDraftEntryDialog(initialEntry: entry),
                    );
                    if (edited != null) {
                      cubit.updateEntry(index, edited);
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  tooltip: 'حذف',
                  onPressed: () => _showDeleteEntryConfirmation(context, index, entry.displayName),
                ),
              ],
            ),
            const Divider(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('ID: ${entry.id}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                Text('الحجم: $sizeMb MB', style: GoogleFonts.cairo(fontSize: 12)),
                Text('المدة: ${entry.durationSeconds} ثانية', style: GoogleFonts.cairo(fontSize: 12)),
                Text('المسار: ${entry.objectKey}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveInspectorTab(
    BuildContext context,
    AdhanCatalogDeveloperState state,
  ) {
    final live = state.liveCatalog;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'حالة الكتالوج المباشر',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  Text('المصدر: ${state.liveSourceLabel}', style: GoogleFonts.cairo()),
                  Text('إصدار المخطط: ${live?.schemaVersion ?? "غير متوفر"}', style: GoogleFonts.cairo()),
                  Text('تاريخ الإنشاء: ${live?.generatedAt ?? "غير متوفر"}', style: GoogleFonts.cairo(fontSize: 12)),
                  Text('عدد الأصوات المتاحة: ${live?.entries.length ?? 0}', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (live == null || live.entries.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'لا يتوفر كتالوج مباشر صالح حالياً.',
                    style: GoogleFonts.cairo(color: Colors.grey),
                  ),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: live.entries.length,
              itemBuilder: (context, index) {
                final entry = live.entries[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(entry.displayName, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                    subtitle: Text('${entry.sheikhName} • ${entry.audioType.arabicLabel}\n${entry.objectKey}', style: GoogleFonts.cairo(fontSize: 12)),
                    trailing: Text('${(entry.fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB', style: GoogleFonts.cairo()),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar(
    BuildContext context,
    AdhanCatalogDeveloperState state,
    AdhanCatalogDeveloperCubit cubit,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Save Draft Button
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondaryGold,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: state.isSaving
                    ? const SizedBox(width: 20, height: 20, child: AppLoader(width: 20, height: 20))
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text('حفظ المسودة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                onPressed: state.isSaving ? null : () => cubit.saveDraft(),
              ),
            ),
            const SizedBox(width: 8),

            // Reset Button
            IconButton(
              icon: state.isResetting
                  ? const SizedBox(width: 20, height: 20, child: AppLoader(width: 20, height: 20))
                  : const Icon(Icons.restore_rounded),
              tooltip: 'استعادة من المباشر',
              onPressed: state.isResetting ? null : () => _showResetConfirmation(context),
            ),
            const SizedBox(width: 4),

            // Export JSON Button
            IconButton(
              icon: const Icon(Icons.share_rounded),
              tooltip: 'تصدير JSON',
              onPressed: () => _handleExport(context, state),
            ),
          ],
        ),
      ),
    );
  }
}

