<#
.SYNOPSIS
  Phase 2D.2 Scenario 2D.2.3 End-to-End Orchestrator:
  Process-Death Prayer Notification Delivery Verification.
  Coordinates with scripts/device_observer.ps1 to enforce Conditions C1 through C7.
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$DeviceId = "dfa9f629",

    [Parameter(Mandatory=$false)]
    [string]$PackageName = "com.shadyatef.hafiz_alahd",

    [Parameter(Mandatory=$false)]
    [int]$TargetId = 999902,

    [Parameter(Mandatory=$false)]
    [int]$HorizonSeconds = 55,

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

$safeDeviceId = $DeviceId -replace "[:\/\\]", "_"
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
if (-not (Test-Path $EvidenceDir)) {
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
}

$observerScript = Join-Path $PSScriptRoot "device_observer.ps1"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " SCENARIO 2D.2.3: PROCESS-DEATH NOTIFICATION DELIVERY VERIFICATION" -ForegroundColor Cyan
Write-Host " Device: $DeviceId | Target ID: $TargetId (${HorizonSeconds}s) | Sibling ID: $SecondaryId (${SecondaryHorizonSeconds}s)" -ForegroundColor Cyan
Write-Host " Observer: $observerScript" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# -------------------------------------------------------------
# STEP 0: Inspect Notification Channels & Preflight Cleanliness
# -------------------------------------------------------------
Write-Host "`n[STEP 0] Inspecting Notification Channels & App Permissions on [$DeviceId]..." -ForegroundColor Yellow
$profileEvidenceRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action profile-notification-channel -ChannelId $ChannelId
$profileEvidenceFile = ($profileEvidenceRaw | Where-Object { $_ -match "channel_profile_.*\.json" } | Select-Object -Last 1)
if ($profileEvidenceFile) {
    Write-Host "Channel profile captured: $profileEvidenceFile" -ForegroundColor Green
}

Write-Host "`n[STEP 1] Preflight Verification: Ensuring Target ID #$TargetId and Sibling #$SecondaryId are absent..." -ForegroundColor Yellow
$preflightAlarmRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification-alarm -TargetId $TargetId -ScheduledEpochMs 0
$preflightAlarmFile = ($preflightAlarmRaw | Where-Object { $_ -match "target_notification_alarm_.*\.json" } | Select-Object -Last 1)
if ($preflightAlarmFile) {
    $preflightAlarm = Get-Content $preflightAlarmFile.Trim() | ConvertFrom-Json
    if ($preflightAlarm.target_notification_alarm_matched) {
        Write-Warning "Target Alarm #$TargetId already present preflight! Cleaning up..."
        adb -s $DeviceId shell "cmd notification cancel $PackageName $TargetId"
    }
}
Write-Host "Preflight check completed." -ForegroundColor Green

# -------------------------------------------------------------
# STEP 2: Clear device logcat buffer & Launch Harness
# -------------------------------------------------------------
Write-Host "`n[STEP 2] Clearing device logcat buffer..." -ForegroundColor Yellow
adb -s $DeviceId logcat -c

Write-Host "[STEP 2] Launching Phase 2D.2 Delivery Harness (Target: ${HorizonSeconds}s, Sibling: ${SecondaryHorizonSeconds}s)..." -ForegroundColor Yellow
$testJob = Start-Job -ScriptBlock {
    param($dev, $workDir, $tId, $hSec, $cId, $sId, $sSec)
    Set-Location $workDir
    flutter run -t integration_test/phase_2d_2_delivery_app.dart -d $dev --no-pub `
        --dart-define=TARGET_ID=$tId `
        --dart-define=HORIZON_SEC=$hSec `
        --dart-define=CHANNEL_ID=$cId `
        --dart-define=SCHEDULE_SECONDARY=true `
        --dart-define=SECONDARY_ID=$sId `
        --dart-define=SECONDARY_HORIZON_SEC=$sSec `
        --dart-define=CLEANUP_DELAY_SEC=0 `
        --dart-define=TEARDOWN_DELAY_SEC=0
} -ArgumentList $DeviceId, $projectRoot, $TargetId, $HorizonSeconds, $ChannelId, $SecondaryId, $SecondaryHorizonSeconds

Write-Host "Waiting for [PHASE_2D_NOTIF_SCHEDULED] event from harness..." -ForegroundColor Yellow
$scheduledEvent = $null
$timeoutSeconds = 240
$sw = [System.Diagnostics.Stopwatch]::StartNew()

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
    Write-Error "CRITICAL: Timed out waiting for scheduling event within 240s. Aborting."
    Stop-Job -Job $testJob -ErrorAction SilentlyContinue
    Remove-Job -Job $testJob -ErrorAction SilentlyContinue
    return
}

$scheduledEpochMs = [long]$scheduledEvent.scheduled_epoch_ms
$runMarker = "$($scheduledEvent.run_marker)"
$titleMarker = "$($scheduledEvent.title)"

$secondaryEpochMs = 0
if ($scheduledEvent.secondary_scheduled -and $scheduledEvent.secondary_details) {
    $secondaryEpochMs = [long]$scheduledEvent.secondary_details.scheduled_epoch_ms
}

Write-Host "`nTarget Notification Identity Binding:" -ForegroundColor Cyan
Write-Host " - Target ID:         $TargetId"
Write-Host " - Scheduled Epoch:   $scheduledEpochMs ($([DateTimeOffset]::FromUnixTimeMilliseconds($scheduledEpochMs).LocalDateTime))"
Write-Host " - Run Marker:        $runMarker"
Write-Host " - Title Marker:      $titleMarker"
Write-Host " - Channel ID:        $ChannelId"
Write-Host " - Sibling ID:        $SecondaryId"
Write-Host " - Sibling Epoch:     $secondaryEpochMs ($([DateTimeOffset]::FromUnixTimeMilliseconds($secondaryEpochMs).LocalDateTime))"

# -------------------------------------------------------------
# STEP 3: Pre-Kill State & AlarmManager Verification (Process ALIVE)
# -------------------------------------------------------------
Write-Host "`n[STEP 3] Capturing Pre-Kill Process State & Mid-Flight AlarmManager Registration..." -ForegroundColor Yellow
$pidPreKill = (adb -s $DeviceId shell "pidof $PackageName").Trim()
$pidPreKill = ($pidPreKill -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
Write-Host "Pre-Kill App Process State: ALIVE (PID: $pidPreKill)" -ForegroundColor Green

if ([string]::IsNullOrEmpty($pidPreKill)) {
    Write-Error "CRITICAL: Process is not alive before kill step. Aborting."
    Stop-Job -Job $testJob -ErrorAction SilentlyContinue
    Remove-Job -Job $testJob -ErrorAction SilentlyContinue
    return
}

# Verify Target & Sibling in AlarmManager pre-kill
$preKillTargetAlarmRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification-alarm -TargetId $TargetId -ScheduledEpochMs $scheduledEpochMs
$preKillTargetAlarmFile = ($preKillTargetAlarmRaw | Where-Object { $_ -match "target_notification_alarm_.*\.json" } | Select-Object -Last 1)
$preKillTargetAlarm = if ($preKillTargetAlarmFile) { Get-Content $preKillTargetAlarmFile.Trim() | ConvertFrom-Json } else { $null }

$preKillSiblingAlarmRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification-alarm -TargetId $SecondaryId -ScheduledEpochMs $secondaryEpochMs
$preKillSiblingAlarmFile = ($preKillSiblingAlarmRaw | Where-Object { $_ -match "target_notification_alarm_.*\.json" } | Select-Object -Last 1)
$preKillSiblingAlarm = if ($preKillSiblingAlarmFile) { Get-Content $preKillSiblingAlarmFile.Trim() | ConvertFrom-Json } else { $null }

Write-Host "Pre-Kill Target Alarm Matched:  $($preKillTargetAlarm.target_notification_alarm_matched) | OrigWhen: $($preKillTargetAlarm.target_identity_attributes.orig_when_epoch_ms)" -ForegroundColor Green
Write-Host "Pre-Kill Sibling Alarm Matched: $($preKillSiblingAlarm.target_notification_alarm_matched) | OrigWhen: $($preKillSiblingAlarm.target_identity_attributes.orig_when_epoch_ms)" -ForegroundColor Green

# -------------------------------------------------------------
# STEP 4: Remaining Time Guard Check (> 12,000 ms required)
# -------------------------------------------------------------
Write-Host "`n[STEP 4] Checking Remaining Time Guard before process termination..." -ForegroundColor Yellow
$nowEpoch = [long]([DateTimeOffset]::UtcNow).ToUnixTimeMilliseconds()
$remainingMs = $scheduledEpochMs - $nowEpoch
Write-Host "Target Epoch: $scheduledEpochMs | Current Epoch: $nowEpoch | Remaining: $remainingMs ms"

if ($remainingMs -lt 12000) {
    Write-Error "CRITICAL: Remaining time ($remainingMs ms) is less than 12000ms guard threshold. Aborting Scenario 2D.2.3."
    Stop-Job -Job $testJob -ErrorAction SilentlyContinue
    Remove-Job -Job $testJob -ErrorAction SilentlyContinue
    return
}
Write-Host "Remaining Time Guard PASSED ($remainingMs ms >= 12000 ms)." -ForegroundColor Green

# -------------------------------------------------------------
# STEP 5: Background App via KEYCODE_HOME
# -------------------------------------------------------------
Write-Host "`n[STEP 5] Moving application to background via KEYCODE_HOME..." -ForegroundColor Yellow
powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action background-app | Out-Null
Start-Sleep -Milliseconds 800

# Stop the host-side flutter run job so it doesn't hold ADB connections
Stop-Job -Job $testJob -ErrorAction SilentlyContinue
Remove-Job -Job $testJob -ErrorAction SilentlyContinue

# -------------------------------------------------------------
# STEP 6: Execute SIGKILL via run-as (Process Death)
# -------------------------------------------------------------
Write-Host "`n[STEP 6] Executing SIGKILL process termination (kill -9 $pidPreKill)..." -ForegroundColor Yellow
powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action kill-process | Out-Null
Start-Sleep -Milliseconds 800

# Secondary check if process is still running
$pidCheckRaw = adb -s $DeviceId shell "pidof $PackageName"
$pidCheck = if ($pidCheckRaw) { "$pidCheckRaw".Trim() } else { "" }
if ($pidCheck) {
    adb -s $DeviceId shell "kill -9 $pidPreKill"
    Start-Sleep -Milliseconds 500
}

# Confirm Process Death
$pidAfterKillRaw = adb -s $DeviceId shell "pidof $PackageName"
$pidAfterKill = if ($pidAfterKillRaw) { ("$pidAfterKillRaw" -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1) } else { "" }
if ($pidAfterKill) { $pidAfterKill = "$pidAfterKill".Trim() }
$isDead = [string]::IsNullOrEmpty($pidAfterKill)
Write-Host "Verification of process death: $(if ($isDead) { "CONFIRMED DEAD (PID is empty)" } else { "ALIVE (PID: $pidAfterKill)" })" -ForegroundColor $(if ($isDead) { "Green" } else { "Red" })

if (-not $isDead) {
    Write-Error "CRITICAL: Process failed to terminate via SIGKILL. Aborting."
    return
}

# -------------------------------------------------------------
# STEP 7: CRITICAL PROOF — Target Alarm Persistence in AlarmManager While Process is DEAD
# -------------------------------------------------------------
Write-Host "`n[STEP 7] CRITICAL TEST: Verifying Target Alarm Persistence in AlarmManager while Process is DEAD..." -ForegroundColor Yellow
$postKillTargetAlarmRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification-alarm -TargetId $TargetId -ScheduledEpochMs $scheduledEpochMs
$postKillTargetAlarmFile = ($postKillTargetAlarmRaw | Where-Object { $_ -match "target_notification_alarm_.*\.json" } | Select-Object -Last 1)
$postKillTargetAlarm = if ($postKillTargetAlarmFile) { Get-Content $postKillTargetAlarmFile.Trim() | ConvertFrom-Json } else { $null }

$postKillSiblingAlarmRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification-alarm -TargetId $SecondaryId -ScheduledEpochMs $secondaryEpochMs
$postKillSiblingAlarmFile = ($postKillSiblingAlarmRaw | Where-Object { $_ -match "target_notification_alarm_.*\.json" } | Select-Object -Last 1)
$postKillSiblingAlarm = if ($postKillSiblingAlarmFile) { Get-Content $postKillSiblingAlarmFile.Trim() | ConvertFrom-Json } else { $null }

Write-Host "Post-Kill Process State:          $($postKillTargetAlarm.process_state)" -ForegroundColor Green
Write-Host "Post-Kill Target Alarm Matched:   $($postKillTargetAlarm.target_notification_alarm_matched)" -ForegroundColor Green
Write-Host "Post-Kill Target Classification:  $($postKillTargetAlarm.state_classification)" -ForegroundColor Green
Write-Host "Post-Kill Sibling Alarm Matched:  $($postKillSiblingAlarm.target_notification_alarm_matched)" -ForegroundColor Green

$targetPersistenceProven = ($postKillTargetAlarm.target_notification_alarm_matched -and $postKillTargetAlarm.process_state -eq "DEAD")
Write-Host "`n>>> TARGET NOTIFICATION ALARM PERSISTENCE ACROSS PROCESS DEATH: $targetPersistenceProven <<<" -ForegroundColor $(if ($targetPersistenceProven) { "Green" } else { "Red" })

if (-not $targetPersistenceProven) {
    Write-Error "CRITICAL: Target Alarm not persisted across process death in AlarmManager! Aborting."
    return
}

# -------------------------------------------------------------
# STEP 8: Delivery Window Wait & Post-Death Notification Dispatch
# -------------------------------------------------------------
$nowEpoch = [long]([DateTimeOffset]::UtcNow).ToUnixTimeMilliseconds()
$waitMs = $scheduledEpochMs - $nowEpoch + 3000
if ($waitMs -gt 0) {
    Write-Host "`n[STEP 8] Awaiting delivery epoch while process remains dead (Waiting $([Math]::Round($waitMs / 1000, 1))s)..." -ForegroundColor Yellow
    Start-Sleep -Milliseconds $waitMs
}

# Check process state after trigger
$pidAfterTrigger = (adb -s $DeviceId shell "pidof $PackageName").Trim()
$pidAfterTrigger = ($pidAfterTrigger -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)

$processRecreationDetected = -not [string]::IsNullOrEmpty($pidAfterTrigger)
Write-Host "App Process State Post-Trigger: $(if ($processRecreationDetected) { "NEW PROCESS STARTED (PID: $pidAfterTrigger)" } else { "PROCESS REMAINED DEAD (PID: none)" })" -ForegroundColor Cyan

# Inspect Logcat for broadcast delivery
$logcatDispatch = (adb -s $DeviceId logcat -d -v time "*:S" "ScheduledNotificationReceiver:V" "NotificationManager:V" "ActivityManager:I" | Select-String -Pattern "ScheduledNotificationReceiver|Start proc.*$PackageName" | Select-Object -Last 10)
Write-Host "Logcat OS Dispatch Lines: $(@($logcatDispatch).Count) lines detected" -ForegroundColor Cyan
if (@($logcatDispatch).Count -gt 0) {
    $logcatDispatch | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
}

# Verify OS Notification Posting
Write-Host "`n[STEP 8] Verifying NotificationManager state and UI Shade visibility (dumpsys notification + uiautomator)..." -ForegroundColor Yellow
$notifEvidenceRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification -TargetId $TargetId -ChannelId $ChannelId -ScheduledEpochMs $scheduledEpochMs -RunMarker $runMarker
$notifEvidenceFile = ($notifEvidenceRaw | Where-Object { $_ -match "target_notification_record_.*\.json" } | Select-Object -Last 1)
$notifEvidence = if ($notifEvidenceFile) { Get-Content $notifEvidenceFile.Trim() | ConvertFrom-Json } else { $null }

Write-Host "`nDelivery Verification Result:" -ForegroundColor Cyan
Write-Host " - Posted in OS:       $($notifEvidence.tri_state_delivery.is_posted_in_os)" -ForegroundColor $(if ($notifEvidence.tri_state_delivery.is_posted_in_os) { "Green" } else { "Red" })
Write-Host " - Alerting Level:     $($notifEvidence.tri_state_delivery.is_alerting_importance) (Importance: $($notifEvidence.tri_state_delivery.importance))" -ForegroundColor $(if ($notifEvidence.tri_state_delivery.is_alerting_importance) { "Green" } else { "Red" })
Write-Host " - Shade Visibility:   $($notifEvidence.tri_state_delivery.is_visible_in_shade) ($($notifEvidence.tri_state_delivery.shade_verification_detail))" -ForegroundColor $(if ($notifEvidence.tri_state_delivery.is_visible_in_shade -eq $true) { "Green" } else { "Yellow" })
Write-Host " - Overall Verdict:    $($notifEvidence.tri_state_delivery.overall_classification)" -ForegroundColor Green

# Check AlarmManager post-trigger: Target must be absent (consumed), Sibling must be intact!
Write-Host "`n[STEP 8b] Verifying AlarmManager state post-trigger (Target consumed, Sibling intact)..." -ForegroundColor Yellow
$postTriggerSiblingAlarmRaw = powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification-alarm -TargetId $SecondaryId -ScheduledEpochMs $secondaryEpochMs
$postTriggerSiblingAlarmFile = ($postTriggerSiblingAlarmRaw | Where-Object { $_ -match "target_notification_alarm_.*\.json" } | Select-Object -Last 1)
$postTriggerSiblingAlarm = if ($postTriggerSiblingAlarmFile) { Get-Content $postTriggerSiblingAlarmFile.Trim() | ConvertFrom-Json } else { $null }

$siblingIntactPostDispatch = ($postTriggerSiblingAlarm.target_notification_alarm_matched -eq $true)
Write-Host "Sibling Alarm (#$SecondaryId) Intact in AlarmManager Post-Dispatch: $siblingIntactPostDispatch" -ForegroundColor $(if ($siblingIntactPostDispatch) { "Green" } else { "Red" })

# -------------------------------------------------------------
# STEP 9: Teardown & Final Device Cleanliness
# -------------------------------------------------------------
Write-Host "`n[STEP 9] Executing Complete Clean Teardown (Clearing Target Notification & Sibling Alarm)..." -ForegroundColor Yellow
$cleanJob = Start-Job -ScriptBlock {
    param($dev, $workDir, $tId, $sId)
    Set-Location $workDir
    flutter run -t integration_test/phase_2d_2_cleanup_app.dart -d $dev --no-pub `
        --dart-define=TARGET_ID=$tId `
        --dart-define=SECONDARY_ID=$sId `
        --dart-define=CLEAN_SECONDARY=true
} -ArgumentList $DeviceId, $projectRoot, $TargetId, $SecondaryId

$cleanTimeout = (Get-Date).AddSeconds(90)
$cleanDone = $false
while ((Get-Date) -lt $cleanTimeout -and -not $cleanDone) {
    Start-Sleep -Seconds 2
    $cleanOutput = Receive-Job -Job $cleanJob -Keep
    $cleanLine = $cleanOutput | Where-Object { $_ -match "\[PHASE_2D_NOTIF_CLEANUP_COMPLETED\]" }
    if (-not $cleanLine) {
        $logcatClean = adb -s $DeviceId logcat -d -v time "*:S" "flutter:I" | Select-String -Pattern "\[PHASE_2D_NOTIF_CLEANUP_COMPLETED\]" | Select-Object -Last 1
        if ($logcatClean) { $cleanLine = $logcatClean }
    }
    if ($cleanLine) {
        $cleanDone = $true
        Write-Host "Surgical cleanup harness confirmed teardown completion." -ForegroundColor Green
        break
    }
}
Stop-Job -Job $cleanJob -ErrorAction SilentlyContinue
Remove-Job -Job $cleanJob -ErrorAction SilentlyContinue

# Verify 0 lingering notifications and 0 lingering alarms
$postTeardownNotifs = adb -s $DeviceId shell "dumpsys notification --noredact | grep -i '$PackageName'"
$hasLingeringNotifs = ($postTeardownNotifs | Select-String -Pattern "NotificationRecord").Count -gt 0

$postTeardownAlarms = adb -s $DeviceId shell "dumpsys alarm | grep -E 'PendingIntent.*$PackageName'"
$hasLingeringAlarms = ($postTeardownAlarms | Where-Object { $_.Trim() -ne "" }).Count -gt 0

Write-Host "Post-Teardown Notifications Clean: $(-not $hasLingeringNotifs)" -ForegroundColor $(if (-not $hasLingeringNotifs) { "Green" } else { "Red" })
Write-Host "Post-Teardown Alarms Clean:        $(-not $hasLingeringAlarms)" -ForegroundColor $(if (-not $hasLingeringAlarms) { "Green" } else { "Red" })

# -------------------------------------------------------------
# STEP 10: Master Evidence Compilation
# -------------------------------------------------------------
$masterVerdict = if ($targetPersistenceProven -and $notifEvidence.tri_state_delivery.is_posted_in_os -and $siblingIntactPostDispatch) { "SCENARIO_2D_2_3_PASS" } else { "SCENARIO_2D_2_3_FAIL" }

$masterEvidence = [ordered]@{
    scenario_id = "2D.2.3.ProcessDeathDelivery"
    device_id = $DeviceId
    package_name = $PackageName
    target_id = $TargetId
    sibling_id = $SecondaryId
    scheduled_epoch_ms = $scheduledEpochMs
    sibling_epoch_ms = $secondaryEpochMs
    process_state_transitions = [ordered]@{
        pid_pre_kill = $pidPreKill
        is_dead_after_kill = $isDead
        pid_after_kill = $pidAfterKill
        pid_after_trigger = $pidAfterTrigger
        process_recreation_detected = $processRecreationDetected
        process_death_delivery_classification = if ($processRecreationDetected) { "PROCESS_DEATH_DELIVERY_WITH_BROADCAST_PROCESS_START" } else { "PROCESS_DEATH_DELIVERY_OS_SYSTEM_ONLY" }
    }
    composite_identity = [ordered]@{
        package = $PackageName
        target_id = $TargetId
        channel_id = $ChannelId
        run_marker = $runMarker
        title_marker = $titleMarker
    }
    alarm_persistence_under_process_death = [ordered]@{
        target_alarm_matched = $postKillTargetAlarm.target_notification_alarm_matched
        classification = $postKillTargetAlarm.state_classification
        receiver_component = $postKillTargetAlarm.target_identity_attributes.receiver_component
        pending_intent = $postKillTargetAlarm.target_identity_attributes.pending_intent_identity
        orig_when_epoch_ms = $postKillTargetAlarm.target_identity_attributes.orig_when_epoch_ms
        process_state = $postKillTargetAlarm.process_state
        persistence_proven = $targetPersistenceProven
    }
    notification_delivery_verification = [ordered]@{
        is_posted_in_os = $notifEvidence.tri_state_delivery.is_posted_in_os
        is_alerting_importance = $notifEvidence.tri_state_delivery.is_alerting_importance
        is_visible_in_shade = $notifEvidence.tri_state_delivery.is_visible_in_shade
        shade_verification_detail = $notifEvidence.tri_state_delivery.shade_verification_detail
        importance = $notifEvidence.tri_state_delivery.importance
        overall_classification = $notifEvidence.tri_state_delivery.overall_classification
        matched_key = $notifEvidence.composite_identity.matched_key
        matched_title = $notifEvidence.composite_identity.matched_title
        matched_text = $notifEvidence.composite_identity.matched_text
    }
    shade_ui_evidence = $notifEvidence.shade_ui_evidence
    sibling_non_interference_post_dispatch = [ordered]@{
        sibling_id = $SecondaryId
        sibling_epoch_ms = $secondaryEpochMs
        sibling_intact_in_alarm_manager = $siblingIntactPostDispatch
        verdict = if ($siblingIntactPostDispatch) { "DISPATCH_NON_INTERFERENCE_PASS" } else { "DISPATCH_NON_INTERFERENCE_FAIL" }
    }
    teardown_cleanliness = [ordered]@{
        lingering_notifications_absent = (-not $hasLingeringNotifs)
        lingering_alarms_absent = (-not $hasLingeringAlarms)
        teardown_verdict = if (-not $hasLingeringNotifs -and -not $hasLingeringAlarms) { "TEARDOWN_CLEANLINESS_PASS" } else { "TEARDOWN_CLEANLINESS_FAIL" }
    }
    evidence_files = [ordered]@{
        channel_profile_json = $profileEvidenceFile
        pre_kill_target_alarm_json = $preKillTargetAlarmFile
        pre_kill_sibling_alarm_json = $preKillSiblingAlarmFile
        post_kill_target_alarm_json = $postKillTargetAlarmFile
        post_kill_sibling_alarm_json = $postKillSiblingAlarmFile
        notification_record_json = $notifEvidenceFile
        post_trigger_sibling_alarm_json = $postTriggerSiblingAlarmFile
        shade_ui_xml = $notifEvidence.shade_ui_evidence.ui_hierarchy_file
        shade_screenshot_png = $notifEvidence.shade_ui_evidence.screenshot_file
    }
    verdict = $masterVerdict
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
}

$masterFile = Join-Path $EvidenceDir "scenario_2d_2_3_master_evidence_${safeDeviceId}_${timestamp}.json"
$masterEvidence | ConvertTo-Json -Depth 5 | Out-File -FilePath $masterFile -Encoding utf8

Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host " Scenario 2D.2.3 Process-Death Delivery Verdict: $masterVerdict" -ForegroundColor $(if ($masterVerdict -match "PASS") { "Green" } else { "Red" })
Write-Host " Master Evidence JSON written to: $masterFile" -ForegroundColor Cyan
Write-Host "=================================================================`n" -ForegroundColor Cyan
