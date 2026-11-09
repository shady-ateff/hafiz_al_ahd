<#
.SYNOPSIS
  Phase 2D.1 Scenario 2D.1.3 End-to-End Orchestrator:
  Target Alarm Identity Persistence & Process-Death Delivery Verification.
  Coordinates with scripts/device_observer.ps1 to implement B1-B5 strict evidence contracts.
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$DeviceId = "dfa9f629",

    [Parameter(Mandatory=$false)]
    [string]$PackageName = "com.shadyatef.hafiz_alahd",

    [Parameter(Mandatory=$false)]
    [int]$LeadSeconds = 45,

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
Write-Host "  SCENARIO 2D.1.3: TARGET IDENTITY & PROCESS-DEATH DELIVERY" -ForegroundColor Cyan
Write-Host "  Device: [$DeviceId] | Package: [$PackageName]" -ForegroundColor Cyan
Write-Host "  Observer Script: $observerScript" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Step 0: Preflight Check — Target ID 999901 must not be scheduled
Write-Host "`n[Step 0] Preflight Check: Target Alarm ID 999901 state in AlarmManager..." -ForegroundColor Yellow
$preflightDump = adb -s $DeviceId shell dumpsys alarm
$preflightHasTag = ($preflightDump | Select-String -Pattern "AlarmReceiver").Count
Write-Host "Active AlarmReceiver records currently in AlarmManager: $preflightHasTag"

# Step 1: Preflight Process State
Write-Host "`n[Step 1] Initial Process State on device [$DeviceId]..."
$initialPid = adb -s $DeviceId shell "pidof $PackageName"
$initialPid = ($initialPid -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
Write-Host "Initial App Process State: $(if ($initialPid) { "RUNNING (PID: $initialPid)" } else { "NOT RUNNING" })"

# Step 2: Trigger Target Alarm Scheduling via Harness (Lead horizon: +45s)
Write-Host "`n[Step 2] Launching harness to schedule target alarm (Lead horizon: +$LeadSeconds s)..." -ForegroundColor Yellow
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
    Write-Error "CRITICAL: Could not capture target schedule event from harness. Aborting Scenario 2D.1.3."
    Stop-Job -Job $testJob -ErrorAction SilentlyContinue
    Remove-Job -Job $testJob -ErrorAction SilentlyContinue
    return
}

# Step 3: Run verify-target-alarm (Pre-Kill Identity Verification)
Write-Host "`n[Step 3] Running Host Observer verify-target-alarm (Pre-Kill State)..." -ForegroundColor Yellow
$preKillRaw = & $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action "verify-target-alarm" -ScheduledEpochMs $actualTargetEpoch -ExpectedId 999901 -EvidenceDir $EvidenceDir
$preKillEvidenceFile = ($preKillRaw | Where-Object { Test-Path $_ } | Select-Object -Last 1)
$preKillEvidence = Get-Content $preKillEvidenceFile -Raw | ConvertFrom-Json
Write-Host "Pre-Kill Target Matched: $($preKillEvidence.target_alarm_matched) | Classification: $($preKillEvidence.state_classification)" -ForegroundColor Green

if (-not $preKillEvidence.target_alarm_matched) {
    Write-Error "CRITICAL: Target Alarm not matched in AlarmManager pre-kill. Aborting."
    return
}

# Step 4: Remaining Time Guard Check (> 12,000 ms required)
Write-Host "`n[Step 4] Checking Remaining Time Guard before process termination..." -ForegroundColor Yellow
$nowEpoch = [long]([DateTimeOffset]::UtcNow).ToUnixTimeMilliseconds()
$remainingMs = $actualTargetEpoch - $nowEpoch
Write-Host "Target Epoch: $actualTargetEpoch | Current Epoch: $nowEpoch | Remaining: $remainingMs ms"

if ($remainingMs -lt 12000) {
    $abortRecord = [ordered]@{
        failure_classification = "INVALID_TEST_TIMING"
        reason = "Remaining time before alarm trigger ($remainingMs ms) is less than strict 12000ms threshold."
        target_epoch = $actualTargetEpoch
        current_epoch = $nowEpoch
        remaining_ms = $remainingMs
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
    }
    $abortFile = Join-Path $EvidenceDir "scenario_2d_1_3_aborted_${safeDeviceId}_${timestamp}.json"
    $abortRecord | ConvertTo-Json -Depth 3 | Out-File -FilePath $abortFile -Encoding utf8
    Write-Error "ABORTED: Remaining time $remainingMs ms < 12000 ms threshold. Abort evidence recorded to $abortFile."
    return
}
Write-Host "Remaining Time Guard PASSED ($remainingMs ms >= 12000 ms)." -ForegroundColor Green

# Step 5: Background App via KEYCODE_HOME
Write-Host "`n[Step 5] Moving application to background via KEYCODE_HOME..." -ForegroundColor Yellow
& $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action "background-app"
Start-Sleep -Milliseconds 500

# Step 6: Execute SIGKILL_PROCESS_TERMINATION
Write-Host "`n[Step 6] Executing SIGKILL_PROCESS_TERMINATION via run-as..." -ForegroundColor Yellow
& $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action "kill-process" -EvidenceDir $EvidenceDir
Start-Sleep -Milliseconds 500

# Verify process is dead
$pidAfterKill = adb -s $DeviceId shell "pidof $PackageName"
$pidAfterKill = ($pidAfterKill -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
$isDead = [string]::IsNullOrEmpty($pidAfterKill)
Write-Host "Verification of process death: $(if ($isDead) { "CONFIRMED DEAD (PID is empty)" } else { "ALIVE (PID: $pidAfterKill)" })" -ForegroundColor $(if ($isDead) { "Green" } else { "Red" })

if (-not $isDead) {
    Write-Error "CRITICAL: Process failed to terminate. Aborting."
    return
}

# Step 7: PROVE TARGET ALARM PERSISTENCE IN ALARMMANAGER (DURING PROCESS DEATH)
Write-Host "`n[Step 7] CRITICAL TEST: Verifying Target Alarm Persistence in AlarmManager while Process is DEAD..." -ForegroundColor Yellow
$postKillRaw = & $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action "verify-target-alarm" -ScheduledEpochMs $actualTargetEpoch -ExpectedId 999901 -EvidenceDir $EvidenceDir
$postKillEvidenceFile = ($postKillRaw | Where-Object { Test-Path $_ } | Select-Object -Last 1)
$postKillEvidence = Get-Content $postKillEvidenceFile -Raw | ConvertFrom-Json

Write-Host "Post-Kill Target Matched: $($postKillEvidence.target_alarm_matched)" -ForegroundColor Green
Write-Host "Post-Kill State Classification: $($postKillEvidence.state_classification)" -ForegroundColor Green
Write-Host "Process State: $($postKillEvidence.process_state)" -ForegroundColor Green

$persistenceProven = ($postKillEvidence.target_alarm_matched -and $postKillEvidence.state_classification -eq "TARGET_ALARM_PERSISTENCE_PROVEN")
Write-Host "`n>>> TARGET ALARM PERSISTENCE PROVEN: $persistenceProven <<<" -ForegroundColor $(if ($persistenceProven) { "Green" } else { "Red" })

# Step 8: Monitor Alarm Lifecycle Across Scheduled Delivery Time
$nowEpoch = [long]([DateTimeOffset]::UtcNow).ToUnixTimeMilliseconds()
$remainingToTrigger = [Math]::Max(5, [int](($actualTargetEpoch - $nowEpoch) / 1000) + 10)
Write-Host "`n[Step 8] Monitoring Alarm Lifecycle across trigger window for $remainingToTrigger seconds..." -ForegroundColor Yellow
$lifecycleRaw = & $observerScript -DeviceId $DeviceId -PackageName $PackageName -Action "monitor-alarm-lifecycle" -ScheduledEpochMs $actualTargetEpoch -ExpectedId 999901 -DurationSeconds $remainingToTrigger -EvidenceDir $EvidenceDir
$lifecycleEvidenceFile = ($lifecycleRaw | Where-Object { Test-Path $_ } | Select-Object -Last 1)
$lifecycleEvidence = Get-Content $lifecycleEvidenceFile -Raw | ConvertFrom-Json

# Step 9: Surgical Cleanup via Harness
Write-Host "`n[Step 9] Executing Surgical Cleanup of Target Alarm 999901..." -ForegroundColor Yellow
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

# Step 10: Compile Final Master Evidence Bundle
$masterEvidence = [ordered]@{
    scenario_id = "2D.1.3.TargetIdentityPersistenceAndProcessDeathDelivery"
    device_id = $DeviceId
    package_name = $PackageName
    target_alarm_id = 999901
    scheduled_epoch_ms = $actualTargetEpoch
    target_identity_attributes = $preKillEvidence.target_identity_attributes
    timing_guard = [ordered]@{
        remaining_ms_at_kill = $remainingMs
        guard_passed = ($remainingMs -ge 12000)
    }
    process_termination = [ordered]@{
        pid_before_kill = $preKillEvidence.pid
        pid_after_kill = $postKillEvidence.pid
        process_confirmed_dead = $isDead
        termination_mechanism = "run-as /system/bin/kill"
    }
    alarm_persistence = [ordered]@{
        pre_kill_matched = $preKillEvidence.target_alarm_matched
        post_kill_matched = $postKillEvidence.target_alarm_matched
        post_kill_classification = $postKillEvidence.state_classification
        persistence_proven = $persistenceProven
    }
    lifecycle_delivery = [ordered]@{
        receiver_onreceive_executed = $lifecycleEvidence.receiver_onreceive_executed
        service_started = $lifecycleEvidence.service_started
        native_audio_playback_requested = $lifecycleEvidence.native_audio_playback_requested
        hardware_audio_confirmed = $false # Deferred to Phase 2D.3
        pid_after_delivery = $lifecycleEvidence.current_pid
        recreated_process = ($null -ne $lifecycleEvidence.current_pid -and $lifecycleEvidence.current_pid -ne $preKillEvidence.pid)
        classification = $lifecycleEvidence.lifecycle_classification
    }
    surgical_cleanup = [ordered]@{
        target_absent_post_cleanup = $cleanupSuccess
        remaining_sibling_alarms = $cleanupEvidence.total_package_alarms_in_alarmmanager
    }
    evidence_files = [ordered]@{
        pre_kill_json = $preKillEvidenceFile
        post_kill_json = $postKillEvidenceFile
        lifecycle_json = $lifecycleEvidenceFile
        cleanup_json = $cleanupEvidenceFile
    }
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
}

$masterEvidenceFile = Join-Path $EvidenceDir "scenario_2d_1_3_master_evidence_${safeDeviceId}_${timestamp}.json"
$masterEvidence | ConvertTo-Json -Depth 6 | Out-File -FilePath $masterEvidenceFile -Encoding utf8

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  SCENARIO 2D.1.3 RUN COMPLETE" -ForegroundColor Green
Write-Host "  Persistence Proven:           $persistenceProven" -ForegroundColor $(if ($persistenceProven) { "Green" } else { "Red" })
Write-Host "  Receiver onReceive Executed:  $($lifecycleEvidence.receiver_onreceive_executed)" -ForegroundColor $(if ($lifecycleEvidence.receiver_onreceive_executed) { "Green" } else { "Yellow" })
Write-Host "  Native Service Started:       $($lifecycleEvidence.service_started)" -ForegroundColor $(if ($lifecycleEvidence.service_started) { "Green" } else { "Yellow" })
Write-Host "  Audio Playback Requested:     $($lifecycleEvidence.native_audio_playback_requested)" -ForegroundColor $(if ($lifecycleEvidence.native_audio_playback_requested) { "Green" } else { "Yellow" })
Write-Host "  Hardware Audio Confirmed:     FALSE (Tier 4 Deferred to 2D.3)" -ForegroundColor DarkGray
Write-Host "  Surgical Cleanup Verified:    $cleanupSuccess" -ForegroundColor Green
Write-Host "  Master Evidence JSON:         $masterEvidenceFile" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green

# Clean up test background job
Stop-Job -Job $testJob -ErrorAction SilentlyContinue
Remove-Job -Job $testJob -ErrorAction SilentlyContinue
