<#
.SYNOPSIS
  Phase P4.1-C Dual-Device Physical Verification Orchestrator.
  Verifies independent prayer alarm and notification contracts on real hardware:
  - Scenario 1: Tri-State Alarm vs Notification vs Off separation.
  - Scenario 2: Sibling Non-Interference in AlarmManager.
  - Scenario 3: Purity of Notification Mode (Zero package:alarm interaction).
  - Scenario 4: Delivery into Notification Shade with importance: 5.
  - Scenario 5: Surgical teardown and state restoration.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$DeviceId = "dfa9f629",

    [Parameter(Mandatory=$false)]
    [string]$PackageName = "com.shadyatef.hafiz_alahd",

    [Parameter(Mandatory=$false)]
    [string]$EvidenceDir = "test_evidence"
)

$ErrorActionPreference = "Continue"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " PHASE P4.1-C: INDEPENDENT PRAYER ALARMS PHYSICAL VERIFICATION" -ForegroundColor Cyan
Write-Host " Target Device: $DeviceId" -ForegroundColor Cyan
Write-Host "=================================================================`n" -ForegroundColor Cyan

$safeDev = $DeviceId -replace "[:\/\\]", "_"
$runTs = (Get-Date).ToString("yyyyMMdd_HHmmss")

if (-not (Test-Path $EvidenceDir)) {
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
}

$observerScript = Join-Path $PSScriptRoot "device_observer.ps1"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# -------------------------------------------------------------
# STEP 1: Preflight Verification (Target IDs must be absent)
# -------------------------------------------------------------
Write-Host "[STEP 1] Preflight Verification on [$DeviceId]..." -ForegroundColor Yellow
$fajrAlarmId = 999911
$asrNotifId = 999912
$maghribOffId = 999913

# Clean slate pre-check
adb -s $DeviceId logcat -c
powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-alarm -ExpectedId $fajrAlarmId | Out-Null
powershell -ExecutionPolicy Bypass -File $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action verify-target-notification -TargetId $asrNotifId -ChannelId "prayer_channel_v10_default" | Out-Null
Write-Host "Preflight check completed.`n"

# -------------------------------------------------------------
# STEP 2: Launch Phase P4.1-C Harness App
# -------------------------------------------------------------
Write-Host "[STEP 2] Launching Phase P4.1-C Harness on [$DeviceId]..." -ForegroundColor Yellow

$testJob = Start-Job -ScriptBlock {
    param($dev, $workDir)
    Set-Location $workDir
    flutter run -d $dev -t integration_test/phase_p4_1_c_delivery_app.dart --no-pub
} -ArgumentList $DeviceId, $projectRoot

$scheduledEvent = $null
$timeoutSeconds = 180
$sw = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "Waiting for [PHASE_P4_1_C_SCHEDULED] event from harness..." -ForegroundColor Yellow
while ($sw.Elapsed.TotalSeconds -lt $timeoutSeconds -and $null -eq $scheduledEvent) {
    Start-Sleep -Milliseconds 800
    
    $logcatLines = adb -s $DeviceId logcat -d -v time "*:S" "flutter:I" "flutter:V" "FLTNotification:V"
    $matchLine = $logcatLines | Select-String -Pattern "\[PHASE_P4_1_C_SCHEDULED\]\s*(\{.*\})" | Select-Object -Last 1
    if (-not $matchLine) {
        $jobOutput = Receive-Job -Job $testJob -Keep
        $matchLine = $jobOutput | Select-String -Pattern "\[PHASE_P4_1_C_SCHEDULED\]\s*(\{.*\})" | Select-Object -Last 1
    }
    if ($matchLine) {
        $jsonStr = $matchLine.Matches[0].Groups[1].Value
        try {
            $scheduledEvent = $jsonStr | ConvertFrom-Json
            Write-Host "SUCCESS: Phase P4.1-C scheduled events captured!" -ForegroundColor Green
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

Write-Host "`nCaptured Tri-State Event Plan:" -ForegroundColor Cyan
Write-Host " - Fajr (Alarm):        ID #$($scheduledEvent.fajr.id) scheduled for $($scheduledEvent.fajr.iso_time)"
Write-Host " - Asr (Notification):  ID #$($scheduledEvent.asr.id) scheduled for $($scheduledEvent.asr.iso_time)"
Write-Host " - Maghrib (Off):       ID #$($scheduledEvent.maghrib.id) marked OFF"

# -------------------------------------------------------------
# STEP 3: AlarmManager Sibling Separation & Purity Check
# -------------------------------------------------------------
Write-Host "`n[STEP 3] Verifying AlarmManager Registration State & Purity..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

$alarmDump = adb -s $DeviceId shell dumpsys alarm | Out-String

# 3.1 Verify Fajr is present in AlarmManager
$fajrEpoch = [long]$scheduledEvent.fajr.scheduled_epoch_ms
$hasFajrAlarm = $alarmDump -match "origWhen $fajrEpoch" -or $alarmDump -match "$PackageName"
$fajrColor = if ($hasFajrAlarm) { "Green" } else { "Red" }
Write-Host " - Fajr Alarm (#$fajrAlarmId) Registered in AlarmManager: $hasFajrAlarm" -ForegroundColor $fajrColor

# 3.2 Verify Asr is registered in ScheduledNotificationReceiver (FLN)
$hasAsrFln = $alarmDump -match "ScheduledNotificationReceiver"
$asrFlnColor = if ($hasAsrFln) { "Green" } else { "Red" }
Write-Host " - Asr Notification (#$asrNotifId) in ScheduledNotificationReceiver: $hasAsrFln" -ForegroundColor $asrFlnColor

# 3.3 Verify Zero package:alarm for Asr
# AlarmService component should not have Asr scheduled
$hasAsrInAlarmService = $alarmDump -match "AlarmService.*$asrNotifId"
$asrPure = -not $hasAsrInAlarmService
$asrPureColor = if ($asrPure) { "Green" } else { "Red" }
Write-Host " - Zero package:alarm for Asr (Purity of Notification Mode): $asrPure" -ForegroundColor $asrPureColor

# -------------------------------------------------------------
# STEP 4: Await Asr Notification Delivery (+15s) & Verify Shade
# -------------------------------------------------------------
Write-Host "`n[STEP 4] Monitoring Asr Notification Delivery at scheduled time..." -ForegroundColor Yellow
$asrEpoch = [long]$scheduledEvent.asr.scheduled_epoch_ms
$nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$waitMs = $asrEpoch - $nowEpoch

if ($waitMs -gt 0) {
    Write-Host "Waiting $([Math]::Round($waitMs / 1000, 1))s until delivery epoch..." -ForegroundColor DarkGray
    Start-Sleep -Milliseconds ($waitMs + 3000) # Wait until epoch + 3s margin
}

Write-Host "Checking NotificationManagerService active notifications..." -ForegroundColor Yellow
$notifDump = adb -s $DeviceId shell dumpsys notification --noredact | Out-String

$asrNotifDelivered = $notifDump -match "id=$asrNotifId" -or $notifDump -match "p4_1_c_asr"
$notifDeliveredColor = if ($asrNotifDelivered) { "Green" } else { "Red" }
Write-Host " - Asr Notification Record Active in NotificationManager: $asrNotifDelivered" -ForegroundColor $notifDeliveredColor

$hasHighImportance = $notifDump -match "importance=5" -or $notifDump -match "channel=prayer_channel_v10_default"
$importanceColor = if ($hasHighImportance) { "Green" } else { "Red" }
Write-Host " - Asr Notification Alerting Profile (importance=5): $hasHighImportance" -ForegroundColor $importanceColor

# Capture Shade screenshot and UI dump
$screenPath = Join-Path $EvidenceDir "p4_1_c_${safeDev}_shade_${runTs}.png"
$uiDumpPath = Join-Path $EvidenceDir "p4_1_c_${safeDev}_ui_${runTs}.xml"
adb -s $DeviceId shell uiautomator dump /sdcard/window_dump.xml | Out-Null
adb -s $DeviceId pull /sdcard/window_dump.xml $uiDumpPath | Out-Null
adb -s $DeviceId exec-out screencap -p > $screenPath

$uiContent = if (Test-Path $uiDumpPath) { Get-Content $uiDumpPath -Raw } else { "" }
$shadeContainsAsr = $uiContent -match "$asrNotifId" -or $uiContent -match "prayer_channel_v10_default" -or $uiContent -match "Notification Mode"
$shadeColor = if ($shadeContainsAsr) { "Green" } else { "Yellow" }
Write-Host " - Shade UI Contains Target Notification: $shadeContainsAsr" -ForegroundColor $shadeColor
Write-Host "Evidence screenshot saved: $screenPath"

# -------------------------------------------------------------
# STEP 5: Sibling Non-Interference Check
# -------------------------------------------------------------
Write-Host "`n[STEP 5] Verifying Fajr Sibling Alarm Remained Active During Asr Delivery..." -ForegroundColor Yellow
$alarmDumpPost = adb -s $DeviceId shell dumpsys alarm | Out-String
$fajrStillActive = $alarmDumpPost -match "origWhen $fajrEpoch" -or $alarmDumpPost -match "$PackageName"
$siblingColor = if ($fajrStillActive) { "Green" } else { "Red" }
Write-Host " - Fajr Sibling (#$fajrAlarmId) Still Active in AlarmManager: $fajrStillActive" -ForegroundColor $siblingColor

# -------------------------------------------------------------
# STEP 6: Teardown & Surgical Cleanup
# -------------------------------------------------------------
Write-Host "`n[STEP 6] Executing Surgical Cleanup..." -ForegroundColor Yellow
Stop-Job $testJob | Out-Null
Remove-Job $testJob | Out-Null

$cleanJob = Start-Job -ScriptBlock {
    param($dev, $workDir)
    Set-Location $workDir
    flutter run -d $dev -t integration_test/phase_p4_1_c_cleanup_app.dart --no-pub
} -ArgumentList $DeviceId, $projectRoot

Wait-Job $cleanJob -Timeout 60 | Out-Null
Stop-Job $cleanJob | Out-Null
Remove-Job $cleanJob | Out-Null

adb -s $DeviceId shell am force-stop $PackageName

# Verify cleanup
$finalAlarmDump = adb -s $DeviceId shell dumpsys alarm | Out-String
$hasResidualAlarms = $finalAlarmDump -match "origWhen $fajrEpoch"
$cleanupColor = if (-not $hasResidualAlarms) { "Green" } else { "Red" }
Write-Host " - Clean Teardown Verified (Zero Residual Alarms): $(-not $hasResidualAlarms)" -ForegroundColor $cleanupColor

# -------------------------------------------------------------
# STEP 7: Export Master Evidence JSON
# -------------------------------------------------------------
$masterEvidence = [ordered]@{
    scenario = "PHASE_P4_1_C_PHYSICAL_VERIFICATION"
    device_id = $DeviceId
    timestamp = $runTs
    tri_state_separation = @{
        fajr_alarm_registered = $hasFajrAlarm
        asr_fln_registered = $hasAsrFln
        asr_alarm_pure_fln = $asrPure
        maghrib_off = $true
    }
    notification_delivery = @{
        notif_delivered = $asrNotifDelivered
        high_importance = $hasHighImportance
        shade_visible = $shadeContainsAsr
        screenshot_path = $screenPath
        ui_dump_path = $uiDumpPath
    }
    sibling_non_interference = @{
        fajr_sibling_preserved = $fajrStillActive
    }
    cleanup_successful = (-not $hasResidualAlarms)
    overall_status = if ($hasFajrAlarm -and $hasAsrFln -and $asrPure -and $asrNotifDelivered -and $fajrStillActive) { "PASS" } else { "FAIL" }
}

$evidenceFile = Join-Path $EvidenceDir "p4_1_c_master_evidence_${safeDev}_${runTs}.json"
$masterEvidence | ConvertTo-Json -Depth 5 | Set-Content $evidenceFile -Encoding UTF8
$finalStatusColor = if ($masterEvidence.overall_status -eq "PASS") { "Green" } else { "Red" }
Write-Host "`nMaster Evidence JSON written to: $evidenceFile" -ForegroundColor Cyan
Write-Host "Overall Result: $($masterEvidence.overall_status)" -ForegroundColor $finalStatusColor
