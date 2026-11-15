import 'package:flutter/foundation.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';

/// Status of an active or completed mode transition.
enum TransitionStatus {
  pending,
  waitingForImminentAlarm,
  reconciling,
  completed,
  failed;

  String get key => name;

  static TransitionStatus fromKey(String? key, {TransitionStatus fallback = TransitionStatus.pending}) {
    if (key == null) return fallback;
    for (final status in TransitionStatus.values) {
      if (status.name == key.trim()) {
        return status;
      }
    }
    return fallback;
  }
}

/// Persistent record tracking a mode transition between alarm / notification / off.
/// Used for crash recovery, imminent alarm waiting, and idempotency.
@immutable
class PrayerAlertTransitionRecord {
  final int schemaVersion;
  final int revision;
  final String operationId;
  final PrayerId prayerId;
  final PrayerAlarmType sourceMode;
  final PrayerAlarmType targetMode;
  final DateTime requestedAt;
  final DateTime? protectedAlarmEpoch;
  final TransitionStatus status;
  final String? failureReason;

  const PrayerAlertTransitionRecord({
    this.schemaVersion = 1,
    required this.revision,
    required this.operationId,
    required this.prayerId,
    required this.sourceMode,
    required this.targetMode,
    required this.requestedAt,
    this.protectedAlarmEpoch,
    required this.status,
    this.failureReason,
  });

  PrayerAlertTransitionRecord copyWith({
    int? schemaVersion,
    int? revision,
    String? operationId,
    PrayerId? prayerId,
    PrayerAlarmType? sourceMode,
    PrayerAlarmType? targetMode,
    DateTime? requestedAt,
    DateTime? protectedAlarmEpoch,
    bool clearProtectedEpoch = false,
    TransitionStatus? status,
    String? failureReason,
    bool clearFailureReason = false,
  }) {
    return PrayerAlertTransitionRecord(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      revision: revision ?? this.revision,
      operationId: operationId ?? this.operationId,
      prayerId: prayerId ?? this.prayerId,
      sourceMode: sourceMode ?? this.sourceMode,
      targetMode: targetMode ?? this.targetMode,
      requestedAt: requestedAt ?? this.requestedAt,
      protectedAlarmEpoch: clearProtectedEpoch
          ? null
          : (protectedAlarmEpoch ?? this.protectedAlarmEpoch),
      status: status ?? this.status,
      failureReason: clearFailureReason
          ? null
          : (failureReason ?? this.failureReason),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'revision': revision,
        'operationId': operationId,
        'prayerId': prayerId.key,
        'sourceMode': sourceMode.key,
        'targetMode': targetMode.key,
        'requestedAt': requestedAt.toIso8601String(),
        'protectedAlarmEpoch': protectedAlarmEpoch?.toIso8601String(),
        'status': status.key,
        'failureReason': failureReason,
      };

  static PrayerAlertTransitionRecord? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final prayerId = PrayerId.fromKey(json['prayerId'] as String?);
    if (prayerId == null) return null;

    final sourceMode = PrayerAlarmType.fromKey(json['sourceMode'] as String?);
    final targetMode = PrayerAlarmType.fromKey(json['targetMode'] as String?);
    final requestedAtStr = json['requestedAt'] as String?;
    final requestedAt = requestedAtStr != null
        ? DateTime.tryParse(requestedAtStr) ?? DateTime.now()
        : DateTime.now();

    final protectedEpochStr = json['protectedAlarmEpoch'] as String?;
    final protectedAlarmEpoch = protectedEpochStr != null
        ? DateTime.tryParse(protectedEpochStr)
        : null;

    final status = TransitionStatus.fromKey(json['status'] as String?);

    return PrayerAlertTransitionRecord(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      revision: (json['revision'] as num?)?.toInt() ?? 1,
      operationId: json['operationId'] as String? ?? '',
      prayerId: prayerId,
      sourceMode: sourceMode,
      targetMode: targetMode,
      requestedAt: requestedAt,
      protectedAlarmEpoch: protectedAlarmEpoch,
      status: status,
      failureReason: json['failureReason'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrayerAlertTransitionRecord &&
          schemaVersion == other.schemaVersion &&
          revision == other.revision &&
          operationId == other.operationId &&
          prayerId == other.prayerId &&
          sourceMode == other.sourceMode &&
          targetMode == other.targetMode &&
          requestedAt == other.requestedAt &&
          protectedAlarmEpoch == other.protectedAlarmEpoch &&
          status == other.status &&
          failureReason == other.failureReason;

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        revision,
        operationId,
        prayerId,
        sourceMode,
        targetMode,
        requestedAt,
        protectedAlarmEpoch,
        status,
        failureReason,
      );

  @override
  String toString() =>
      'PrayerAlertTransitionRecord(prayer: ${prayerId.key}, rev: $revision, op: $operationId, ${sourceMode.key} -> ${targetMode.key}, status: ${status.key}, deferred: $protectedAlarmEpoch)';
}

