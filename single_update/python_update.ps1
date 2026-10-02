$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$RebootRequired = $false
$UpdateFailed = $false

$PythonTargetVersion = [version]"3.14.7"

$PythonInstallerUrl =
    "https://www.python.org/ftp/python/3.14.7/python-3.14.7-amd64.exe"

$PythonInstallerPath =
    Join-Path $env:TEMP "python-3.14.7-amd64.exe"

function Test-PythonDisplayName {

    param (
        [string]$DisplayName
    )

    $name = $null
    $blocked = $null

    $name = ([string]$DisplayName).ToLowerInvariant()
    $blocked = "launcher|documentation|test suite|pip bootstrap|tcl/tk|add to path|development libraries|standard library|executables"

    if ($name -eq "") {
        return ($false)
    }

    if ($name -match $blocked) {
        return ($false)
    }

    if ($name -like "python *") {
        return ($true)
    }

    return ($name -like "python3*")
}

function Convert-PythonVersion {

    param (
        [version]$Value
    )

    $major = $null
    $minor = $null
    $micro = $null
    $suffix = $null

    $major = $Value.Major
    $minor = $Value.Minor
    $micro = $Value.Build
    $suffix = 0

    if ($micro -lt 0) {
        $micro = 0
    }

    if ($micro -ge 1000) {
        $suffix = $micro % 1000

        if ($suffix -ge 100 -and $suffix -le 159) {
            $micro = [int][math]::Floor($micro / 1000)
        }
    }

    return ([version]("$major.$minor.$micro"))
}

function Convert-PythonVersionText {

    param (
        [string]$Text
    )

    $match = $null
    $parsed = $null

    $match = [regex]::Match([string]$Text, '(\d+\.\d+(?:\.\d+){0,2})')

    if ($match.Success -eq $true) {
        try {
            $parsed = [version]$match.Groups[1].Value
        }
        catch {
        }

        if ($null -ne $parsed) {
            return (Convert-PythonVersion -Value $parsed)
        }
    }
}

function Get-PythonVersion {

    $versions = $null
    $raw = $null

    $versions = @(
        Get-ItemProperty -Path @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        ) -ErrorAction SilentlyContinue |
        Where-Object { (Test-PythonDisplayName -DisplayName $_.DisplayName) -eq $true } |
        ForEach-Object {
            $raw = $_.DisplayVersion

            if ($null -eq $raw -or $raw -eq "") {
                $raw = $_.DisplayName
            }

            Convert-PythonVersionText -Text $raw
        }
    )

    return ($versions | Sort-Object -Descending | Select-Object -First 1)
}

$startTime = Get-Date
$exitCode = 0
$exitText = "Esito Action1: OK."

try {

    $currentVersion = Get-PythonVersion

    if ($null -eq $currentVersion) {
        Write-Host "Python non è stato rilevato. Aggiornamento ignorato."
    }
    elseif ($currentVersion -ge $PythonTargetVersion) {
        Write-Host "Python è già aggiornato. Versione installata: $currentVersion"
    }
    else {

        Write-Host "Aggiornamento da $currentVersion a $PythonTargetVersion"

        Get-Process `
            -Name "python", "pythonw", "py" `
            -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue

        Invoke-WebRequest `
            -Uri $PythonInstallerUrl `
            -OutFile $PythonInstallerPath `
            -UseBasicParsing `
            -TimeoutSec 600 `
            -UserAgent "Action1-SoftwareUpdate/1.0" |
            Out-Null

        $process = Start-Process `
            -FilePath $PythonInstallerPath `
            -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Shortcuts=0 /norestart" `
            -PassThru `
            -Wait

        Write-Host "Codice uscita installer: $($process.ExitCode)"

        if ($process.ExitCode -eq 3010) {
            $RebootRequired = $true
        }

        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
            throw "Installazione Python fallita. Codice: $($process.ExitCode)"
        }

        Start-Sleep -Seconds 3

        $newVersion = Get-PythonVersion

        if ($null -eq $newVersion) {
            Write-Warning "Impossibile verificare la versione finale di Python."
        }
        elseif ($newVersion -lt $PythonTargetVersion) {

            Write-Warning "La versione finale di Python ($newVersion) è inferiore a quella richiesta ($PythonTargetVersion)."
            $UpdateFailed = $true
        }
        else {
            Write-Host "Python aggiornato correttamente. Versione finale: $newVersion"
        }
    }
}
catch {

    Write-Host "ERRORE Python: $($_.Exception.Message)"
    $UpdateFailed = $true
}

Remove-Item $PythonInstallerPath -Force -ErrorAction SilentlyContinue

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
