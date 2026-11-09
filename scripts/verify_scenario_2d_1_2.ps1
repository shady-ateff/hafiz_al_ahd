<#
.SYNOPSIS
  Phase 2D.1 Scenario 2D.1.2 End-to-End Orchestrator:
  Background Prayer Alarm Delivery & Audio/Notification Verification.
  Coordinates with scripts/device_observer.ps1 to implement strict evidence contracts.
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$DeviceId = "dfa9f629",

    [Parameter(Mandatory=$false)]
    [string]$PackageName = "com.shadyatef.hafiz_alahd",

    [Parameter(Mandatory=$false)]
    [string]$EvidenceDir = "test_evidence"
)

$safeDeviceId = $DeviceId -replace "[:\/\\]", "_"
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
if (-not (Test-Path $EvidenceDir)) {
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
}

$observerScript = Join-Path $PSScriptRoot "device_observer.ps1"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  SCENARIO 2D.1.2: BACKGROUND DELIVERY VERIFICATION" -ForegroundColor Cyan
Write-Host "  Device: [$DeviceId] | Package: [$PackageName]" -ForegroundColor Cyan
Write-Host "  Observer Script: $observerScript" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Step 0: Preflight Check
Write-Host "`n[Step 0] Preflight Check: Target Alarm ID 999901 state in AlarmManager..." -ForegroundColor Yellow
$preflightDump = adb -s $DeviceId shell dumpsys alarm
$preflightHasTag = ($preflightDump | Select-String -Pattern "AlarmReceiver").Count
Write-Host "Active AlarmReceiver records currently in AlarmManager: $preflightHasTag"

# Step 1: Preflight Process State
Write-Host "`n[Step 1] Initial Process State on device [$DeviceId]..."
$initialPid = adb -s $DeviceId shell "pidof $PackageName"
$initialPid = ($initialPid -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
Write-Host "Initial App Process State: $(if ($initialPid) { "RUNNING (PID: $initialPid)" } else { "NOT RUNNING" })"

# Step 2: Trigger Target Alarm Scheduling via Harness
Write-Host "`n[Step 2] Launching harness to schedule target alarm (Lead horizon: ~45s)..." -ForegroundColor Yellow
adb -s $DeviceId logcat -c

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$testJob = Start-Job -ScriptBlock {
    param($dev, $workDir)
    Set-Location $workDir
    flutter run -t integration_test/phase_2d_1_delivery_app.dart -d $dev --no-pub
} -ArgumentList $DeviceId, $projectRoot

Write-Host "Waiting for in-app schedule dispatch event [PHASE_2D_TARGET_SCHEDULED]..."
$timeout = (Get-Date).AddSeconds(120)
$scheduledFound = $false
$actualTargetEpoch = 0

while ((Get-Date) -lt $timeout -and -not $scheduledFound) {
    Start-Sleep -Milliseconds 1500
    $jobOutput = Receive-Job -Job $testJob -Keep
    $schedLine = $jobOutput | Where-Object { $_ -match "\[PHASE_2D_TARGET_SCHEDULED\]" }
    if (-not $schedLine) {
        $logcatMatch = adb -s $DeviceId logcat -d | Select-String "\[PHASE_2D_TARGET_SCHEDULED\]"
        if ($logcatMatch) {
            $schedLine = $logcatMatch.Line
        }
    }
    if ($schedLine) {
        $jsonPart = ($schedLine | Select-Object -First 1) -replace ".*\[PHASE_2D_TARGET_SCHEDULED\]\s*", ""
        try {
            $parsed = $jsonPart | ConvertFrom-Json
            $actualTargetEpoch = [long]$parsed.scheduled_epoch_ms
            $scheduledFound = $true
            Write-Host "Captured target schedule event from app: Epoch=$actualTargetEpoch" -ForegroundColor Green
        } catch {}
    }
}

if (-not $scheduledFound -or $actualTargetEpoch -le 0) {
    Write-Error "CRITICAL: Could not capture target schedule event from harness. Aborting Scenario 2D.1.2."
    Stop-Job -Job $testJob -ErrorAction SilentlyContinue
    Remove-Job -Job $testJob -ErrorAction SilentlyContinue
    return
}

# Step 3: Move application to background via KEYCODE_HOME
Write-Host "`n[Step 3] Moving application to background via KEYCODE_HOME..." -ForegroundColor Yellow
& $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action "background-app"
Start-Sleep -Milliseconds 500

# Verify process is still alive and in background
$pidBackground = adb -s $DeviceId shell "pidof $PackageName"
$pidBackground = ($pidBackground -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
$isAlive = -not [string]::IsNullOrEmpty($pidBackground)
Write-Host "Process state in background: $(if ($isAlive) { "ALIVE (PID: $pidBackground)" } else { "NOT RUNNING" })" -ForegroundColor $(if ($isAlive) { "Green" } else { "Red" })

if (-not $isAlive) {
    Write-Error "CRITICAL: Process died prematurely upon backgrounding. Aborting."
    return
}

# Step 4: Verify Target Alarm in AlarmManager while app is in background
Write-Host "`n[Step 4] Running Host Observer verify-target-alarm (Background State)..." -ForegroundColor Yellow
$bgRaw = & $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action "verify-target-alarm" -ScheduledEpochMs $actualTargetEpoch -ExpectedId 999901 -EvidenceDir $EvidenceDir
$bgEvidenceFile = ($bgRaw | Where-Object { Test-Path $_ } | Select-Object -Last 1)
$bgEvidence = Get-Content $bgEvidenceFile -Raw | ConvertFrom-Json
Write-Host "Background Target Matched: $($bgEvidence.target_alarm_matched) | Classification: $($bgEvidence.state_classification)" -ForegroundColor Green

if (-not $bgEvidence.target_alarm_matched) {
    Write-Error "CRITICAL: Target Alarm not matched in AlarmManager in background. Aborting."
    return
}

# Step 5: Monitor Alarm Lifecycle Across Scheduled Delivery Time
$nowEpoch = [long]([DateTimeOffset]::UtcNow).ToUnixTimeMilliseconds()
$remainingToTrigger = [Math]::Max(5, [int](($actualTargetEpoch - $nowEpoch) / 1000) + 10)
Write-Host "`n[Step 5] Monitoring Alarm Lifecycle across trigger window for $remainingToTrigger seconds (App in Background)..." -ForegroundColor Yellow
$lifecycleRaw = & $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action "monitor-alarm-lifecycle" -ScheduledEpochMs $actualTargetEpoch -ExpectedId 999901 -DurationSeconds $remainingToTrigger -EvidenceDir $EvidenceDir
$lifecycleEvidenceFile = ($lifecycleRaw | Where-Object { Test-Path $_ } | Select-Object -Last 1)
$lifecycleEvidence = Get-Content $lifecycleEvidenceFile -Raw | ConvertFrom-Json

# Step 6: Verify Notification State
Write-Host "`n[Step 6] Inspecting NotificationManager state on device [$DeviceId]..." -ForegroundColor Yellow
$notifDump = adb -s $DeviceId shell dumpsys notification
$notifMatch = ($notifDump | Select-String -Pattern "NotificationRecord\{" -Context 0, 4 | Where-Object { $_.Context.PostContext -match $PackageName -or $_.Line -match $PackageName })
$notificationVisible = ($notifMatch.Count -gt 0)
Write-Host "Notification Visible in System: $notificationVisible" -ForegroundColor $(if ($notificationVisible) { "Green" } else { "Yellow" })

# Step 7: Surgical Cleanup via Harness
Write-Host "`n[Step 7] Executing Surgical Cleanup of Target Alarm 999901..." -ForegroundColor Yellow
$cleanJob = Start-Job -ScriptBlock {
    param($dev, $workDir)
    Set-Location $workDir
    flutter run -t integration_test/phase_2d_1_cleanup_app.dart -d $dev --no-pub
} -ArgumentList $DeviceId, $projectRoot

$cleanTimeout = (Get-Date).AddSeconds(45)
$cleanDone = $false
while ((Get-Date) -lt $cleanTimeout -and -not $cleanDone) {
    Start-Sleep -Seconds 2
    $cleanOutput = Receive-Job -Job $cleanJob -Keep
    $cleanLine = $cleanOutput | Where-Object { $_ -match "\[PHASE_2D_CLEANUP_COMPLETED\]" }
    if (-not $cleanLine) {
        $logcatMatch = adb -s $DeviceId logcat -d | Select-String "\[PHASE_2D_CLEANUP_COMPLETED\]"
        if ($logcatMatch) {
            $cleanLine = $logcatMatch.Line
        }
    }
    if ($cleanLine) {
        $cleanDone = $true
        Write-Host "Surgical cleanup harness confirmed completion." -ForegroundColor Green
    }
}
Stop-Job -Job $cleanJob -ErrorAction SilentlyContinue
Remove-Job -Job $cleanJob -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# Post-cleanup check: Target 999901 must now be ABSENT from AlarmManager
$cleanupRaw = & $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action "verify-target-alarm" -ScheduledEpochMs $actualTargetEpoch -ExpectedId 999901 -EvidenceDir $EvidenceDir
$cleanupEvidenceFile = ($cleanupRaw | Where-Object { Test-Path $_ } | Select-Object -Last 1)
$cleanupEvidence = Get-Content $cleanupEvidenceFile -Raw | ConvertFrom-Json
$cleanupSuccess = (-not $cleanupEvidence.target_alarm_matched)
Write-Host "Surgical Cleanup Post-Check: Target Absent = $cleanupSuccess (Total Remaining Alarms: $($cleanupEvidence.total_package_alarms_in_alarmmanager))" -ForegroundColor $(if ($cleanupSuccess) { "Green" } else { "Yellow" })

# Step 8: Compile Final Master Evidence Bundle
$masterEvidence = [ordered]@{
    scenario_id = "2D.1.2.BackgroundDelivery"
    device_id = $DeviceId
    package_name = $PackageName
    target_alarm_id = 999901
    scheduled_epoch_ms = $actualTargetEpoch
    target_identity_attributes = $bgEvidence.target_identity_attributes
    process_state = [ordered]@{
        pid = $pidBackground
        background_transition_confirmed = $isAlive
    }
    alarm_persistence = [ordered]@{
        background_matched = $bgEvidence.target_alarm_matched
        background_classification = $bgEvidence.state_classification
    }
    lifecycle_delivery = [ordered]@{
        receiver_onreceive_executed = $lifecycleEvidence.receiver_onreceive_executed
        service_started = $lifecycleEvidence.service_started
        native_audio_playback_requested = $lifecycleEvidence.native_audio_playback_requested
        hardware_audio_confirmed = $false # Deferred to Phase 2D.3
        notification_visible = $notificationVisible
        classification = $lifecycleEvidence.lifecycle_classification
    }
    surgical_cleanup = [ordered]@{
        target_absent_post_cleanup = $cleanupSuccess
        remaining_sibling_alarms = $cleanupEvidence.total_package_alarms_in_alarmmanager
    }
    evidence_files = [ordered]@{
        background_json = $bgEvidenceFile
        lifecycle_json = $lifecycleEvidenceFile
        cleanup_json = $cleanupEvidenceFile
    }
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
}

$masterEvidenceFile = Join-Path $EvidenceDir "scenario_2d_1_2_master_evidence_${safeDeviceId}_${timestamp}.json"
$masterEvidence | ConvertTo-Json -Depth 6 | Out-File -FilePath $masterEvidenceFile -Encoding utf8

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  SCENARIO 2D.1.2 RUN COMPLETE" -ForegroundColor Green
Write-Host "  Background State:             $isAlive (PID: $pidBackground)" -ForegroundColor Green
Write-Host "  Receiver onReceive Executed:  $($lifecycleEvidence.receiver_onreceive_executed)" -ForegroundColor $(if ($lifecycleEvidence.receiver_onreceive_executed) { "Green" } else { "Yellow" })
Write-Host "  Native Service Started:       $($lifecycleEvidence.service_started)" -ForegroundColor $(if ($lifecycleEvidence.service_started) { "Green" } else { "Yellow" })
Write-Host "  Audio Playback Requested:     $($lifecycleEvidence.native_audio_playback_requested)" -ForegroundColor $(if ($lifecycleEvidence.native_audio_playback_requested) { "Green" } else { "Yellow" })
Write-Host "  Hardware Audio Confirmed:     FALSE (Tier 4 Deferred to 2D.3)" -ForegroundColor DarkGray
Write-Host "  Notification Visible:         $notificationVisible" -ForegroundColor $(if ($notificationVisible) { "Green" } else { "Yellow" })
Write-Host "  Surgical Cleanup Verified:    $cleanupSuccess" -ForegroundColor Green
Write-Host "  Master Evidence JSON:         $masterEvidenceFile" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green

# Clean up test background job
Stop-Job -Job $testJob -ErrorAction SilentlyContinue
Remove-Job -Job $testJob -ErrorAction SilentlyContinue

