$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$RebootRequired = $false
$UpdateFailed = $false

$WinRarTargetVersion = [version]"7.23.0"

$WinRarInstallerUrl =
    "https://www.rarlab.com/rar/winrar-x64-723.exe"

$WinRarInstallerPath =
    Join-Path $env:TEMP "winrar-x64-723.exe"

function Convert-WinRARVersionText {

    param (
        [string]$Text
    )

    $match = $null
    $parsed = $null

    $match = [regex]::Match([string]$Text, "(\d+\.\d+(?:\.\d+){0,2})")

    if ($match.Success -eq $true) {
        $parsed = [version]$match.Groups[1].Value

        if ($parsed.Build -lt 0) {
            $parsed = [version]("$($parsed.Major).$($parsed.Minor).0")
        }

        return ($parsed)
    }
}

function Get-WinRARVersion {

    $versions = $null
    $raw = $null

    $versions = @(
        Get-ItemProperty -Path @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        ) -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "WinRAR*" } |
        ForEach-Object {
            $raw = $_.DisplayVersion

            if ($null -eq $raw -or $raw -eq "") {
                $raw = $_.DisplayName
            }

            Convert-WinRARVersionText -Text $raw
        }
    )

    return ($versions | Sort-Object -Descending | Select-Object -First 1)
}

$startTime = Get-Date
$exitCode = 0
$exitText = "Esito Action1: OK."

try {

    $currentVersion = Get-WinRARVersion

    if ($null -eq $currentVersion) {
        Write-Host "WinRAR non è stato rilevato. Aggiornamento ignorato."
    }
    elseif ($currentVersion -ge $WinRarTargetVersion) {
        Write-Host "WinRAR è già aggiornato. Versione installata: $currentVersion"
    }
    else {

        Write-Host "Aggiornamento da $currentVersion a $WinRarTargetVersion"

        Get-Process `
            -Name "WinRAR", "Rar", "UnRAR" `
            -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue

        Invoke-WebRequest `
            -Uri $WinRarInstallerUrl `
            -OutFile $WinRarInstallerPath `
            -UseBasicParsing `
            -TimeoutSec 600 `
            -UserAgent "Action1-SoftwareUpdate/1.0" |
            Out-Null

        $process = Start-Process `
            -FilePath $WinRarInstallerPath `
            -ArgumentList "-s1" `
            -PassThru `
            -Wait

        Write-Host "Codice uscita installer: $($process.ExitCode)"

        if ($process.ExitCode -eq 3010) {
            $RebootRequired = $true
        }

        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
            throw "Installazione WinRAR fallita. Codice: $($process.ExitCode)"
        }

        Start-Sleep -Seconds 3

        $newVersion = Get-WinRARVersion

        if ($null -eq $newVersion) {
            Write-Warning "Impossibile verificare la versione finale di WinRAR."
        }
        elseif ($newVersion -lt $WinRarTargetVersion) {

            Write-Warning "La versione finale di WinRAR ($newVersion) è inferiore a quella richiesta ($WinRarTargetVersion)."
            $UpdateFailed = $true
        }
        else {
            Write-Host "WinRAR aggiornato correttamente. Versione finale: $newVersion"
        }
    }
}
catch {
    Write-Host "ERRORE WinRAR: $($_.Exception.Message)"
    $UpdateFailed = $true
}

Remove-Item $WinRarInstallerPath -Force -ErrorAction SilentlyContinue

if ($UpdateFailed -eq $true) {

    $exitCode = 1
    $exitText = "Esito Action1: FALLITO."
}
elseif ($RebootRequired -eq $true) {

    $exitCode = 3010
    $exitText = "Esito Action1: OK, riavvio richiesto (3010)."
}

Write-Host ("Fine: " + ((Get-Date) - $startTime).ToString("hh\:mm\:ss"))
Write-Host $exitText

exit $exitCode
