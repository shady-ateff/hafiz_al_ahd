<#
.SYNOPSIS
  Phase 2D.2-B1: Notification Delivery Pilot Verification Orchestrator on Xiaomi / Samsung.
  Proves that device_observer.ps1 accurately captures, identifies, and verifies:
  1. ScheduledNotificationReceiver in dumpsys alarm
  2. NotificationRecord and Notification Shade visibility in dumpsys notification
  3. Composite identity matching (Package, ID, Channel, Run Marker, Epoch)
  4. Latency measurement (delivery correctness separate from latency degradation)
  5. 6-point surgical cleanup via cancel(999902) without blanket wipes
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
Write-Host " Phase 2D.2-B1: Notification Observer & Harness Pilot Run" -ForegroundColor Cyan
Write-Host " Device: $DeviceId | Target ID: $TargetId (${HorizonSeconds}s) | Sibling ID: $SecondaryId (${SecondaryHorizonSeconds}s)" -ForegroundColor Cyan
Write-Host "=================================================================`n" -ForegroundColor Cyan

$safeDev = $DeviceId -replace "[:\/\\]", "_"
$runTs = (Get-Date).ToString("yyyyMMdd_HHmmss")

if (-not (Test-Path $EvidenceDir)) {
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
}

# -------------------------------------------------------------
# STEP 0: Capture Channel & Permission Profile (Condition C7)
# -------------------------------------------------------------
Write-Host "[STEP 0] Inspecting Notification Channels & App Permissions..." -ForegroundColor Yellow
$profileFile = powershell -ExecutionPolicy Bypass -File .\scripts\device_observer.ps1 -DeviceId $DeviceId -PackageName $PackageName -Action profile-notification-channel -ChannelId $ChannelId
Write-Host "Channel profile captured: $profileFile`n"

# -------------------------------------------------------------
# STEP 1: Preflight Verification (Target must be ABSENT)
# -------------------------------------------------------------
Write-Host "[STEP 1] Preflight Verification: Ensuring ID #$TargetId is absent..." -ForegroundColor Yellow
$preflightNotif = powershell -ExecutionPolicy Bypass -File .\scripts\device_observer.ps1 -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification -TargetId $TargetId -ChannelId $ChannelId
$preflightAlarm = powershell -ExecutionPolicy Bypass -File .\scripts\device_observer.ps1 -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification-alarm -TargetId $TargetId

Write-Host "Preflight check completed.`n"

# -------------------------------------------------------------
# STEP 2: Clear Logcat & Launch Delivery App Harness
# -------------------------------------------------------------
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

Write-Host "[STEP 2] Clearing device logcat buffer..." -ForegroundColor Yellow
adb -s $DeviceId logcat -c

Write-Host "[STEP 2] Launching Phase 2D.2 Delivery Harness (Target: ${HorizonSeconds}s, Sibling: ${SecondaryHorizonSeconds}s)..." -ForegroundColor Yellow
$testJob = Start-Job -ScriptBlock {
    param($dev, $workDir, $tid, $horiz, $chid, $secId, $secHoriz)
    Set-Location $workDir
    flutter run -d $dev -t integration_test/phase_2d_2_delivery_app.dart --dart-define=TARGET_ID=$tid --dart-define=HORIZON_SEC=$horiz --dart-define=CHANNEL_ID=$chid --dart-define=SCHEDULE_SECONDARY=true --dart-define=SECONDARY_ID=$secId --dart-define=SECONDARY_HORIZON_SEC=$secHoriz --no-pub
} -ArgumentList $DeviceId, $projectRoot, $TargetId, $HorizonSeconds, $ChannelId, $SecondaryId, $SecondaryHorizonSeconds

$scheduledEvent = $null
$timeoutSeconds = 120
$sw = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "Waiting for [PHASE_2D_NOTIF_SCHEDULED] event from harness..." -ForegroundColor Yellow
while ($sw.Elapsed.TotalSeconds -lt $timeoutSeconds -and $null -eq $scheduledEvent) {
    Start-Sleep -Milliseconds 800
    
    # Query logcat directly for instantaneous capture
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
# STEP 3: Mid-Flight AlarmManager Verification (Condition C4)
# -------------------------------------------------------------
Write-Host "`n[STEP 3] Mid-flight AlarmManager verification (querying ScheduledNotificationReceiver)..." -ForegroundColor Yellow
$alarmEvidenceRaw = powershell -ExecutionPolicy Bypass -File .\scripts\device_observer.ps1 -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification-alarm -ScheduledEpochMs $scheduledEpochMs -TargetId $TargetId
$alarmEvidenceFile = ($alarmEvidenceRaw | Where-Object { $_ -match "target_notification_alarm_.*\.json" } | Select-Object -Last 1)
if ($alarmEvidenceFile) { $alarmEvidenceFile = $alarmEvidenceFile.Trim() }
$alarmEvidence = Get-Content $alarmEvidenceFile | ConvertFrom-Json

Write-Host "Target Alarm Matched:    $($alarmEvidence.target_notification_alarm_matched) | Classification: $($alarmEvidence.state_classification)" -ForegroundColor $(if ($alarmEvidence.target_notification_alarm_matched) { "Green" } else { "Red" })

# Also verify secondary alarm scheduled in AlarmManager
if ($secondaryEpochMs -gt 0) {
    $secAlarmRaw = powershell -ExecutionPolicy Bypass -File .\scripts\device_observer.ps1 -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification-alarm -ScheduledEpochMs $secondaryEpochMs -TargetId $SecondaryId
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
Write-Host "`n[STEP 4] Waiting for delivery window (Remaining: $remainingMs ms)..." -ForegroundColor Yellow

if ($remainingMs -gt 0) {
    Start-Sleep -Milliseconds ($remainingMs + 3000) # Wait until epoch + 3s buffer
} else {
    Start-Sleep -Seconds 3
}

Write-Host "[STEP 4] Verifying NotificationManager state (dumpsys notification)..." -ForegroundColor Yellow
$notifEvidenceRaw = powershell -ExecutionPolicy Bypass -File .\scripts\device_observer.ps1 -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification -TargetId $TargetId -ChannelId $ChannelId -RunMarker $runMarker -Title $targetTitle -ScheduledEpochMs $scheduledEpochMs
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
# STEP 5: Stop Delivery App & Run Surgical Cleanup Harness for Target Only (Condition C5 Non-Interference)
# -------------------------------------------------------------
Write-Host "`n[STEP 5] Stopping delivery app job..." -ForegroundColor Yellow
Stop-Job $testJob | Out-Null
Remove-Job $testJob | Out-Null

Write-Host "[STEP 5] Running Surgical Cleanup Harness for Target ONLY (cancel($TargetId), leaving Sibling #$SecondaryId intact)..." -ForegroundColor Yellow
adb -s $DeviceId logcat -c

$cleanupJob = Start-Job -ScriptBlock {
    param($dev, $workDir, $tid)
    Set-Location $workDir
    flutter run -d $dev -t integration_test/phase_2d_2_cleanup_app.dart --dart-define=TARGET_ID=$tid --dart-define=CLEAN_SECONDARY=false --no-pub
} -ArgumentList $DeviceId, $projectRoot, $TargetId

$cleanupEvent = $null
$swCleanup = [System.Diagnostics.Stopwatch]::StartNew()
while ($swCleanup.Elapsed.TotalSeconds -lt 120 -and $null -eq $cleanupEvent) {
    Start-Sleep -Milliseconds 800
    $logcatLines = adb -s $DeviceId logcat -d -v time "*:S" "flutter:I" "flutter:V"
    $matchLine = $logcatLines | Select-String -Pattern "\[PHASE_2D_NOTIF_CLEANUP_COMPLETED\]\s*(\{.*\})" | Select-Object -Last 1
    if (-not $matchLine) {
        $jobOutput = Receive-Job -Job $cleanupJob -Keep
        $matchLine = $jobOutput | Select-String -Pattern "\[PHASE_2D_NOTIF_CLEANUP_COMPLETED\]\s*(\{.*\})" | Select-Object -Last 1
    }
    if ($matchLine) {
        $jsonStr = $matchLine.Matches[0].Groups[1].Value
        try {
            $cleanupEvent = $jsonStr | ConvertFrom-Json
            Write-Host "SUCCESS: Surgical cleanup harness completed successfully!" -ForegroundColor Green
            break
        } catch {}
    }
}

Stop-Job $cleanupJob | Out-Null
Remove-Job $cleanupJob | Out-Null

Write-Host "[STEP 5] Host-side 6-point verification of surgical cleanup (Proving Non-Interference with #$SecondaryId)..." -ForegroundColor Yellow
$cleanupEvidenceRaw = powershell -ExecutionPolicy Bypass -File .\scripts\device_observer.ps1 -DeviceId $DeviceId -PackageName $PackageName -Action verify-notification-cleanup -TargetId $TargetId -SecondaryId $SecondaryId -ScheduledEpochMs $scheduledEpochMs -SecondaryEpochMs $secondaryEpochMs
$cleanupEvidenceFile = ($cleanupEvidenceRaw | Where-Object { $_ -match "notification_cleanup_.*\.json" } | Select-Object -Last 1)
if ($cleanupEvidenceFile) { $cleanupEvidenceFile = $cleanupEvidenceFile.Trim() }
$cleanupEvidence = Get-Content $cleanupEvidenceFile | ConvertFrom-Json

Write-Host "Target ($TargetId) Notification Absent: $($cleanupEvidence.point1_target_notification_record_absent)" -ForegroundColor $(if ($cleanupEvidence.point1_target_notification_record_absent) { "Green" } else { "Red" })
Write-Host "Target ($TargetId) Alarm Absent:        $($cleanupEvidence.point2_target_notification_alarm_absent)" -ForegroundColor $(if ($cleanupEvidence.point2_target_notification_alarm_absent) { "Green" } else { "Red" })
Write-Host "Sibling ($SecondaryId) Intact:         $($cleanupEvidence.point3_secondary_notification_intact) (Notif: $($cleanupEvidence.point3_secondary_in_notification_manager), Alarm: $($cleanupEvidence.point3_secondary_in_alarm_manager))" -ForegroundColor $(if ($cleanupEvidence.point3_secondary_notification_intact) { "Green" } else { "Red" })
Write-Host "Cleanup Verdict:                      $($cleanupEvidence.point6_surgical_cleanup_verdict)" -ForegroundColor $(if ($cleanupEvidence.point6_surgical_cleanup_verdict -match "PASS") { "Green" } else { "Red" })

# -------------------------------------------------------------
# STEP 5b: Tear Down Sibling Notification Cleanly
# -------------------------------------------------------------
Write-Host "`n[STEP 5b] Tearing down Sibling Notification #$SecondaryId to leave device completely clean..." -ForegroundColor Yellow
$cleanupSecJob = Start-Job -ScriptBlock {
    param($dev, $workDir, $tid)
    Set-Location $workDir
    flutter run -d $dev -t integration_test/phase_2d_2_cleanup_app.dart --dart-define=TARGET_ID=$tid --dart-define=CLEAN_SECONDARY=false --no-pub
} -ArgumentList $DeviceId, $projectRoot, $SecondaryId
Wait-Job $cleanupSecJob -Timeout 120 | Out-Null
Stop-Job $cleanupSecJob | Out-Null
Remove-Job $cleanupSecJob | Out-Null
Write-Host "Sibling teardown complete.`n"

# -------------------------------------------------------------
# STEP 6: Compile Consolidated Pilot Report
# -------------------------------------------------------------
$pilotVerdict = "PILOT_VERIFICATION_FAIL"
if ($alarmEvidence.target_notification_alarm_matched -and 
    $notifEvidence.tri_state_delivery.is_posted_in_os -and 
    $cleanupEvidence.point6_surgical_cleanup_verdict -eq "SURGICAL_CLEANUP_NON_INTERFERENCE_PASS") {
    $pilotVerdict = "PILOT_VERIFICATION_PASS"
}

$consolidatedPilot = [ordered]@{
    scenario_id = "2D.2.B1.NotificationPilotVerification"
    calibration_version = "B1.1_Calibrated"
    device_id = $DeviceId
    target_id = $TargetId
    sibling_id = $SecondaryId
    scheduled_epoch_ms = $scheduledEpochMs
    sibling_epoch_ms = $secondaryEpochMs
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
    verdict = $pilotVerdict
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
}

$pilotReportFile = Join-Path $EvidenceDir "pilot_2d_2_${safeDev}_${runTs}.json"
$consolidatedPilot | ConvertTo-Json -Depth 6 | Out-File -FilePath $pilotReportFile -Encoding utf8

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " Phase 2D.2-B1 Pilot Verification Verdict: $($consolidatedPilot.verdict)" -ForegroundColor $(if ($consolidatedPilot.verdict -eq "PILOT_VERIFICATION_PASS") { "Green" } else { "Red" })
Write-Host " Consolidated Pilot Report written to: $pilotReportFile" -ForegroundColor Cyan
Write-Host "=================================================================`n" -ForegroundColor Cyan
