import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/config/catalog_config.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/core/widgets/app_loader.dart';
import 'package:hafiz_al_ahd/features/notifications/data/services/audio_download_service_impl.dart';
import 'package:hafiz_al_ahd/features/notifications/developer/navigation/developer_route_gate.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_catalog_entry.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/adhan_storage_inventory.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/audio_source_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/download_state.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/services/playable_audio_resolver.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/adhan_catalog_cubit/adhan_catalog_cubit.dart';
import 'package:hafiz_al_ahd/features/notifications/presentation/cubit/adhan_catalog_cubit/adhan_catalog_state.dart';

class AdhanCatalogScreen extends StatelessWidget {
  final AudioSourceConfig currentSelectedSource;
  final bool isFajr;

  const AdhanCatalogScreen({
    super.key,
    required this.currentSelectedSource,
    this.isFajr = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdhanCatalogCubit>(
      create: (_) => sl<AdhanCatalogCubit>()..loadCatalog(),
      child: _AdhanCatalogView(
        currentSelectedSource: currentSelectedSource,
        isFajr: isFajr,
      ),
    );
  }
}

class _AdhanCatalogView extends StatefulWidget {
  final AudioSourceConfig currentSelectedSource;
  final bool isFajr;

  const _AdhanCatalogView({
    required this.currentSelectedSource,
    required this.isFajr,
  });

  @override
  State<_AdhanCatalogView> createState() => _AdhanCatalogViewState();
}

class _AdhanCatalogViewState extends State<_AdhanCatalogView> {
  late AudioSourceConfig _selected;
  int _developerTapCount = 0;
  DateTime? _lastDeveloperTapTime;

  static const List<BuiltInAudioSource> _builtInSources = [
    AudioSourceConfig.defaultMishary,
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.currentSelectedSource;
  }

  void _handleTitleTap() {
    if (!isCatalogDeveloperToolsActive) return;
    final now = DateTime.now();
    if (_lastDeveloperTapTime == null ||
        now.difference(_lastDeveloperTapTime!) > const Duration(seconds: 3)) {
      _developerTapCount = 1;
    } else {
      _developerTapCount++;
    }
    _lastDeveloperTapTime = now;

    if (_developerTapCount >= 7) {
      _developerTapCount = 0;
      openDeveloperCatalogIfActive(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return BlocConsumer<AdhanCatalogCubit, AdhanCatalogState>(
      listener: (context, state) {
        if (state.userNotice != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.userNotice!,
                style: GoogleFonts.cairo(color: Colors.white),
              ),
              backgroundColor: AppColors.secondaryGold,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
          context.read<AdhanCatalogCubit>().clearNotice();
        }
      },
      builder: (context, state) {
        final cubit = context.read<AdhanCatalogCubit>();

        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) {
              cubit.stopPreview();
            }
          },
          child: Scaffold(
            backgroundColor: backgroundColor,
            appBar: AppBar(
              title: isCatalogDeveloperToolsActive
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _handleTitleTap,
                      child: Text(
                        'اختيار صوت الأذان',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      ),
                    )
                  : Text(
                      'اختيار صوت الأذان',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                    ),
              centerTitle: true,
              elevation: 0,
              actions: [
                IconButton(
                  tooltip: 'إدارة الذاكرة',
                  icon: const Icon(Icons.pie_chart_outline_rounded),
                  onPressed: () => _showStorageModal(context, cubit, state),
                ),
                IconButton(
                  tooltip: 'تحديث المكتبة',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => cubit.loadCatalog(forceRefresh: true),
                ),
              ],
            ),
            body: RefreshIndicator(
              color: AppColors.secondaryGold,
              onRefresh: () => cubit.loadCatalog(forceRefresh: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 1. Offline Indicator Banner
                if (state.isOffline) _buildOfflineBanner(),

                // 2. Quota Alert Banner
                _buildQuotaAlertBanner(context, cubit, state),

                // 3. Built-in Audio Section Header
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    'الأصوات المدمجة',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondaryGold,
                    ),
                  ),
                ),

                // 3. Built-in Audio Cards
                ..._builtInSources.map((source) {
                  final isSelected = _selected.id == source.id ||
                      (_selected is BuiltInAudioSource &&
                          (_selected.id == 'builtIn:default_general' ||
                              _selected.id == 'builtIn:default_fajr'));

                  final isPlayingThis =
                      state.isPreviewPlaying && state.playingAudioId == source.id;

                  return Card(
                    color: cardColor,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isSelected
                          ? const BorderSide(color: AppColors.secondaryGold, width: 2)
                          : BorderSide.none,
                    ),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: IconButton(
                        icon: Icon(
                          isPlayingThis
                              ? Icons.stop_circle_rounded
                              : Icons.play_circle_fill_rounded,
                          color: AppColors.secondaryGold,
                          size: 36,
                        ),
                        onPressed: () =>
                            cubit.playBuiltInPreview(source, isFajr: widget.isFajr),
                      ),
                      title: Text(
                        source.displayName,
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      subtitle: Text(
                        widget.isFajr
                            ? 'يشمل أذان الفجر (الصلاة خير من النوم)'
                            : 'الأذان لجميع الصلوات (افتراضي)',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: textColor.withValues(alpha: 0.6),
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded,
                              color: AppColors.secondaryGold, size: 28)
                          : OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.secondaryGold),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () {
                                setState(() => _selected = source);
                                cubit.stopPreview();
                                Navigator.of(context).pop(source);
                              },
                              child: Text(
                                'اختيار',
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  color: AppColors.secondaryGold,
                                ),
                              ),
                            ),
                      onTap: () {
                        setState(() => _selected = source);
                        cubit.stopPreview();
                        Navigator.of(context).pop(source);
                      },
                    ),
                  );
                }),

                const SizedBox(height: 16),

                // 4. Remote Catalog Section Header
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'مكتبة الأذان السحابية',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondaryGold,
                        ),
                      ),
                      if (state.status == CatalogStatus.loading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: AppLoader(width: 20, height: 20),
                        ),
                    ],
                  ),
                ),

                // 5. Remote Catalog Body (Loading / Error / Empty / List)
                if (state.status == CatalogStatus.loading && state.catalog == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: AppLoader(width: 80, height: 80),
                    ),
                  )
                else if (state.status == CatalogStatus.error &&
                    (state.catalog == null || state.catalog!.isEmpty))
                  _buildErrorView(cubit, state.errorMessage)
                else if (state.catalog != null && state.catalog!.entries.isEmpty)
                  _buildEmptyView()
                else if (state.catalog != null)
                  ..._buildCatalogEntries(
                    context,
                    cubit,
                    state,
                    cardColor,
                    textColor,
                  ),
              ],
            ),
          ),
        ),
        );
      },
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.amber, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'أنت في وضع عدم الاتصال — يمكنك اختيار واستماع الأصوات المحملة مسبقاً',
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.amber.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(AdhanCatalogCubit cubit, String? message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            message ?? 'تعذر تحميل مكتبة الأذان في الوقت الحالي',
            style: GoogleFonts.cairo(color: Colors.grey, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text('إعادة المحاولة', style: GoogleFonts.cairo(fontSize: 13)),
            onPressed: () => cubit.loadCatalog(forceRefresh: true),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          'لا توجد أصوات متاحة في الكتالوج حالياً',
          style: GoogleFonts.cairo(color: Colors.grey, fontSize: 13),
        ),
      ),
    );
  }

  List<Widget> _buildCatalogEntries(
    BuildContext context,
    AdhanCatalogCubit cubit,
    AdhanCatalogState state,
    Color cardColor,
    Color textColor,
  ) {
    final entries = state.catalog!.entries;

    // Filter or prioritize according to prayer context
    final sortedEntries = List<AdhanCatalogEntry>.from(entries);
    if (widget.isFajr) {
      // Show Fajr specific first
      sortedEntries.sort((a, b) {
        if (a.audioType == AdhanAudioType.fajr && b.audioType != AdhanAudioType.fajr) {
          return -1;
        }
        if (a.audioType != AdhanAudioType.fajr && b.audioType == AdhanAudioType.fajr) {
          return 1;
        }
        return 0;
      });
    }

    return sortedEntries.map((entry) {
      final isSelected = _selected.id == 'custom:${entry.id}';
      final playableStatus =
          state.playableStatuses[entry.id] ?? AudioPlayableStatus.requiresDownload;
      final isReady = playableStatus == AudioPlayableStatus.ready;
      final isPlayingThis =
          state.isPreviewPlaying && state.playingAudioId == entry.id;

      final task = state.downloadTasks[entry.id];
      final isDownloading = task != null && task.status.isActive;

      final sizeMb = (entry.fileSizeBytes / (1024 * 1024)).toStringAsFixed(1);

      return Card(
        color: cardColor,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isSelected
              ? const BorderSide(color: AppColors.secondaryGold, width: 2)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Play/Stop Button
                  IconButton(
                    icon: Icon(
                      isPlayingThis
                          ? Icons.stop_circle_rounded
                          : (isReady
                              ? Icons.play_circle_fill_rounded
                              : Icons.play_circle_outline_rounded),
                      color: isReady ? AppColors.secondaryGold : Colors.grey,
                      size: 36,
                    ),
                    onPressed: () {
                      if (isReady) {
                        cubit.playRemoteEntryPreview(entry);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'يجب تنزيل الأذان أولاً للاستماع إليه',
                              style: GoogleFonts.cairo(color: Colors.white),
                            ),
                            backgroundColor: AppColors.secondaryGold,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),

                  // Title and Sheikh
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.sheikhName,
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        Text(
                          entry.displayName,
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: textColor.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: entry.audioType == AdhanAudioType.fajr
                                    ? Colors.blue.withValues(alpha: 0.12)
                                    : AppColors.secondaryGold.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                entry.audioType.arabicLabel,
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: entry.audioType == AdhanAudioType.fajr
                                      ? Colors.blue
                                      : AppColors.secondaryGold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$sizeMb ميجابايت • ${entry.durationSeconds} ثانية',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: textColor.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Trailing Action Control
                  _buildTrailingControl(
                    context,
                    cubit,
                    entry,
                    isSelected,
                    isReady,
                    isDownloading,
                    task,
                    state,
                  ),
                ],
              ),

              // Active Download Progress Bar
              if (task != null && task.status.isActive) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: task.progress.fraction,
                          backgroundColor: Colors.grey.withValues(alpha: 0.2),
                          color: AppColors.secondaryGold,
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      task.progress.percentage != null
                          ? '${task.progress.percentage}%'
                          : 'جارٍ...',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondaryGold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => cubit.cancelDownload(entry.id),
                      child: const Icon(Icons.cancel_rounded,
                          size: 18, color: Colors.grey),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    task.status == DownloadStatus.verifying
                        ? 'جارٍ التحقق من سلامة الملف (SHA-256)...'
                        : task.status == DownloadStatus.promoting
                            ? 'جارٍ الحفظ في الذاكرة المحلية...'
                            : '${(task.progress.receivedBytes / (1024 * 1024)).toStringAsFixed(1)} / $sizeMb ميجابايت',
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: textColor.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildTrailingControl(
    BuildContext context,
    AdhanCatalogCubit cubit,
    AdhanCatalogEntry entry,
    bool isSelected,
    bool isReady,
    bool isDownloading,
    AudioDownloadTask? task,
    AdhanCatalogState state,
  ) {
    if (isSelected) {
      return const Icon(
        Icons.check_circle_rounded,
        color: AppColors.secondaryGold,
        size: 28,
      );
    }

    if (isReady) {
      final targetFileName = AudioDownloadServiceImpl.buildTargetFileName(entry);
      final relPath = 'adhan_sounds/$targetFileName';
      final isAssignedInAlarm =
          state.storageInventory?.activeAlarmPaths.contains(relPath) ?? false;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: isAssignedInAlarm ? 'الصوت مخصص لمنبه صلاة' : 'حذف من الهاتف',
            icon: Icon(
              Icons.delete_outline_rounded,
              color: isAssignedInAlarm
                  ? Colors.grey.withValues(alpha: 0.3)
                  : Colors.redAccent.withValues(alpha: 0.8),
              size: 20,
            ),
            onPressed: () {
              if (isAssignedInAlarm) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'لا يمكن حذف هذا الأذان لأنه مخصص لمنبه إحدى الصلوات',
                      style: GoogleFonts.cairo(color: Colors.white),
                    ),
                    backgroundColor: Colors.redAccent,
                    duration: const Duration(seconds: 3),
                  ),
                );
              } else {
                _confirmDeleteEntry(context, cubit, entry);
              }
            },
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.secondaryGold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            onPressed: () {
              final customSource = state.localSources[entry.id];
              if (customSource != null) {
                setState(() => _selected = customSource);
                cubit.stopPreview();
                Navigator.of(context).pop(customSource);
              }
            },
            child: Text(
              'اختيار',
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: AppColors.secondaryGold,
              ),
            ),
          ),
        ],
      );
    }

    if (isDownloading) {
      return const SizedBox.shrink();
    }

    if (task != null && task.status == DownloadStatus.failed) {
      return IconButton(
        tooltip: 'إعادة المحاولة',
        icon: const Icon(Icons.refresh_rounded, color: Colors.redAccent),
        onPressed: () => cubit.startDownload(entry),
      );
    }

    // Not downloaded yet -> Download Button
    if (state.isQuotaExceeded) {
      return IconButton(
        tooltip: 'تم بلوغ الحد الأقصى لكاش الأصوات (150 ميجابايت)',
        icon: Icon(
          Icons.cloud_download_outlined,
          color: Colors.grey.withValues(alpha: 0.4),
          size: 26,
        ),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'لا يمكن بدء تنزيل جديد: تم بلوغ الحد الأقصى لكاش الأصوات (150 ميجابايت). يرجى تحرير مساحة أولاً.',
                style: GoogleFonts.cairo(color: Colors.white),
              ),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 3),
            ),
          );
        },
      );
    }

    return IconButton(
      tooltip: 'تنزيل الأذان',
      icon: const Icon(Icons.cloud_download_outlined,
          color: AppColors.secondaryGold, size: 26),
      onPressed: () => cubit.startDownload(entry),
    );
  }

  void _confirmDeleteEntry(
    BuildContext context,
    AdhanCatalogCubit cubit,
    AdhanCatalogEntry entry,
  ) {
    showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'حذف الأذان من الهاتف',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل أنت متأكد من حذف صوت أذان "${entry.displayName}" للشيخ ${entry.sheikhName} من ذاكرة الهاتف؟\nستتمكن من تنزيله لاحقاً في أي وقت.',
          style: GoogleFonts.cairo(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(
              'إلغاء',
              style: GoogleFonts.cairo(color: Colors.grey),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(
              'حذف',
              style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        cubit.deleteDownloadedEntry(entry);
      }
    });
  }

  Widget _buildQuotaAlertBanner(
    BuildContext context,
    AdhanCatalogCubit cubit,
    AdhanCatalogState state,
  ) {
    if (state.storageStatus == StorageStatus.loading && state.storageInventory == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: AppLoader(width: 18, height: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'جارٍ فحص مساحة التخزين...',
              style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (state.storageStatus == StorageStatus.error && state.storageInventory == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, size: 16, color: Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.storageErrorMessage ?? 'تعذر فحص الذاكرة',
                style: GoogleFonts.cairo(fontSize: 11, color: Colors.redAccent),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(45, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => cubit.refreshStorageInventory(),
              child: Text('إعادة المحاولة', style: GoogleFonts.cairo(fontSize: 11, color: Colors.redAccent)),
            ),
          ],
        ),
      );
    }

    final inventory = state.storageInventory;
    if (inventory == null) return const SizedBox.shrink();

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final usedMb = (inventory.effectiveRemoteUsageBytes / (1024 * 1024)).toStringAsFixed(1);
    final quotaMb = (inventory.remoteCacheQuotaBytes / (1024 * 1024)).toStringAsFixed(0);
    final inFlightMb = (inventory.reservedInFlightBytes / (1024 * 1024)).toStringAsFixed(1);
    final remainingMb = (inventory.availableRemoteQuotaBytes / (1024 * 1024)).toStringAsFixed(1);
    final fraction = state.quotaUsageRatio;

    Color themeColor;
    Color bgColor;
    Color borderColor;
    IconData iconData;
    String titleText;
    String? subtitleText;

    if (state.isQuotaExceeded) {
      themeColor = Colors.redAccent;
      bgColor = isDark ? Colors.red.withValues(alpha: 0.15) : Colors.red.shade50;
      borderColor = Colors.redAccent.withValues(alpha: 0.4);
      iconData = Icons.error_outline_rounded;
      titleText = 'تم بلوغ الحد الأقصى لكاش الأصوات ($quotaMb ميجابايت)';
      subtitleText = 'التنزيلات متوقفة حتى تحرير مساحة من كاش الأصوات السحابية.';
    } else if (state.isQuotaWarning) {
      themeColor = Colors.amber.shade800;
      bgColor = isDark ? Colors.amber.withValues(alpha: 0.15) : Colors.amber.shade50;
      borderColor = Colors.amber.withValues(alpha: 0.4);
      iconData = Icons.warning_amber_rounded;
      titleText = 'تحذير: اقتراب امتلاء كاش الأصوات ($usedMb / $quotaMb ميجابايت)';
      subtitleText = 'متبقي $remainingMb ميجابايت فقط قبل بلوغ الحد الأقصى للكاش.';
    } else {
      themeColor = AppColors.secondaryGold;
      bgColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
      borderColor = Colors.grey.withValues(alpha: 0.15);
      iconData = Icons.storage_rounded;
      titleText = 'كاش الأصوات السحابية: $usedMb / $quotaMb ميجابايت';
      subtitleText = inventory.reservedInFlightBytes > 0
          ? 'يشمل $inFlightMb ميجابايت محجوزة قيد التنزيل حالياً'
          : null;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(iconData, size: 18, color: themeColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        titleText,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: state.isQuotaExceeded || state.isQuotaWarning ? themeColor : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _showStorageModal(context, cubit, state),
                child: Text(
                  'تفاصيل الذاكرة',
                  style: GoogleFonts.cairo(fontSize: 11, color: themeColor),
                ),
              ),
            ],
          ),
          if (subtitleText != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitleText,
              style: GoogleFonts.cairo(
                fontSize: 10.5,
                color: state.isQuotaExceeded || state.isQuotaWarning
                    ? themeColor.withValues(alpha: 0.85)
                    : Colors.grey,
              ),
            ),
          ],
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 5,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              color: themeColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showStorageModal(
    BuildContext context,
    AdhanCatalogCubit cubit,
    AdhanCatalogState state,
  ) {
    final inventory = state.storageInventory;
    if (inventory == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalMb = (inventory.totalDirectoryBytes / (1024 * 1024)).toStringAsFixed(1);
    final remoteEffectiveMb = (inventory.effectiveRemoteUsageBytes / (1024 * 1024)).toStringAsFixed(1);
    final remoteDiskMb = (inventory.remoteCacheBytes / (1024 * 1024)).toStringAsFixed(1);
    final customMb = (inventory.userCustomBytes / (1024 * 1024)).toStringAsFixed(1);
    final inFlightMb = (inventory.reservedInFlightBytes / (1024 * 1024)).toStringAsFixed(1);
    final quotaMb = (inventory.remoteCacheQuotaBytes / (1024 * 1024)).toStringAsFixed(0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'إدارة مساحة أصوات الأذان',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: 'تحديث الحساب',
                      onPressed: () => cubit.refreshStorageInventory(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 1. Remote Audio Cache Section
                Text(
                  'كاش الأصوات السحابية (الحد الأقصى $quotaMb ميجابايت)',
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.secondaryGold),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      _buildStatRow('إجمالي استهلاك الكاش الفعلي', '$remoteEffectiveMb / $quotaMb ميجابايت'),
                      const Divider(height: 12),
                      _buildStatRow('الملفات المحملة على القرص', '$remoteDiskMb ميجابايت'),
                      if (inventory.reservedInFlightBytes > 0) ...[
                        const Divider(height: 12),
                        _buildStatRow('سعة محجوزة قيد التنزيل', '$inFlightMb ميجابايت'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 2. User Custom Audio Section (Exempt from quota)
                Text(
                  'أصوات المستخدم المخصصة',
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatRow('مساحة الأصوات المستوردة', '$customMb ميجابايت'),
                      const SizedBox(height: 4),
                      Text(
                        'أصواتك المخصصة مستقلة تماماً ومعفاة من كوتة الكاش (150 ميجابايت).',
                        style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 3. Protected Audio Files (Active in prayer alarms)
                Text(
                  'الأصوات المحمية (مخصصة لمنبهات الصلاة)',
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Builder(
                  builder: (_) {
                    final protectedList = inventory.files.where((f) => f.isProtected).toList();
                    if (protectedList.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'لا توجد أصوات مخصصة لمنبهات حالياً.',
                          style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey),
                        ),
                      );
                    }
                    return Column(
                      children: protectedList.map((file) {
                        final fileName = file.fileName;
                        final size = (file.byteLength / (1024 * 1024)).toStringAsFixed(1);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.lock_rounded, size: 16, color: AppColors.secondaryGold),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fileName,
                                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${file.protectedReason ?? "منبه صلاة"} • $size ميجابايت',
                                      style: GoogleFonts.cairo(fontSize: 10.5, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.secondaryGold.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'محمي',
                                  style: GoogleFonts.cairo(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.secondaryGold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 14),

                // 4. Safe Eviction Candidates (Unassigned remote cache files)
                Text(
                  'أصوات سحابية يمكن حذفها (غير مخصصة لأي منبه)',
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                if (inventory.evictionCandidates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'لا توجد أصوات سحابية قابلة للحذف.',
                      style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey),
                    ),
                  )
                else
                  ...inventory.evictionCandidates.map((file) {
                    final fileName = file.fileName;
                    final size = (file.byteLength / (1024 * 1024)).toStringAsFixed(1);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_done_rounded, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fileName,
                                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '$size ميجابايت',
                                  style: GoogleFonts.cairo(fontSize: 10.5, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                            tooltip: 'حذف الملف لتحرير مساحة',
                            onPressed: () {
                              _confirmDeleteCandidateFile(context, cubit, file);
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 14),

                // 5. Total Directory Storage Overview
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _buildStatRow('إجمالي مساحة مجلد adhan_sounds/', '$totalMb ميجابايت'),
                ),
                const SizedBox(height: 14),

                // 6. Dry-Run Temporary Files Preview
                if (inventory.abandonedTmpFiles.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'معاينة: توجد ${inventory.abandonedTmpFiles.length} ملفات مؤقتة مهجورة (${(inventory.abandonedTmpBytes / 1024).toStringAsFixed(1)} ك.ب) مرشحة للتنظيف التلقائي مستقبلاً.',
                            style: GoogleFonts.cairo(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(modalCtx).pop(),
                    child: Text('إغلاق', style: GoogleFonts.cairo()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteCandidateFile(
    BuildContext context,
    AdhanCatalogCubit cubit,
    StorageAudioFile file,
  ) {
    final fileName = file.fileName;
    showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'حذف ملف الأذان',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل أنت متأكد من حذف الملف "$fileName" من الذاكرة المحلية؟\nلن تتأثر إعدادات الصلوات لأن هذا الملف غير مخصص لأي منبه.',
          style: GoogleFonts.cairo(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text('حذف', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        cubit.deleteStorageFile(file.relativePath);
      }
    });
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey)),
        Text(value, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
