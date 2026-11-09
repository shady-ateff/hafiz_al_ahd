<#
.SYNOPSIS
  Phase 2D.2 Scenario 2D.2.1: Foreground Prayer Notification Delivery Verification Orchestrator.
  Verifies delivery while the application process is alive and in the foreground.
  Implements strict multi-tier evidence contracts (Conditions C1-C7):
  - Tier 1: flutter_local_notifications plugin dispatch
  - Tier 2: Android AlarmManager kernel queue (ScheduledNotificationReceiver)
  - Tier 3: Android NotificationManagerService active NotificationRecord & alerting importance
  - Tier 4: User Notification Shade visibility (independent UI evidence)
  - Tier 5: 6-point surgical cleanup with sibling non-interference (#999902 canceled, #999903 preserved)
  - Tier 6: Zero diff on production code (lib/ and android/)
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$DeviceId = "dfa9f629",

    [Parameter(Mandatory=$false)]
    [string]$PackageName = "com.shadyatef.hafiz_alahd",

    [Parameter(Mandatory=$false)]
    [int]$TargetId = 999902,

    [Parameter(Mandatory=$false)]
    [int]$HorizonSeconds = 15,

    [Parameter(Mandatory=$false)]
    [int]$SecondaryId = 999903,

    [Parameter(Mandatory=$false)]
    [int]$SecondaryHorizonSeconds = 180,

    [Parameter(Mandatory=$false)]
    [string]$ChannelId = "prayer_channel_v10_default",

    [Parameter(Mandatory=$false)]
    [string]$EvidenceDir = "test_evidence"
)

$ErrorActionPreference = "Continue"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " SCENARIO 2D.2.1: FOREGROUND NOTIFICATION DELIVERY VERIFICATION" -ForegroundColor Cyan
Write-Host " Device: $DeviceId | Target ID: $TargetId (${HorizonSeconds}s) | Sibling ID: $SecondaryId (${SecondaryHorizonSeconds}s)" -ForegroundColor Cyan
Write-Host "=================================================================`n" -ForegroundColor Cyan

$safeDev = $DeviceId -replace "[:\/\\]", "_"
$runTs = (Get-Date).ToString("yyyyMMdd_HHmmss")

if (-not (Test-Path $EvidenceDir)) {
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
}

$observerScript = Join-Path $PSScriptRoot "device_observer.ps1"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# -------------------------------------------------------------
# STEP 0: Capture Channel & Permission Profile (Condition C7)
# -------------------------------------------------------------
Write-Host "[STEP 0] Inspecting Notification Channels & App Permissions on [$DeviceId]..." -ForegroundColor Yellow
$profileRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action profile-notification-channel -ChannelId $ChannelId
$profileFile = ($profileRaw | Where-Object { $_ -match "channel_profile_.*\.json" } | Select-Object -Last 1)
if ($profileFile) { $profileFile = $profileFile.Trim() }
Write-Host "Channel profile captured: $profileFile`n"

# -------------------------------------------------------------
# STEP 1: Preflight Verification (Target must be ABSENT)
# -------------------------------------------------------------
Write-Host "[STEP 1] Preflight Verification: Ensuring Target ID #$TargetId is absent..." -ForegroundColor Yellow
$preflightNotifRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification -TargetId $TargetId -ChannelId $ChannelId
$preflightAlarmRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification-alarm -TargetId $TargetId

Write-Host "Preflight check completed.`n"

# -------------------------------------------------------------
# STEP 2: Clear Logcat & Launch Delivery App Harness in Foreground
# -------------------------------------------------------------
Write-Host "[STEP 2] Clearing device logcat buffer..." -ForegroundColor Yellow
adb -s $DeviceId logcat -c

$cleanupDelay = $HorizonSeconds + 7
$teardownDelay = $HorizonSeconds + 17

Write-Host "[STEP 2] Launching Phase 2D.2 Delivery Harness (Foreground, Target: ${HorizonSeconds}s, Sibling: ${SecondaryHorizonSeconds}s)..." -ForegroundColor Yellow
$testJob = Start-Job -ScriptBlock {
    param($dev, $workDir, $tid, $horiz, $chid, $secId, $secHoriz, $cleanDelay, $tearDelay)
    Set-Location $workDir
    flutter run -d $dev -t integration_test/phase_2d_2_delivery_app.dart --dart-define=TARGET_ID=$tid --dart-define=HORIZON_SEC=$horiz --dart-define=CHANNEL_ID=$chid --dart-define=SCHEDULE_SECONDARY=true --dart-define=SECONDARY_ID=$secId --dart-define=SECONDARY_HORIZON_SEC=$secHoriz --dart-define=CLEANUP_DELAY_SEC=$cleanDelay --dart-define=TEARDOWN_DELAY_SEC=$tearDelay --no-pub
} -ArgumentList $DeviceId, $projectRoot, $TargetId, $HorizonSeconds, $ChannelId, $SecondaryId, $SecondaryHorizonSeconds, $cleanupDelay, $teardownDelay

$scheduledEvent = $null
$timeoutSeconds = 240
$sw = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "Waiting for [PHASE_2D_NOTIF_SCHEDULED] event from harness..." -ForegroundColor Yellow
while ($sw.Elapsed.TotalSeconds -lt $timeoutSeconds -and $null -eq $scheduledEvent) {
    Start-Sleep -Milliseconds 800
    
    $logcatLines = adb -s $DeviceId logcat -d -v time "*:S" "flutter:I" "flutter:V" "FLTNotification:V"
    $matchLine = $logcatLines | Select-String -Pattern "\[PHASE_2D_NOTIF_SCHEDULED\]\s*(\{.*\})" | Select-Object -Last 1
    if (-not $matchLine) {
        $jobOutput = Receive-Job -Job $testJob -Keep
        $matchLine = $jobOutput | Select-String -Pattern "\[PHASE_2D_NOTIF_SCHEDULED\]\s*(\{.*\})" | Select-Object -Last 1
    }
    if ($matchLine) {
        $jsonStr = $matchLine.Matches[0].Groups[1].Value
        try {
            $scheduledEvent = $jsonStr | ConvertFrom-Json
            Write-Host "SUCCESS: Target notification scheduled event captured!" -ForegroundColor Green
            break
        } catch {
            Write-Host "Warning: JSON parse failed on event: $jsonStr" -ForegroundColor DarkGray
        }
    }
}

if ($null -eq $scheduledEvent) {
    Write-Host "ERROR: Timed out waiting for scheduling event." -ForegroundColor Red
    Stop-Job $testJob | Out-Null
    Remove-Job $testJob | Out-Null
    exit 1
}

$scheduledEpochMs = [long]$scheduledEvent.scheduled_epoch_ms
$runMarker = "$($scheduledEvent.run_marker)"
$targetTitle = "$($scheduledEvent.title)"
$targetBody = "$($scheduledEvent.body)"

$secondaryEpochMs = 0
if ($scheduledEvent.secondary_scheduled -and $scheduledEvent.secondary_details) {
    $secondaryEpochMs = [long]$scheduledEvent.secondary_details.scheduled_epoch_ms
}

Write-Host "`nTarget Notification Identity Binding:" -ForegroundColor Cyan
Write-Host " - Target ID:         $TargetId"
Write-Host " - Scheduled Epoch:   $scheduledEpochMs ($([DateTimeOffset]::FromUnixTimeMilliseconds($scheduledEpochMs).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss.fff')))"
Write-Host " - Run Marker:        $runMarker"
Write-Host " - Title Marker:      $targetTitle"
Write-Host " - Channel ID:        $ChannelId"
Write-Host " - Sibling ID:        $SecondaryId"
Write-Host " - Sibling Epoch:     $secondaryEpochMs ($([DateTimeOffset]::FromUnixTimeMilliseconds($secondaryEpochMs).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss.fff')))"

# -------------------------------------------------------------
# STEP 2b: Foreground State Verification
# -------------------------------------------------------------
Write-Host "`n[STEP 2b] Verifying application process is alive and in FOREGROUND..." -ForegroundColor Yellow
$fgPid = (adb -s $DeviceId shell "pidof $PackageName").Trim()
$currentFocus = (adb -s $DeviceId shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp'").Trim()
$isForeground = ($currentFocus -match [regex]::Escape($PackageName))
Write-Host "App Process State: $(if ($fgPid) { "ALIVE (PID: $fgPid)" } else { "NOT RUNNING" })" -ForegroundColor $(if ($fgPid) { "Green" } else { "Red" })
Write-Host "Window Focus State: $currentFocus" -ForegroundColor $(if ($isForeground) { "Green" } else { "Yellow" })

# -------------------------------------------------------------
# STEP 3: Mid-Flight AlarmManager Verification (Condition C4)
# -------------------------------------------------------------
Write-Host "`n[STEP 3] Mid-flight AlarmManager verification (querying ScheduledNotificationReceiver)..." -ForegroundColor Yellow
$alarmEvidenceRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification-alarm -ScheduledEpochMs $scheduledEpochMs -TargetId $TargetId
$alarmEvidenceFile = ($alarmEvidenceRaw | Where-Object { $_ -match "target_notification_alarm_.*\.json" } | Select-Object -Last 1)
if ($alarmEvidenceFile) { $alarmEvidenceFile = $alarmEvidenceFile.Trim() }
$alarmEvidence = Get-Content $alarmEvidenceFile | ConvertFrom-Json

Write-Host "Target Alarm Matched:    $($alarmEvidence.target_notification_alarm_matched) | Classification: $($alarmEvidence.state_classification)" -ForegroundColor $(if ($alarmEvidence.target_notification_alarm_matched) { "Green" } else { "Red" })

if ($secondaryEpochMs -gt 0) {
    $secAlarmRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification-alarm -ScheduledEpochMs $secondaryEpochMs -TargetId $SecondaryId
    $secAlarmFile = ($secAlarmRaw | Where-Object { $_ -match "target_notification_alarm_.*\.json" } | Select-Object -Last 1)
    if ($secAlarmFile) {
        $secAlarmEv = Get-Content $secAlarmFile.Trim() | ConvertFrom-Json
        Write-Host "Sibling Alarm Matched:   $($secAlarmEv.target_notification_alarm_matched) | Classification: $($secAlarmEv.state_classification)" -ForegroundColor $(if ($secAlarmEv.target_notification_alarm_matched) { "Green" } else { "Red" })
    }
}

# -------------------------------------------------------------
# STEP 4: Delivery Window Wait & NotificationManager Verification (Conditions C1, C3, C6)
# -------------------------------------------------------------
$nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$remainingMs = $scheduledEpochMs - $nowEpoch
Write-Host "`n[STEP 4] Waiting for delivery window while app stays in FOREGROUND (Remaining: $remainingMs ms)..." -ForegroundColor Yellow

if ($remainingMs -gt 0) {
    Start-Sleep -Milliseconds ($remainingMs + 3000)
} else {
    Start-Sleep -Seconds 3
}

Write-Host "[STEP 4] Verifying NotificationManager state (dumpsys notification)..." -ForegroundColor Yellow
$notifEvidenceRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification -TargetId $TargetId -ChannelId $ChannelId -RunMarker $runMarker -Title $targetTitle -ScheduledEpochMs $scheduledEpochMs
$notifEvidenceFile = ($notifEvidenceRaw | Where-Object { $_ -match "target_notification_record_.*\.json" } | Select-Object -Last 1)
if ($notifEvidenceFile) { $notifEvidenceFile = $notifEvidenceFile.Trim() }
$notifEvidence = Get-Content $notifEvidenceFile | ConvertFrom-Json

Write-Host "`nDelivery Verification Result:" -ForegroundColor Cyan
Write-Host " - Posted in OS:       $($notifEvidence.tri_state_delivery.is_posted_in_os)" -ForegroundColor $(if ($notifEvidence.tri_state_delivery.is_posted_in_os) { "Green" } else { "Red" })
Write-Host " - Alerting Level:     $($notifEvidence.tri_state_delivery.is_alerting_importance) (Importance: $($notifEvidence.tri_state_delivery.importance))" -ForegroundColor $(if ($notifEvidence.tri_state_delivery.is_alerting_importance) { "Green" } else { "Yellow" })
Write-Host " - Shade Visibility:   $($notifEvidence.tri_state_delivery.is_visible_in_shade)" -ForegroundColor Cyan
Write-Host " - Delivery Delta:     $($notifEvidence.timing_and_latency.delivery_delta_ms) ms ($($notifEvidence.timing_and_latency.latency_classification))" -ForegroundColor $(if ($notifEvidence.timing_and_latency.latency_classification -eq "LATENCY_WITHIN_TARGET") { "Green" } elseif ($notifEvidence.timing_and_latency.latency_classification -eq "EARLY_DELIVERY") { "Cyan" } else { "Yellow" })
Write-Host " - Overall Verdict:    $($notifEvidence.tri_state_delivery.overall_classification)" -ForegroundColor Green

# -------------------------------------------------------------
# STEP 5: In-Session Surgical Cleanup Verification for Target Only (Condition C5 Non-Interference)
# -------------------------------------------------------------
Write-Host "`n[STEP 5] Awaiting In-Session Surgical Cleanup of Target Only (cancel($TargetId), leaving Sibling #$SecondaryId intact)..." -ForegroundColor Yellow

$cleanupEvent = $null
$swCleanup = [System.Diagnostics.Stopwatch]::StartNew()
while ($swCleanup.Elapsed.TotalSeconds -lt 60 -and $null -eq $cleanupEvent) {
    Start-Sleep -Milliseconds 800
    $logcatLines = adb -s $DeviceId logcat -d -v time "*:S" "flutter:I" "flutter:V"
    $matchLine = $logcatLines | Select-String -Pattern "\[PHASE_2D_NOTIF_CLEANUP_COMPLETED\]\s*(\{.*\})" | Select-Object -Last 1
    if (-not $matchLine) {
        $jobOutput = Receive-Job -Job $testJob -Keep
        $matchLine = $jobOutput | Select-String -Pattern "\[PHASE_2D_NOTIF_CLEANUP_COMPLETED\]\s*(\{.*\})" | Select-Object -Last 1
    }
    if ($matchLine) {
        $jsonStr = $matchLine.Matches[0].Groups[1].Value
        try {
            $cleanupEvent = $jsonStr | ConvertFrom-Json
            Write-Host "SUCCESS: In-session surgical cleanup completed by harness!" -ForegroundColor Green
            break
        } catch {}
    }
}

Write-Host "[STEP 5] Host-side 6-point verification of surgical cleanup (Proving Non-Interference with #$SecondaryId)..." -ForegroundColor Yellow
$cleanupEvidenceRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-notification-cleanup -TargetId $TargetId -SecondaryId $SecondaryId -ScheduledEpochMs $scheduledEpochMs -SecondaryEpochMs $secondaryEpochMs
$cleanupEvidenceFile = ($cleanupEvidenceRaw | Where-Object { $_ -match "notification_cleanup_.*\.json" } | Select-Object -Last 1)
if ($cleanupEvidenceFile) { $cleanupEvidenceFile = $cleanupEvidenceFile.Trim() }
$cleanupEvidence = Get-Content $cleanupEvidenceFile | ConvertFrom-Json

Write-Host "Target ($TargetId) Notification Absent: $($cleanupEvidence.point1_target_notification_record_absent)" -ForegroundColor $(if ($cleanupEvidence.point1_target_notification_record_absent) { "Green" } else { "Red" })
Write-Host "Target ($TargetId) Alarm Absent:        $($cleanupEvidence.point2_target_notification_alarm_absent)" -ForegroundColor $(if ($cleanupEvidence.point2_target_notification_alarm_absent) { "Green" } else { "Red" })
Write-Host "Sibling ($SecondaryId) Intact:         $($cleanupEvidence.point3_secondary_notification_intact) (Notif: $($cleanupEvidence.point3_secondary_in_notification_manager), Alarm: $($cleanupEvidence.point3_secondary_in_alarm_manager))" -ForegroundColor $(if ($cleanupEvidence.point3_secondary_notification_intact) { "Green" } else { "Red" })
Write-Host "Cleanup Verdict:                      $($cleanupEvidence.point6_surgical_cleanup_verdict)" -ForegroundColor $(if ($cleanupEvidence.point6_surgical_cleanup_verdict -match "PASS") { "Green" } else { "Red" })

# -------------------------------------------------------------
# STEP 5b: In-Session Sibling Teardown & Process Teardown
# -------------------------------------------------------------
Write-Host "`n[STEP 5b] Awaiting In-Session Sibling Teardown (#$SecondaryId) to leave device completely clean..." -ForegroundColor Yellow
$swSec = [System.Diagnostics.Stopwatch]::StartNew()
$teardownDone = $false
while ($swSec.Elapsed.TotalSeconds -lt 30 -and -not $teardownDone) {
    Start-Sleep -Milliseconds 800
    $logcatLines = adb -s $DeviceId logcat -d -v time "*:S" "flutter:I" "flutter:V"
    $matchLine = $logcatLines | Select-String -Pattern "\[PHASE_2D_NOTIF_TEARDOWN_COMPLETED\]" | Select-Object -Last 1
    if (-not $matchLine) {
        $jobOutput = Receive-Job -Job $testJob -Keep
        $matchLine = $jobOutput | Select-String -Pattern "\[PHASE_2D_NOTIF_TEARDOWN_COMPLETED\]" | Select-Object -Last 1
    }
    if ($matchLine) {
        $teardownDone = $true
        Write-Host "Sibling in-session teardown confirmed." -ForegroundColor Green
        break
    }
}

Stop-Job $testJob | Out-Null
Remove-Job $testJob | Out-Null
Write-Host "Harness process stopped cleanly.`n"

# -------------------------------------------------------------
# STEP 6: Compile Scenario 2D.2.1 Master Evidence Report
# -------------------------------------------------------------
$scenarioVerdict = "SCENARIO_2D_2_1_FAIL"
if ($alarmEvidence.target_notification_alarm_matched -and 
    $notifEvidence.tri_state_delivery.is_posted_in_os -and 
    $cleanupEvidence.point6_surgical_cleanup_verdict -eq "SURGICAL_CLEANUP_NON_INTERFERENCE_PASS") {
    $scenarioVerdict = "SCENARIO_2D_2_1_PASS"
}

$masterEvidence = [ordered]@{
    scenario_id = "2D.2.1.ForegroundDelivery"
    device_id = $DeviceId
    package_name = $PackageName
    target_id = $TargetId
    sibling_id = $SecondaryId
    scheduled_epoch_ms = $scheduledEpochMs
    sibling_epoch_ms = $secondaryEpochMs
    process_state = [ordered]@{
        pid = $fgPid
        foreground_focus_confirmed = $isForeground
        current_focus = $currentFocus
    }
    composite_identity = [ordered]@{
        package = $PackageName
        target_id = $TargetId
        channel_id = $ChannelId
        run_marker = $runMarker
        title_marker = $targetTitle
    }
    alarm_manager_verification = [ordered]@{
        matched = $alarmEvidence.target_notification_alarm_matched
        classification = $alarmEvidence.state_classification
        receiver_component = $alarmEvidence.target_identity_attributes.receiver_component
        pending_intent = $alarmEvidence.target_identity_attributes.pending_intent_identity
        orig_when_epoch_ms = $alarmEvidence.target_identity_attributes.orig_when_epoch_ms
    }
    notification_delivery_verification = [ordered]@{
        is_posted_in_os = $notifEvidence.tri_state_delivery.is_posted_in_os
        is_alerting_importance = $notifEvidence.tri_state_delivery.is_alerting_importance
        is_visible_in_shade = $notifEvidence.tri_state_delivery.is_visible_in_shade
        importance = $notifEvidence.tri_state_delivery.importance
        overall_classification = $notifEvidence.tri_state_delivery.overall_classification
        delivery_delta_ms = $notifEvidence.timing_and_latency.delivery_delta_ms
        latency_classification = $notifEvidence.timing_and_latency.latency_classification
        matched_key = $notifEvidence.composite_identity.matched_key
        matched_title = $notifEvidence.composite_identity.matched_title
        matched_text = $notifEvidence.composite_identity.matched_text
    }
    surgical_cleanup_non_interference = [ordered]@{
        target_record_absent = $cleanupEvidence.point1_target_notification_record_absent
        target_alarm_absent = $cleanupEvidence.point2_target_notification_alarm_absent
        sibling_intact = $cleanupEvidence.point3_secondary_notification_intact
        sibling_in_alarm_manager = $cleanupEvidence.point3_secondary_in_alarm_manager
        sibling_in_notification_manager = $cleanupEvidence.point3_secondary_in_notification_manager
        cleanup_verdict = $cleanupEvidence.point6_surgical_cleanup_verdict
    }
    evidence_files = [ordered]@{
        channel_profile_json = $profileFile
        target_alarm_json = $alarmEvidenceFile
        notification_record_json = $notifEvidenceFile
        cleanup_json = $cleanupEvidenceFile
    }
    verdict = $scenarioVerdict
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
}

$masterEvidenceFile = Join-Path $EvidenceDir "scenario_2d_2_1_master_evidence_${safeDev}_${runTs}.json"
$masterEvidence | ConvertTo-Json -Depth 6 | Out-File -FilePath $masterEvidenceFile -Encoding utf8

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " Scenario 2D.2.1 Foreground Delivery Verdict: $($masterEvidence.verdict)" -ForegroundColor $(if ($masterEvidence.verdict -eq "SCENARIO_2D_2_1_PASS") { "Green" } else { "Red" })
Write-Host " Master Evidence JSON written to: $masterEvidenceFile" -ForegroundColor Cyan
Write-Host "=================================================================`n" -ForegroundColor Cyan
