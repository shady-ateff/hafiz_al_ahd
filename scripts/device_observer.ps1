<#
.SYNOPSIS
  Phase 2D.1 & 2D.2 External Host-Side Device Observer for Physical Android Verification.
  Runs independently of the Flutter process and Dart VM.
  Implements strict verification contracts for Alarms and Notifications:
  - C1: Tri-state Notification Delivery (Scheduled -> Posted -> Visible in Shade)
  - C2: Process-Death Delivery classification (without vs with process recreation)
  - C3: Composite Target Identity Matching (Package, ID, Channel, Marker, Epoch)
  - C4: AlarmManager identity matching & correlation
  - C5: 6-point surgical cleanup verification
  - C6: Timing & Latency evaluation (delivery correctness separate from latency degradation)
  - C7: Channel & Permissions deep profiling
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$DeviceId = "dfa9f629",

    [Parameter(Mandatory=$false)]
    [string]$PackageName = "com.shadyatef.hafiz_alahd",

    [Parameter(Mandatory=$false)]
    [ValidateSet(
        "profile",
        "dump-alarm",
        "dump-notification",
        "verify-target-alarm",
        "monitor-alarm-lifecycle",
        "verify-target-notification-alarm",
        "verify-target-notification",
        "monitor-notification-lifecycle",
        "profile-notification-channel",
        "verify-notification-cleanup",
        "background-app",
        "kill-process",
        "force-stop",
        "monitor-window"
    )]
    [string]$Action = "profile",

    [Parameter(Mandatory=$false)]
    [long]$ScheduledEpochMs = 0,

    [Parameter(Mandatory=$false)]
    [int]$ExpectedId = 999901,

    [Parameter(Mandatory=$false)]
    [int]$TargetId = 999902,

    [Parameter(Mandatory=$false)]
    [int]$SecondaryId = 999903,

    [Parameter(Mandatory=$false)]
    [long]$SecondaryEpochMs = 0,

    [Parameter(Mandatory=$false)]
    [string]$ChannelId = "prayer_channel_v10_default",

    [Parameter(Mandatory=$false)]
    [string]$RunMarker = "",

    [Parameter(Mandatory=$false)]
    [string]$Title = "",

    [Parameter(Mandatory=$false)]
    [int]$DurationSeconds = 30,

    [Parameter(Mandatory=$false)]
    [string]$EvidenceDir = "test_evidence"
)

# Ensure evidence directory exists
if (-not (Test-Path $EvidenceDir)) {
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
}

$safeDeviceId = $DeviceId -replace "[:\/\\]", "_"
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")

function Parse-AlarmManagerDump {
    param(
        $RawDump,
        [string]$PackageName,
        [long]$TargetEpochMs = 0
    )

    $parsedRecords = @()
    $lines = if ($RawDump -is [array]) { $RawDump } else { $RawDump -split "`r?`n" }

    # Format A: AOSP / Android 12-16 active alarm queue
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match "^\s*(?<alarm_type>RTC(?:_WAKEUP)?)\s*#\d+:\s*Alarm\{(?<alarm_hash>[a-f0-9]+)\s+type\s+(?<type_num>\d+)\s+origWhen\s+(?<orig_when>\d+)\s+whenElapsed\s+(?<when_elapsed>\d+)\s+(?<pkg>[^\}]+)\}") {
            $matchedPkg = $Matches['pkg'].Trim()
            $alarmType = $Matches['alarm_type']
            $origWhen = [long]$Matches['orig_when']
            $whenElapsed = [long]$Matches['when_elapsed']

            if ($matchedPkg -match $PackageName) {
                $tag = "N/A"
                $pendingIntent = "N/A"
                $contextBlock = @($line)
                for ($j = 1; $j -le 8 -and ($i + $j) -lt $lines.Count; $j++) {
                    $nextLine = $lines[$i + $j]
                    $contextBlock += $nextLine
                    if ($nextLine -match "tag=([^\s]+)") { $tag = $Matches[1] }
                    if ($nextLine -match "operation=(PendingIntent\{.+)") { $pendingIntent = $Matches[1] }
                    if ($nextLine -match "^\s*(?:RTC(?:_WAKEUP)?|ELAPSED(?:_WAKEUP)?)\s*#\d+:") { break }
                }

                $receiverComponent = "N/A"
                if ($tag -match "AlarmReceiver") {
                    $receiverComponent = "$PackageName/com.gdelataillade.alarm.alarm.AlarmReceiver"
                } elseif ($tag -match "ScheduledNotificationReceiver") {
                    $receiverComponent = "$PackageName/com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"
                } else {
                    $receiverComponent = $tag
                }

                $parsedRecords += [PSCustomObject]@{
                    format = "FormatA_AOSP_ActiveQueue"
                    package = $matchedPkg
                    receiver_component = $receiverComponent
                    pending_intent_identity = $pendingIntent
                    intent_request_code = "NOT_SURFACED_IN_DUMPSYS"
                    orig_when_epoch_ms = $origWhen
                    orig_when_local_time = [DateTimeOffset]::FromUnixTimeMilliseconds($origWhen).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss.fff")
                    when_elapsed_ms = $whenElapsed
                    alarm_type = $alarmType
                    alarm_tag = $tag
                    raw_record = ($contextBlock -join "`n")
                }
            }
        }
    }

    return ,@($parsedRecords)
}

function Parse-NotificationDump {
    param(
        $RawDump,
        [string]$PackageName
    )

    $records = @()
    $lines = if ($RawDump -is [array]) { $RawDump } else { $RawDump -split "`r?`n" }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        # Match NotificationRecord line
        if ($line -match "NotificationRecord\((?<hash>0x[a-f0-9]+):\s*pkg=(?<pkg>[^\s]+)\s+user=UserHandle\{(?<user>\d+)\}\s+id=(?<id>-?\d+)\s+tag=(?<tag>[^\s]+)\s+importance=(?<importance>\d+)\s+key=(?<key>[^\s:]+)") {
            $recPkg = $Matches['pkg'].Trim()
            if ($recPkg -eq $PackageName) {
                $recHash = $Matches['hash']
                $recId = [int]$Matches['id']
                $recTag = $Matches['tag']
                $recImportance = [int]$Matches['importance']
                $recKey = $Matches['key']

                # Extract details from following context lines
                $contextLines = @($line)
                $channelId = "N/A"
                $flags = "N/A"
                $whenPostMs = 0
                $title = ""
                $text = ""

                if ($line -match "channel=([^\s\)]+)") {
                    $channelId = $Matches[1]
                }
                if ($line -match "flags=([^\s\)]+)") {
                    $flags = $Matches[1]
                }

                for ($j = 1; $j -le 50 -and ($i + $j) -lt $lines.Count; $j++) {
                    $ctxLine = $lines[$i + $j]
                    $contextLines += $ctxLine

                    if ($ctxLine -match "NotificationRecord\(") { break }
                    if ($channelId -eq "N/A" -and $ctxLine -match "channel=([^\s\)]+)") { $channelId = $Matches[1] }
                    if ($flags -eq "N/A" -and $ctxLine -match "flags=([^\s]+)") { $flags = $Matches[1] }
                    if ($ctxLine -match "when=(?<when1>\d+)/(?<when2>\d+)") {
                        $whenPostMs = [long]$Matches['when1']
                    }
                    if ($ctxLine -match "android\.title=String\s*\(\s*(?<t>[^\)]+)\s*\)") {
                        $title = $Matches['t'].Trim()
                    }
                    if ($ctxLine -match "android\.text=String\s*\(\s*(?<txt>[^\)]+)\s*\)") {
                        $text = $Matches['txt'].Trim()
                    }
                }

                $records += [PSCustomObject]@{
                    hash = $recHash
                    package = $recPkg
                    id = $recId
                    tag = if ($recTag -eq "null") { $null } else { $recTag }
                    importance = $recImportance
                    key = $recKey
                    channel_id = $channelId
                    flags = $flags
                    when_post_epoch_ms = $whenPostMs
                    title = $title
                    text = $text
                    raw_record = ($contextLines -join "`n")
                }
            }
        }
    }

    return ,@($records)
}

function Parse-NotificationChannels {
    param(
        $RawDump,
        [string]$PackageName
    )

    $channels = @()
    $lines = if ($RawDump -is [array]) { $RawDump } else { $RawDump -split "`r?`n" }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match "NotificationChannel\{mId='(?<id>[^']+)',\s*mName=(?<name>[^,]+),\s*mDescription=(?<desc>[^,]*),\s*mImportance=(?<imp>\d+)") {
            $chId = $Matches['id']
            $chName = $Matches['name'].Trim()
            $chDesc = $Matches['desc'].Trim()
            $chImp = [int]$Matches['imp']

            $sound = "N/A"
            $vibration = $false
            $lockedFields = 0
            $bypassDnd = $false
            $lockscreenVis = -1000

            if ($line -match "mSound=([^\s,]+)") { $sound = $Matches[1] }
            if ($line -match "mVibrationEnabled=(true|false)") { $vibration = [bool]::Parse($Matches[1]) }
            if ($line -match "mUserLockedFields=(\d+)") { $lockedFields = [int]$Matches[1] }
            if ($line -match "mBypassDnd=(true|false)") { $bypassDnd = [bool]::Parse($Matches[1]) }
            if ($line -match "mLockscreenVisibility=(-?\d+)") { $lockscreenVis = [int]$Matches[1] }

            $channels += [PSCustomObject]@{
                channel_id = $chId
                name = $chName
                description = $chDesc
                importance = $chImp
                sound = $sound
                vibration_enabled = $vibration
                user_locked_fields = $lockedFields
                bypass_dnd = $bypassDnd
                lockscreen_visibility = $lockscreenVis
            }
        }
    }

    return ,@($channels)
}

switch ($Action) {
    "profile" {
        Write-Host "Extracting full device profile for device [$DeviceId]..."
        $model = adb -s $DeviceId shell getprop ro.product.model
        $manufacturer = adb -s $DeviceId shell getprop ro.product.manufacturer
        $androidVersion = adb -s $DeviceId shell getprop ro.build.version.release
        $sdk = adb -s $DeviceId shell getprop ro.build.version.sdk
        $buildId = adb -s $DeviceId shell getprop ro.build.display.id
        $fingerprint = adb -s $DeviceId shell getprop ro.build.fingerprint
        $timezone = adb -s $DeviceId shell getprop persist.sys.timezone
        $deviceDate = adb -s $DeviceId shell date
        $batteryRaw = adb -s $DeviceId shell "dumpsys battery | grep -E 'level|powered'"
        $whitelist = adb -s $DeviceId shell "dumpsys deviceidle whitelist | grep $PackageName"
        $standbyBucket = adb -s $DeviceId shell "am get-standby-bucket $PackageName"
        $fsiAppOp = adb -s $DeviceId shell "appops get $PackageName USE_FULL_SCREEN_INTENT"
        $exactAlarm = adb -s $DeviceId shell "dumpsys package $PackageName | grep -E 'SCHEDULE_EXACT_ALARM: granted|USE_EXACT_ALARM: granted'"
        $postNotif = adb -s $DeviceId shell "dumpsys package $PackageName | grep 'POST_NOTIFICATIONS: granted'"
        $appSettingsLine = (adb -s $DeviceId shell "dumpsys notification --noredact | grep 'AppSettings: $PackageName'")
        $notifEnabled = if ($appSettingsLine -match "importance=(\w+)") { "ENABLED (importance=" + $Matches[1] + ")" } elseif ($postNotif -match "granted=true") { "ENABLED" } else { "CHECK_LOGS" }

        $deviceProfile = [ordered]@{
            device_id = $DeviceId
            model = ("$model").Trim()
            manufacturer = ("$manufacturer").Trim()
            android_version = ("$androidVersion").Trim()
            api_level = ("$sdk").Trim()
            build_id = ("$buildId").Trim()
            build_fingerprint = ("$fingerprint").Trim()
            device_timezone = ("$timezone").Trim()
            device_date_time = ("$deviceDate").Trim()
            battery_status = ($batteryRaw -join "; ").Trim()
            battery_whitelist = ($whitelist -join "; ").Trim()
            standby_bucket = ("$standbyBucket").Trim()
            full_screen_intent_appop = ($fsiAppOp -join "; ").Trim()
            exact_alarm_permission = ($exactAlarm -join "; ").Trim()
            post_notification_permission = ($postNotif -join "; ").Trim()
            notifications_enabled_os = ("$notifEnabled").Trim()
            recorded_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        }

        $jsonOutput = $deviceProfile | ConvertTo-Json -Depth 4
        $outputFile = Join-Path $EvidenceDir "profile_${safeDeviceId}_${timestamp}.json"
        $jsonOutput | Out-File -FilePath $outputFile -Encoding utf8
        Write-Host "Profile saved to $outputFile"
        Write-Output $jsonOutput
    }

    "dump-alarm" {
        Write-Host "Dumping AlarmManager state for device [$DeviceId]..."
        $fullDump = adb -s $DeviceId shell dumpsys alarm
        $outputFile = Join-Path $EvidenceDir "dumpsys_alarm_${safeDeviceId}_${timestamp}.txt"
        $fullDump | Out-File -FilePath $outputFile -Encoding utf8
        Write-Host "Full AlarmManager dump saved to $outputFile"

        $appAlarms = $fullDump | Select-String -Pattern $PackageName -Context 2, 4
        if ($appAlarms) {
            Write-Host "App Alarm records found in AlarmManager:"
            $appAlarms | ForEach-Object { $_.ToString() }
        } else {
            Write-Host "Zero active Alarm records found for $PackageName"
        }
    }

    # B2: Target Alarm Verifier (Phase 2D.1)
    "verify-target-alarm" {
        Write-Host "Verifying Target Alarm in Android AlarmManager state on device [$DeviceId]..."
        Write-Host "Expected Target Epoch: $ScheduledEpochMs | Expected ID: $ExpectedId"

        $rawDumpFile = Join-Path $EvidenceDir "raw_dumpsys_alarm_${safeDeviceId}_${timestamp}.txt"
        $fullDump = adb -s $DeviceId shell dumpsys alarm
        $fullDump | Out-File -FilePath $rawDumpFile -Encoding utf8

        $pidRaw = adb -s $DeviceId shell "pidof $PackageName"
        $currentPid = ($pidRaw -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
        if (-not $currentPid) { $currentPid = $null }
        $processState = if ($currentPid) { "RUNNING" } else { "DEAD" }

        $parsedAlarms = Parse-AlarmManagerDump -RawDump $fullDump -PackageName $PackageName -TargetEpochMs $ScheduledEpochMs
        $targetRecord = $null

        foreach ($rec in $parsedAlarms) {
            if ($ScheduledEpochMs -gt 0 -and $rec.orig_when_epoch_ms -eq $ScheduledEpochMs -and $rec.alarm_tag -match "AlarmReceiver") {
                $targetRecord = $rec
                break
            } elseif ($ScheduledEpochMs -le 0 -and $rec.alarm_tag -match "AlarmReceiver") {
                $targetRecord = $rec
                break
            }
        }

        $targetFound = ($null -ne $targetRecord)
        $classification = "TARGET_ALARM_ABSENT_OR_DISPATCHED"
        if ($targetFound) {
            if ($processState -eq "DEAD") {
                $classification = "TARGET_ALARM_PERSISTENCE_PROVEN"
            } else {
                $classification = "TARGET_ALARM_SCHEDULED"
            }
        }

        $verificationEvidence = [ordered]@{
            verification_action = "verify-target-alarm"
            device_id = $DeviceId
            package_name = $PackageName
            expected_alarm_id = $ExpectedId
            scheduled_epoch_ms = $ScheduledEpochMs
            target_alarm_matched = $targetFound
            state_classification = $classification
            alarm_manager_description = "Android AlarmManager service scheduling state"
            process_state = $processState
            pid = $currentPid
            total_package_alarms_in_alarmmanager = @($parsedAlarms).Count
            target_identity_attributes = if ($targetFound) {
                [ordered]@{
                    package = $targetRecord.package
                    receiver_component = $targetRecord.receiver_component
                    pending_intent_identity = $targetRecord.pending_intent_identity
                    intent_request_code = $targetRecord.intent_request_code
                    orig_when_epoch_ms = $targetRecord.orig_when_epoch_ms
                    orig_when_local_time = $targetRecord.orig_when_local_time
                    when_elapsed_ms = $targetRecord.when_elapsed_ms
                    alarm_type = $targetRecord.alarm_type
                    alarm_tag = $targetRecord.alarm_tag
                }
            } else { $null }
            raw_dumpsys_evidence_file = $rawDumpFile
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
        }

        $evidenceFile = Join-Path $EvidenceDir "target_alarm_identity_${safeDeviceId}_${timestamp}.json"
        $verificationEvidence | ConvertTo-Json -Depth 5 | Out-File -FilePath $evidenceFile -Encoding utf8
        Write-Output $evidenceFile
    }

    # C4: Verify Target Notification Scheduled in AlarmManager
    "verify-target-notification-alarm" {
        Write-Host "Verifying Target Notification in Android AlarmManager on device [$DeviceId]..."
        Write-Host "Expected Target Epoch: $ScheduledEpochMs | Target ID: $TargetId"

        $rawDumpFile = Join-Path $EvidenceDir "raw_dumpsys_alarm_notif_${safeDeviceId}_${timestamp}.txt"
        $fullDump = adb -s $DeviceId shell dumpsys alarm
        $fullDump | Out-File -FilePath $rawDumpFile -Encoding utf8

        $pidRaw = adb -s $DeviceId shell "pidof $PackageName"
        $currentPid = ($pidRaw -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
        if (-not $currentPid) { $currentPid = $null }
        $processState = if ($currentPid) { "RUNNING" } else { "DEAD" }

        $parsedAlarms = Parse-AlarmManagerDump -RawDump $fullDump -PackageName $PackageName -TargetEpochMs $ScheduledEpochMs
        $targetRecord = $null

        foreach ($rec in $parsedAlarms) {
            # Check receiver component and origWhen matching within 1000ms jitter
            $epochDiff = [Math]::Abs($rec.orig_when_epoch_ms - $ScheduledEpochMs)
            if ($rec.receiver_component -match "ScheduledNotificationReceiver") {
                if ($ScheduledEpochMs -gt 0 -and $epochDiff -le 1000) {
                    $targetRecord = $rec
                    break
                } elseif ($ScheduledEpochMs -le 0) {
                    $targetRecord = $rec
                    break
                }
            }
        }

        $targetFound = ($null -ne $targetRecord)
        $classification = "TARGET_NOTIFICATION_ALARM_ABSENT_OR_DISPATCHED"
        if ($targetFound) {
            if ($processState -eq "DEAD") {
                $classification = "TARGET_NOTIFICATION_ALARM_PERSISTENCE_PROVEN"
            } else {
                $classification = "TARGET_NOTIFICATION_ALARM_SCHEDULED"
            }
        }

        $verificationEvidence = [ordered]@{
            verification_action = "verify-target-notification-alarm"
            device_id = $DeviceId
            package_name = $PackageName
            target_notification_id = $TargetId
            scheduled_epoch_ms = $ScheduledEpochMs
            target_notification_alarm_matched = $targetFound
            state_classification = $classification
            alarm_manager_description = "Android AlarmManager ScheduledNotificationReceiver queue"
            process_state = $processState
            pid = $currentPid
            total_package_alarms_in_alarmmanager = @($parsedAlarms).Count
            identity_correlation_note = "Notification ID is embedded in PendingIntent extras; identity correlated via ScheduledEpochMs, Preflight absence, and ScheduledNotificationReceiver component."
            target_identity_attributes = if ($targetFound) {
                [ordered]@{
                    package = $targetRecord.package
                    receiver_component = $targetRecord.receiver_component
                    pending_intent_identity = $targetRecord.pending_intent_identity
                    orig_when_epoch_ms = $targetRecord.orig_when_epoch_ms
                    orig_when_local_time = $targetRecord.orig_when_local_time
                    when_elapsed_ms = $targetRecord.when_elapsed_ms
                    alarm_type = $targetRecord.alarm_type
                    alarm_tag = $targetRecord.alarm_tag
                }
            } else { $null }
            raw_dumpsys_evidence_file = $rawDumpFile
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
        }

        $evidenceFile = Join-Path $EvidenceDir "target_notification_alarm_${safeDeviceId}_${timestamp}.json"
        $verificationEvidence | ConvertTo-Json -Depth 5 | Out-File -FilePath $evidenceFile -Encoding utf8

        Write-Host "`n--- Notification AlarmManager Verification ---" -ForegroundColor Cyan
        Write-Host "Target Matched: $targetFound | Classification: $classification" -ForegroundColor $(if ($targetFound) { "Green" } else { "Yellow" })
        if ($targetFound) {
            Write-Host "Receiver:      $($targetRecord.receiver_component)" -ForegroundColor Green
            Write-Host "PendingIntent: $($targetRecord.pending_intent_identity)" -ForegroundColor Green
            Write-Host "origWhen:      $($targetRecord.orig_when_epoch_ms) ($($targetRecord.orig_when_local_time))" -ForegroundColor Green
        }
        Write-Host "Structured evidence written to: $evidenceFile"
        Write-Output $evidenceFile
    }

    # C1, C3, C6: Verify Target Notification in Android NotificationManager (Posted & Visible in Shade)
    "verify-target-notification" {
        Write-Host "Verifying Target Notification in Android NotificationManager on device [$DeviceId]..."
        Write-Host "Target ID: $TargetId | Channel: $ChannelId | Scheduled Epoch: $ScheduledEpochMs"

        $rawDumpFile = Join-Path $EvidenceDir "raw_dumpsys_notification_${safeDeviceId}_${timestamp}.txt"
        $fullDump = adb -s $DeviceId shell "dumpsys notification --noredact"
        $fullDump | Out-File -FilePath $rawDumpFile -Encoding utf8

        $pidRaw = adb -s $DeviceId shell "pidof $PackageName"
        $currentPid = ($pidRaw -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
        if (-not $currentPid) { $currentPid = $null }
        $processState = if ($currentPid) { "RUNNING" } else { "DEAD" }

        # Parse Active NotificationRecords
        $parsedRecords = Parse-NotificationDump -RawDump $fullDump -PackageName $PackageName
        $targetRecord = $null

        foreach ($rec in $parsedRecords) {
            $idMatch = ($rec.id -eq $TargetId)
            $chMatch = ($ChannelId -eq "" -or $rec.channel_id -eq $ChannelId)
            $markerMatch = ($RunMarker -eq "" -or $rec.text -match [regex]::Escape($RunMarker) -or $rec.title -match [regex]::Escape($RunMarker))
            $titleMatch = ($Title -eq "" -or $rec.title -match [regex]::Escape($Title))

            if ($idMatch -and $chMatch -and $markerMatch -and $titleMatch) {
                $targetRecord = $rec
                break
            }
        }

        # C1 Tri-State Evaluation (Calibrated per Review)
        $isPostedInOs = ($null -ne $targetRecord)
        $importanceLevel = 0
        $isAlerting = $false

        if ($isPostedInOs) {
            $importanceLevel = $targetRecord.importance
            $isAlerting = ($importanceLevel -ge 3)
        }

        # C6 Latency Evaluation (Calibrated per Review: strictly distinguish early delivery)
        $deliveryDeltaMs = $null
        $latencyClassification = "NOT_APPLICABLE"
        if ($isPostedInOs -and $targetRecord.when_post_epoch_ms -gt 0 -and $ScheduledEpochMs -gt 0) {
            $deliveryDeltaMs = $targetRecord.when_post_epoch_ms - $ScheduledEpochMs
            if ($deliveryDeltaMs -lt 0) {
                $latencyClassification = "EARLY_DELIVERY"
            } elseif ($deliveryDeltaMs -le 1000) {
                $latencyClassification = "LATENCY_WITHIN_TARGET"
            } else {
                $latencyClassification = "LATENCY_DEGRADED"
            }
        }

        $overallClassification = "NOTIFICATION_ABSENT"
        if ($isPostedInOs) {
            if ($isAlerting) {
                $overallClassification = "NOTIFICATION_POSTED_WITH_ALERTING_IMPORTANCE"
            } else {
                $overallClassification = "NOTIFICATION_POSTED_LOW_IMPORTANCE"
            }
        }

        # Independent UI Evidence Capture (Shade Visibility Verification)
        $shadeUiFile = $null
        $shadeScreenshotFile = $null
        $isVisibleInShade = $false
        $shadeVerdict = "NOT_ATTEMPTED"

        if ($isPostedInOs) {
            Write-Host "Capturing independent UI evidence from Notification Shade on [$DeviceId]..." -ForegroundColor Cyan
            adb -s $DeviceId shell cmd statusbar expand-notifications
            Start-Sleep -Milliseconds 800

            $remoteXml = "/data/local/tmp/shade_${safeDeviceId}_${timestamp}.xml"
            $remotePng = "/data/local/tmp/shade_${safeDeviceId}_${timestamp}.png"
            $localXml = Join-Path $EvidenceDir "shade_ui_${safeDeviceId}_${timestamp}.xml"
            $localPng = Join-Path $EvidenceDir "shade_screenshot_${safeDeviceId}_${timestamp}.png"

            adb -s $DeviceId shell uiautomator dump $remoteXml | Out-Null
            adb -s $DeviceId shell screencap -p $remotePng | Out-Null
            adb -s $DeviceId shell cmd statusbar collapse | Out-Null

            adb -s $DeviceId pull $remoteXml $localXml | Out-Null
            adb -s $DeviceId pull $remotePng $localPng | Out-Null
            adb -s $DeviceId shell rm -f $remoteXml $remotePng | Out-Null

            if (Test-Path $localXml) {
                $shadeUiFile = $localXml
                $xmlContent = Get-Content $localXml -Raw
                # Check for target text / title or target package in shade
                $hasTitle = ($targetRecord.title -ne "" -and $xmlContent -match [regex]::Escape($targetRecord.title))
                $hasMarker = ($RunMarker -ne "" -and $xmlContent -match [regex]::Escape($RunMarker))
                $hasId = ($xmlContent -match [regex]::Escape("$TargetId"))
                $hasPkg = ($xmlContent -match [regex]::Escape($PackageName))

                if ($hasTitle -or $hasMarker -or ($hasId -and $hasPkg)) {
                    $isVisibleInShade = $true
                    $shadeVerdict = "CONFIRMED_VIA_UIAUTOMATOR_AND_SCREENSHOT"
                } else {
                    $shadeVerdict = "NOT_FOUND_IN_UI_TREE"
                }
            }
            if (Test-Path $localPng) {
                $shadeScreenshotFile = $localPng
            }
            Write-Host "Shade UI Verdict: $shadeVerdict | Visible: $isVisibleInShade" -ForegroundColor $(if ($isVisibleInShade) { "Green" } else { "Yellow" })
        }

        $verificationEvidence = [ordered]@{
            verification_action = "verify-target-notification"
            device_id = $DeviceId
            package_name = $PackageName
            target_notification_id = $TargetId
            expected_channel_id = $ChannelId
            expected_run_marker = $RunMarker
            scheduled_epoch_ms = $ScheduledEpochMs
            process_state = $processState
            pid = $currentPid
            tri_state_delivery = [ordered]@{
                is_scheduled = $false # Correlated via verify-target-notification-alarm
                is_posted_in_os = $isPostedInOs
                is_alerting_importance = $isAlerting
                is_visible_in_shade = $isVisibleInShade
                shade_verification_detail = $shadeVerdict
                importance = $importanceLevel
                overall_classification = $overallClassification
            }
            shade_ui_evidence = [ordered]@{
                is_visible_in_shade = $isVisibleInShade
                shade_verdict = $shadeVerdict
                ui_hierarchy_file = $shadeUiFile
                screenshot_file = $shadeScreenshotFile
            }
            composite_identity = if ($isPostedInOs) {
                [ordered]@{
                    matched_id = $targetRecord.id
                    matched_package = $targetRecord.package
                    matched_channel = $targetRecord.channel_id
                    matched_key = $targetRecord.key
                    matched_title = $targetRecord.title
                    matched_text = $targetRecord.text
                    matched_flags = $targetRecord.flags
                    when_post_epoch_ms = $targetRecord.when_post_epoch_ms
                }
            } else { $null }
            timing_and_latency = [ordered]@{
                scheduled_epoch_ms = $ScheduledEpochMs
                os_when_epoch_ms = if ($isPostedInOs) { $targetRecord.when_post_epoch_ms } else { $null }
                delivery_delta_ms = $deliveryDeltaMs
                target_threshold_ms = 1000
                latency_classification = $latencyClassification
                timing_note = if ($deliveryDeltaMs -ne $null -and $deliveryDeltaMs -lt 0) { "Negative delta occurs because Android AlarmManager / FLN truncates scheduling to whole seconds (...000)." } else { $null }
            }
            total_active_package_notifications = @($parsedRecords).Count
            raw_dumpsys_evidence_file = $rawDumpFile
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
        }

        $evidenceFile = Join-Path $EvidenceDir "target_notification_record_${safeDeviceId}_${timestamp}.json"
        $verificationEvidence | ConvertTo-Json -Depth 5 | Out-File -FilePath $evidenceFile -Encoding utf8

        Write-Host "`n--- Notification Verification Result ---" -ForegroundColor Cyan
        Write-Host "Posted in OS:          $isPostedInOs" -ForegroundColor $(if ($isPostedInOs) { "Green" } else { "Yellow" })
        Write-Host "Alerting Importance:  $isAlerting (Importance: $importanceLevel)" -ForegroundColor $(if ($isAlerting) { "Green" } else { "Yellow" })
        Write-Host "Classification:        $overallClassification" -ForegroundColor Green
        if ($deliveryDeltaMs -ne $null) {
            Write-Host "Delivery Latency:      $deliveryDeltaMs ms ($latencyClassification)" -ForegroundColor $(if ($latencyClassification -eq "LATENCY_WITHIN_TARGET") { "Green" } elseif ($latencyClassification -eq "EARLY_DELIVERY") { "Cyan" } else { "Yellow" })
        }
        Write-Host "Structured evidence written to: $evidenceFile"
        Write-Output $evidenceFile
    }

    # C2: Monitor Notification Lifecycle across Process Death
    "monitor-notification-lifecycle" {
        Write-Host "Starting Notification Lifecycle Monitoring on device [$DeviceId] for $DurationSeconds seconds..."
        Write-Host "Tracking Target Notification ID: $TargetId | Target Epoch: $ScheduledEpochMs"

        $rawLogcatFile = Join-Path $EvidenceDir "raw_logcat_notif_lifecycle_${safeDeviceId}_${timestamp}.txt"
        adb -s $DeviceId logcat -c
        $monitoringStartUtc = (Get-Date).ToUniversalTime()

        $pidBefore = adb -s $DeviceId shell "pidof $PackageName"
        $pidBefore = ($pidBefore -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
        if (-not $pidBefore) { $pidBefore = $null }

        Write-Host "Monitoring window active ($DurationSeconds s)... PID before: $pidBefore"
        Start-Sleep -Seconds $DurationSeconds

        $logcatDump = adb -s $DeviceId logcat -d -v time "ScheduledNotificationReceiver:V" "NotificationService:V" "NotificationManager:V" "ActivityTaskManager:I" "ActivityManager:I" "BroadcastQueue:V" "AlarmManager:V" "*:S"
        $logcatDump | Out-File -FilePath $rawLogcatFile -Encoding utf8
        Write-Host "Raw logcat captured to: $rawLogcatFile"

        $pidAfter = adb -s $DeviceId shell "pidof $PackageName"
        $pidAfter = ($pidAfter -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
        if (-not $pidAfter) { $pidAfter = $null }

        # Check for receiver dispatch
        $receiverDispatched = ($logcatDump | Select-String -Pattern "ScheduledNotificationReceiver").Count -gt 0
        $receiverLines = ($logcatDump | Select-String -Pattern "ScheduledNotificationReceiver" | ForEach-Object { $_.Line }) -join "`n"

        # Check for OS notification enqueued/posted
        $notificationEnqueued = ($logcatDump | Select-String -Pattern "enqueueNotificationInternal|NotificationService.*$PackageName").Count -gt 0
        $notificationLines = ($logcatDump | Select-String -Pattern "enqueueNotificationInternal|NotificationService.*$PackageName" | ForEach-Object { $_.Line }) -join "`n"

        # Check for process restart during broadcast
        $processRestarted = $false
        if ($pidBefore -eq $null -and $pidAfter -ne $null) {
            $processRestarted = $true
        }

        # C2 Delivery Classification
        $deliveryClassification = "DELIVERY_NOT_PROVEN"
        if ($receiverDispatched -or $notificationEnqueued) {
            if ($pidBefore -eq $null) {
                if ($processRestarted) {
                    $deliveryClassification = "POSTED_AFTER_PROCESS_DEATH_WITH_PROCESS_RESTART"
                } else {
                    $deliveryClassification = "POSTED_AFTER_PROCESS_DEATH_WITHOUT_PROCESS_RESTART"
                }
            } else {
                $deliveryClassification = "POSTED_WHILE_PROCESS_ALIVE"
            }
        }

        $lifecycleEvidence = [ordered]@{
            verification_action = "monitor-notification-lifecycle"
            device_id = $DeviceId
            package_name = $PackageName
            target_notification_id = $TargetId
            scheduled_epoch_ms = $ScheduledEpochMs
            monitoring_start_utc = $monitoringStartUtc.ToString("o")
            duration_seconds = $DurationSeconds
            pid_before = $pidBefore
            pid_after = $pidAfter
            process_restarted = $processRestarted
            receiver_dispatched = $receiverDispatched
            notification_enqueued = $notificationEnqueued
            lifecycle_classification = $deliveryClassification
            receiver_logcat_snippets = $receiverLines
            notification_logcat_snippets = $notificationLines
            raw_logcat_file = $rawLogcatFile
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
        }

        $lifecycleEvidenceFile = Join-Path $EvidenceDir "notif_lifecycle_evidence_${safeDeviceId}_${timestamp}.json"
        $lifecycleEvidence | ConvertTo-Json -Depth 5 | Out-File -FilePath $lifecycleEvidenceFile -Encoding utf8

        Write-Host "`n--- Notification Lifecycle Result ---" -ForegroundColor Cyan
        Write-Host "Receiver Dispatched:      $receiverDispatched" -ForegroundColor $(if ($receiverDispatched) { "Green" } else { "Yellow" })
        Write-Host "Notification Enqueued:    $notificationEnqueued" -ForegroundColor $(if ($notificationEnqueued) { "Green" } else { "Yellow" })
        Write-Host "Process Restarted:        $processRestarted (PID after: $pidAfter)" -ForegroundColor Cyan
        Write-Host "Lifecycle Classification: $deliveryClassification" -ForegroundColor Green
        Write-Host "Evidence JSON written to: $lifecycleEvidenceFile"
        Write-Output $lifecycleEvidenceFile
    }

    # C7: Deep Notification Channel & Permission Profile
    "profile-notification-channel" {
        Write-Host "Inspecting Notification Channels & Permissions on device [$DeviceId]..."

        $fullDump = adb -s $DeviceId shell "dumpsys notification --noredact"
        $parsedChannels = Parse-NotificationChannels -RawDump $fullDump -PackageName $PackageName

        $targetChannel = $parsedChannels | Where-Object { $_.channel_id -eq $ChannelId } | Select-Object -First 1

        $postNotif = adb -s $DeviceId shell "dumpsys package $PackageName | grep 'POST_NOTIFICATIONS: granted'"
        $exactAlarm = adb -s $DeviceId shell "dumpsys package $PackageName | grep -E 'SCHEDULE_EXACT_ALARM: granted|USE_EXACT_ALARM: granted'"
        $appSettingsLine = (adb -s $DeviceId shell "dumpsys notification --noredact | grep 'AppSettings: $PackageName'")
        $notifEnabled = if ($appSettingsLine -match "importance=(\w+)") { "ENABLED (importance=" + $Matches[1] + ")" } elseif ($postNotif -match "granted=true") { "ENABLED" } else { "CHECK_LOGS" }

        $channelProfileEvidence = [ordered]@{
            verification_action = "profile-notification-channel"
            device_id = $DeviceId
            package_name = $PackageName
            target_channel_id = $ChannelId
            channel_found = ($null -ne $targetChannel)
            target_channel_details = if ($targetChannel) {
                [ordered]@{
                    channel_id = $targetChannel.channel_id
                    name = $targetChannel.name
                    description = $targetChannel.description
                    importance = $targetChannel.importance
                    sound = $targetChannel.sound
                    vibration_enabled = $targetChannel.vibration_enabled
                    user_locked_fields = $targetChannel.user_locked_fields
                    bypass_dnd = $targetChannel.bypass_dnd
                    lockscreen_visibility = $targetChannel.lockscreen_visibility
                }
            } else { $null }
            app_notification_permissions = [ordered]@{
                notifications_enabled = ("$notifEnabled").Trim()
                post_notifications_permission = ($postNotif -join "; ").Trim()
                exact_alarm_permission = ($exactAlarm -join "; ").Trim()
            }
            all_package_channels = @($parsedChannels)
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
        }

        $channelProfileFile = Join-Path $EvidenceDir "channel_profile_${safeDeviceId}_${timestamp}.json"
        $channelProfileEvidence | ConvertTo-Json -Depth 5 | Out-File -FilePath $channelProfileFile -Encoding utf8

        Write-Host "`n--- Channel & Permissions Profile ---" -ForegroundColor Cyan
        Write-Host "Target Channel ($ChannelId): $(if ($targetChannel) { 'FOUND (Importance=' + $targetChannel.importance + ')' } else { 'NOT CREATED YET' })"
        Write-Host "App Notifications Enabled:    $($notifEnabled.Trim())"
        Write-Host "POST_NOTIFICATIONS:           $($postNotif -join '; ')"
        Write-Host "Exact Alarm Permission:       $($exactAlarm -join '; ')"
        Write-Host "Total Channels Registered:    $(@($parsedChannels).Count)"
        Write-Host "Profile written to:           $channelProfileFile"
        Write-Output $channelProfileFile
    }

    # C5: 6-Point Targeted Notification Cleanup Verifier
    "verify-notification-cleanup" {
        Write-Host "Verifying Targeted Notification Cleanup on device [$DeviceId]..."
        Write-Host "Target ID to be absent: $TargetId | Secondary ID to remain intact: $SecondaryId"

        # 1. Query NotificationManager for active NotificationRecords
        $notifDump = adb -s $DeviceId shell "dumpsys notification --noredact"
        $activeRecords = Parse-NotificationDump -RawDump $notifDump -PackageName $PackageName
        $targetInNotificationMgr = ($activeRecords | Where-Object { $_.id -eq $TargetId }).Count -gt 0
        $secondaryInNotificationMgr = ($activeRecords | Where-Object { $_.id -eq $SecondaryId }).Count -gt 0

        # 2. Query AlarmManager for active ScheduledNotificationReceiver alarms
        $alarmDump = adb -s $DeviceId shell "dumpsys alarm"
        $alarmRecords = Parse-AlarmManagerDump -RawDump $alarmDump -PackageName $PackageName
        $targetAlarmInAlarmMgr = $false
        $secondaryAlarmInAlarmMgr = $false
        foreach ($rec in $alarmRecords) {
            if ($rec.receiver_component -match "ScheduledNotificationReceiver") {
                if ($ScheduledEpochMs -gt 0 -and [Math]::Abs($rec.orig_when_epoch_ms - $ScheduledEpochMs) -le 2000) {
                    $targetAlarmInAlarmMgr = $true
                }
                if ($SecondaryEpochMs -gt 0 -and [Math]::Abs($rec.orig_when_epoch_ms - $SecondaryEpochMs) -le 2000) {
                    $secondaryAlarmInAlarmMgr = $true
                }
            }
        }

        # 6-point verification
        $point1_targetRecordAbsent = (-not $targetInNotificationMgr)
        $point2_targetAlarmAbsent = (-not $targetAlarmInAlarmMgr)
        $secondaryIntact = ($secondaryInNotificationMgr -or $secondaryAlarmInAlarmMgr)

        $cleanupVerdict = "CLEANUP_INCOMPLETE"
        if ($point1_targetRecordAbsent -and $point2_targetAlarmAbsent) {
            if ($SecondaryId -gt 0 -and ($SecondaryEpochMs -gt 0 -or $secondaryInNotificationMgr -or $secondaryAlarmInAlarmMgr)) {
                if ($secondaryIntact) {
                    $cleanupVerdict = "SURGICAL_CLEANUP_NON_INTERFERENCE_PASS"
                } else {
                    $cleanupVerdict = "SURGICAL_CLEANUP_SECONDARY_INTERFERENCE_DETECTED"
                }
            } else {
                $cleanupVerdict = "SURGICAL_CLEANUP_PASS"
            }
        }

        $cleanupEvidence = [ordered]@{
            verification_action = "verify-notification-cleanup"
            device_id = $DeviceId
            package_name = $PackageName
            target_id = $TargetId
            secondary_id = $SecondaryId
            scheduled_epoch_ms = $ScheduledEpochMs
            secondary_epoch_ms = $SecondaryEpochMs
            point1_target_notification_record_absent = $point1_targetRecordAbsent
            point2_target_notification_alarm_absent = $point2_targetAlarmAbsent
            point3_secondary_notification_intact = $secondaryIntact
            point3_secondary_in_notification_manager = $secondaryInNotificationMgr
            point3_secondary_in_alarm_manager = $secondaryAlarmInAlarmMgr
            point4_total_active_notifications_remaining = @($activeRecords).Count
            point5_remaining_notification_ids = ($activeRecords | ForEach-Object { $_.id })
            point6_surgical_cleanup_verdict = $cleanupVerdict
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
        }

        $cleanupEvidenceFile = Join-Path $EvidenceDir "notification_cleanup_${safeDeviceId}_${timestamp}.json"
        $cleanupEvidence | ConvertTo-Json -Depth 5 | Out-File -FilePath $cleanupEvidenceFile -Encoding utf8

        Write-Host "`n--- Surgical Cleanup Verification Result ---" -ForegroundColor Cyan
        Write-Host "Target ($TargetId) Notification Absent: $point1_targetRecordAbsent" -ForegroundColor $(if ($point1_targetRecordAbsent) { "Green" } else { "Red" })
        Write-Host "Target ($TargetId) Alarm Absent:        $point2_targetAlarmAbsent" -ForegroundColor $(if ($point2_targetAlarmAbsent) { "Green" } else { "Red" })
        Write-Host "Secondary ($SecondaryId) Intact:       $secondaryIntact (Notif: $secondaryInNotificationMgr, Alarm: $secondaryAlarmInAlarmMgr)" -ForegroundColor $(if ($secondaryIntact) { "Green" } else { "Yellow" })
        Write-Host "Cleanup Verdict:                      $cleanupVerdict" -ForegroundColor $(if ($cleanupVerdict -match "PASS") { "Green" } else { "Red" })
        Write-Host "Evidence written to: $cleanupEvidenceFile"
        Write-Output $cleanupEvidenceFile
    }

    "dump-notification" {
        Write-Host "Dumping NotificationManager state for device [$DeviceId]..."
        $fullDump = adb -s $DeviceId shell "dumpsys notification --noredact"
        $outputFile = Join-Path $EvidenceDir "dumpsys_notification_${safeDeviceId}_${timestamp}.txt"
        $fullDump | Out-File -FilePath $outputFile -Encoding utf8
        Write-Host "Full NotificationManager dump saved to $outputFile"

        $records = Parse-NotificationDump -RawDump $fullDump -PackageName $PackageName
        if ($records.Count -gt 0) {
            Write-Host "Active posted notifications visible for $PackageName ($($records.Count)):"
            foreach ($r in $records) {
                Write-Host " - ID: $($r.id) | Channel: $($r.channel_id) | Importance: $($r.importance) | Title: $($r.title)"
            }
        } else {
            Write-Host "Zero active notifications currently visible for $PackageName."
        }
    }

    "background-app" {
        Write-Host "Moving app to background via KEYCODE_HOME..."
        adb -s $DeviceId shell input keyevent KEYCODE_HOME
        Start-Sleep -Milliseconds 500
        $appPid = adb -s $DeviceId shell "pidof $PackageName"
        Write-Host "App is in background. PID is: $appPid"
    }

    "kill-process" {
        Write-Host "Terminating app process (simulating OS process kill without Force Stop)..."
        $pidBefore = adb -s $DeviceId shell "pidof $PackageName"
        $pidBefore = ($pidBefore -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
        if ($pidBefore) {
            Write-Host "Found running process PID: $pidBefore. Sending termination command via run-as..."
            $cmd = "run-as $PackageName /system/bin/kill $pidBefore"
            $execResult = adb -s $DeviceId shell "$cmd; echo exit_code: `$?"
            $exitCode = ($execResult -split "`r?`n" | Where-Object { $_ -match "exit_code:" }) -replace "exit_code:\s*", ""
            Start-Sleep -Milliseconds 500
            $pidAfter = adb -s $DeviceId shell "pidof $PackageName"
            $pidAfter = ($pidAfter -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)

            if ($pidAfter -and $pidAfter -eq $pidBefore) {
                Write-Host "Process still alive after SIGTERM, sending SIGKILL (-s 9)..."
                $cmd = "run-as $PackageName /system/bin/kill -s 9 $pidBefore"
                $execResult = adb -s $DeviceId shell "$cmd; echo exit_code: `$?"
                Start-Sleep -Milliseconds 500
                $pidAfter = adb -s $DeviceId shell "pidof $PackageName"
                $pidAfter = ($pidAfter -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
            }

            $alarmDump = adb -s $DeviceId shell "dumpsys alarm | grep -E '$PackageName'"
            $alarmCount = ($alarmDump -split "`r?`n" | Where-Object { $_ -match "RTC_WAKEUP" }).Count

            $evidenceRecord = [PSCustomObject]@{
                action = "SIGKILL_PROCESS_TERMINATION"
                note = "Direct process signal kill. Validates AlarmManager persistence across process death; does NOT simulate full Android LMK memory pressure."
                device_id = $DeviceId
                pid_before = $pidBefore
                command_executed = $cmd
                raw_result = $execResult
                exit_code = $exitCode
                pid_after = $pidAfter
                process_dead = (-not $pidAfter -or $pidAfter -ne $pidBefore)
                alarm_manager_intact = ($alarmCount -gt 0)
                alarm_manager_description = "Android AlarmManager service scheduling state"
                active_alarm_count = $alarmCount
                timestamp = (Get-Date).ToUniversalTime().ToString("o")
            }

            $killEvidenceFile = Join-Path $EvidenceDir "process_death_${safeDeviceId}_${timestamp}.json"
            $evidenceRecord | ConvertTo-Json -Depth 3 | Out-File -FilePath $killEvidenceFile -Encoding utf8
            Write-Host "Process termination result: PID before=$pidBefore, exit_code=$exitCode, PID after=$pidAfter, alarms_intact=$($alarmCount -gt 0) (Count: $alarmCount)"
            Write-Host "Evidence recorded: $killEvidenceFile"
        } else {
            Write-Host "App process was not running."
        }
    }

    "force-stop" {
        Write-Host "Executing Force Stop via am force-stop $PackageName..."
        adb -s $DeviceId shell am force-stop $PackageName
        Start-Sleep -Milliseconds 500
        Write-Host "App force-stopped. Note: Android cancels AlarmManager exact alarms on force stop."
    }

    "monitor-window" {
        Write-Host "Monitoring logcat and delivery for $DurationSeconds seconds on device [$DeviceId]..."
        $logFile = Join-Path $EvidenceDir "monitor_logcat_${safeDeviceId}_${timestamp}.txt"
        adb -s $DeviceId logcat -c
        $startTime = Get-Date
        $endTime = $startTime.AddSeconds($DurationSeconds)

        $job = Start-Job -ScriptBlock {
            param($dev, $pkg, $out)
            adb -s $dev logcat -v time "*:S" "AlarmPlugin:V" "AlarmService:V" "ScheduledNotificationReceiver:V" "NotificationService:V" "NotificationManager:V" "ActivityTaskManager:I" | Out-File -FilePath $out -Encoding utf8
        } -ArgumentList $DeviceId, $PackageName, $logFile

        Write-Host "Monitoring active until $($endTime.ToString('HH:mm:ss'))..."
        while ((Get-Date) -lt $endTime) {
            Start-Sleep -Seconds 1
            $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
            Write-Progress -Activity "Monitoring Delivery Window" -Status "$elapsed / $DurationSeconds seconds elapsed" -PercentComplete (($elapsed / $DurationSeconds) * 100)
        }

        Stop-Job $job | Out-Null
        Remove-Job $job | Out-Null
        Write-Host "Monitoring window finished. Log saved to $logFile"
    }
}
