import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hafiz_al_ahd/core/utils/app_colors.dart';
import 'package:hafiz_al_ahd/features/focus_mode_poc/data/focus_poc_channel.dart';
import 'package:hafiz_al_ahd/features/focus_mode_poc/presentation/widgets/poc_status_card.dart';
import 'package:hafiz_al_ahd/core/DI/service_locator.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_state.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_session_coordinator.dart';

class FocusPoCScreen extends StatefulWidget {
  const FocusPoCScreen({super.key});

  @override
  State<FocusPoCScreen> createState() => _FocusPoCScreenState();
}

class _FocusPoCScreenState extends State<FocusPoCScreen> with WidgetsBindingObserver {
  FocusPoCPermissionStatus _permissions = const FocusPoCPermissionStatus(
    hasUsageAccess: false,
    hasOverlayPermission: false,
    canScheduleExactAlarms: false,
  );

  bool _isServiceRunning = false;
  String _currentApp = 'com.shadyatef.hafiz_alahd';
  bool _isAppExempted = true;
  String _selectedWard = 'أذكار الصباح';

  final List<Map<String, dynamic>> _eventLogs = [];
  StreamSubscription? _eventSubscription;
  StreamSubscription<FocusSessionState>? _domainStateSubscription;
  Timer? _periodicAppPoller;

  final List<String> _wardOptions = [
    'أذكار الصباح',
    'أذكار المساء',
    'أذكار بعد الصلاة',
    'قراءة سورة الكهف',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshState();
    _listenToEvents();

    if (sl.isRegistered<FocusSessionCoordinator>()) {
      _domainStateSubscription =
          sl<FocusSessionCoordinator>().onStateChanged.listen((sessionState) {
        if (mounted) {
          setState(() {
            _eventLogs.insert(0, {
              'type': 'DOMAIN_${sessionState.status.name.toUpperCase()}',
              'timestamp': DateTime.now().toIso8601String(),
              'ward': sessionState.wardType.displayName,
              'status': sessionState.status.name,
              'snoozeCount': sessionState.snoozeCount,
            });
            if (_eventLogs.length > 50) _eventLogs.removeLast();

            if (sessionState.isTerminal) {
              _isServiceRunning = false;
            }
          });
        }
      });
    }

    // Poll foreground app every 3 seconds for UI display when screen is open
    _periodicAppPoller = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollCurrentApp();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventSubscription?.cancel();
    _domainStateSubscription?.cancel();
    _periodicAppPoller?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshState();
    }
  }

  Future<void> _refreshState() async {
    final perms = await FocusPoCChannel.checkPermissions();
    final running = await FocusPoCChannel.isServiceRunning();
    await _pollCurrentApp();

    if (mounted) {
      setState(() {
        _permissions = perms;
        _isServiceRunning = running;
      });
    }
  }

  Future<void> _pollCurrentApp() async {
    final info = await FocusPoCChannel.getCurrentForegroundApp();
    if (mounted) {
      setState(() {
        _currentApp = info['packageName'] as String? ?? 'N/A';
        _isAppExempted = info['isExempted'] as bool? ?? true;
      });
    }
  }

  void _listenToEvents() {
    _eventSubscription = FocusPoCChannel.eventStream.listen((event) {
      if (mounted) {
        setState(() {
          _eventLogs.insert(0, event);
          if (_eventLogs.length > 50) {
            _eventLogs.removeLast();
          }

          final type = event['type'] as String?;
          if (type == 'SESSION_STARTED') {
            _isServiceRunning = true;
          } else if (type == 'SESSION_STOPPED' || type == 'SESSION_BYPASSED') {
            _isServiceRunning = false;
          }
        });
      }
    });
  }

  Future<void> _startSession() async {
    if (!_permissions.isAllGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'يرجى منح صلاحيات (Usage Access و Display Over Apps) أولاً.',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (sl.isRegistered<FocusSessionCoordinator>()) {
      FocusWardType wardType = FocusWardType.morningAzkar;
      if (_selectedWard.contains('المساء')) {
        wardType = FocusWardType.eveningAzkar;
      } else if (_selectedWard.contains('القرآن') || _selectedWard.contains('الكهف')) {
        wardType = FocusWardType.quranReading;
      } else if (_selectedWard.contains('الصلاة')) {
        wardType = FocusWardType.postPrayerAzkar;
      }

      await sl<FocusSessionCoordinator>().startSession(
        sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
        wardType: wardType,
      );
    } else {
      await FocusPoCChannel.startMonitoring(wardTitle: _selectedWard);
    }

    await _refreshState();
  }

  Future<void> _stopSession() async {
    if (sl.isRegistered<FocusSessionCoordinator>()) {
      await sl<FocusSessionCoordinator>().cancelSession();
    } else {
      await FocusPoCChannel.stopMonitoring();
    }
    await _refreshState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12161A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: Text(
          'مختبر Focus Mode (PoC)',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PoCStatusCard(
              permissions: _permissions,
              isServiceRunning: _isServiceRunning,
              currentApp: _currentApp,
              isAppExempted: _isAppExempted,
              onRefreshPermissions: _refreshState,
              onOpenUsageSettings: FocusPoCChannel.openUsageAccessSettings,
              onOpenOverlaySettings: FocusPoCChannel.openOverlaySettings,
              onOpenExactAlarmSettings: FocusPoCChannel.openExactAlarmSettings,
            ),
            const SizedBox(height: 20),

            // Ward Selection & Action Controls
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1E232A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إعدادات الجلسة التجريبية:',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedWard,
                    dropdownColor: const Color(0xFF222831),
                    style: GoogleFonts.cairo(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.black26,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: _wardOptions.map((ward) {
                      return DropdownMenuItem(value: ward, child: Text(ward));
                    }).toList(),
                    onChanged: _isServiceRunning
                        ? null
                        : (val) {
                            if (val != null) setState(() => _selectedWard = val);
                          },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isServiceRunning ? null : _startSession,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text('بدء الجلسة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.secondaryGold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isServiceRunning ? _stopSession : null,
                          icon: const Icon(Icons.stop_rounded),
                          label: Text('إيقاف الجلسة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Live Event Logs Console
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.terminal_rounded, color: AppColors.secondaryGold, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'سجل الأحداث المباشر (Live Log)',
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white38, size: 20),
                        onPressed: () => setState(() => _eventLogs.clear()),
                        tooltip: 'مسح السجل',
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10),
                  if (_eventLogs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'لا توجد أحداث حتى الآن. ابدأ جلسة لاختبار المراقبة.',
                          style: GoogleFonts.cairo(color: Colors.white38, fontSize: 12),
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _eventLogs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final log = _eventLogs[index];
                          final type = log['type'] ?? 'UNKNOWN';
                          final time = DateTime.fromMillisecondsSinceEpoch(
                            log['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
                          );
                          final timeStr =
                              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

                          Color badgeColor = Colors.grey;
                          if (type == 'SHIELD_SHOWN') badgeColor = Colors.orangeAccent;
                          if (type == 'SHIELD_HIDDEN') badgeColor = Colors.greenAccent;
                          if (type == 'SESSION_SNOOZED') badgeColor = Colors.amberAccent;
                          if (type == 'SNOOZE_EXPIRED') badgeColor = Colors.cyanAccent;
                          if (type == 'SESSION_BYPASSED') badgeColor = Colors.redAccent;
                          if (type == 'SESSION_STARTED') badgeColor = AppColors.secondaryGold;

                          return Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  timeStr,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    type.toString(),
                                    style: TextStyle(
                                      color: badgeColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _formatLogPayload(log),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatLogPayload(Map<String, dynamic> log) {
    final clone = Map<String, dynamic>.from(log)..remove('type')..remove('timestamp');
    return clone.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }
}
