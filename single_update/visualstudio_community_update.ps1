$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$RebootRequired = $false
$UpdateFailed = $false

# Stable 18.10.3 includes the Visual Studio Community 2026 security fixes through 18.8.3.
$VisualStudioTargetVersion = [version]"18.10.3"

$VisualStudioInstallerUrl =
    "https://aka.ms/vs/18/Stable/vs_community.exe"

$VisualStudioInstallerPath =
    Join-Path $env:TEMP "vs_community.exe"

function Convert-VisualStudioVersionText {

    param (
        [string]$Text
    )

    $match = $null
    $parsed = $null

    $match = [regex]::Match([string]$Text, "(\d+\.\d+\.\d+)")

    if ($match.Success -eq $false) {
        return ($null)
    }

    $parsed = [version]$match.Groups[1].Value
    return ($parsed)
}

function Get-VisualStudioCommunity {

    $vswhere = $null
    $path = $null
    $versionText = $null
    $version = $null

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"

    if ((Test-Path -LiteralPath $vswhere) -eq $false) {
        return ($null)
    }

    $path = (& $vswhere -products Microsoft.VisualStudio.Product.Community -version "[18.0,19.0)" -latest -property installationPath)
    $versionText = (& $vswhere -products Microsoft.VisualStudio.Product.Community -version "[18.0,19.0)" -latest -property catalog_productDisplayVersion)
    $version = Convert-VisualStudioVersionText -Text ([string]$versionText)

    if ($null -eq $path -or [string]$path -eq "") {
        return ($null)
    }
    return ([pscustomobject]@{
            InstallPath = ([string]$path).Trim()
            Version = $version
        })
}

function Test-VisualStudioSuccess {

    param (
        [int]$Code
    )

    $success = $null

    $success = $false

    if ($Code -eq 0 -or $Code -eq 3010 -or $Code -eq 1641) {
        $success = $true
    }

    return ($success)
}

function Start-VisualStudioBootstrapper {

    param (
        [string]$ArgumentLine
    )

    $process = $null

    $process = Start-Process `
        -FilePath $VisualStudioInstallerPath `
        -ArgumentList $ArgumentLine `
        -WorkingDirectory $env:SystemRoot `
        -PassThru `
        -Wait

    return ($process.ExitCode)
}

function Write-VisualStudioLogTail {

    param (
        [string]$Filter
    )

    $log = $null
    $text = $null

    $log = Get-ChildItem -Path $env:TEMP -Filter $Filter -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $log) {
        return ($null)
    }

    $text = Get-Content -LiteralPath $log.FullName -Tail 15 -ErrorAction SilentlyContinue
    Write-Host "Log: $($log.FullName)"
    Write-Host ($text -join [Environment]::NewLine)
    return ($null)
}

function Write-VisualStudioFailureLogs {

    Write-VisualStudioLogTail -Filter "dd_bootstrapper*.log"
    Write-VisualStudioLogTail -Filter "dd_client*.log"
    Write-VisualStudioLogTail -Filter "dd_setup*.log"
    return ($null)
}

$startTime = Get-Date
$exitCode = 0
$exitText = "Esito Action1: OK."

try {

    $current = Get-VisualStudioCommunity

    if ($null -eq $current) {
        Write-Host "Visual Studio Community 2026 non è stato rilevato. Aggiornamento ignorato."
    }
    elseif ($null -ne $current.Version -and $current.Version -ge $VisualStudioTargetVersion) {
        Write-Host "Visual Studio Community è già aggiornato. Versione installata: $($current.Version)"
    }
    else {

        Write-Host "Aggiornamento da $($current.Version) a $VisualStudioTargetVersion"
        Write-Host "Percorso: $($current.InstallPath)"

        Get-Process `
            -Name "devenv", "VSInstaller" `
            -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue

        Invoke-WebRequest `
            -Uri $VisualStudioInstallerUrl `
            -OutFile $VisualStudioInstallerPath `
            -UseBasicParsing `
            -TimeoutSec 600 `
            -UserAgent "Action1-SoftwareUpdate/1.0" |
            Out-Null

        Unblock-File -LiteralPath $VisualStudioInstallerPath -ErrorAction SilentlyContinue

        Write-Host "Aggiornamento del Visual Studio Installer"
        $installerExit = Start-VisualStudioBootstrapper -ArgumentLine "--update --quiet --wait"
        Write-Host "Codice uscita installer: $installerExit"

        if ($installerExit -eq 3010 -or $installerExit -eq 1641) {
            $RebootRequired = $true
        }

        if ((Test-VisualStudioSuccess -Code $installerExit) -eq $false) {
            Write-VisualStudioFailureLogs
            throw "Aggiornamento del Visual Studio Installer fallito. Codice: $installerExit"
        }

        Start-Sleep -Seconds 5

        $productArguments = "update --installPath `"$($current.InstallPath)`" --quiet --wait --norestart"
        Write-Host "Comando: $productArguments"
        $productExit = Start-VisualStudioBootstrapper -ArgumentLine $productArguments
        Write-Host "Codice uscita prodotto: $productExit"

        if ($productExit -eq 3010 -or $productExit -eq 1641) {
            $RebootRequired = $true
        }

        if ((Test-VisualStudioSuccess -Code $productExit) -eq $false) {
            Write-VisualStudioFailureLogs
            throw "Installazione Visual Studio Community fallita. Codice: $productExit"
        }

        Start-Sleep -Seconds 3

        $updated = Get-VisualStudioCommunity
        $newVersion = $null

        if ($null -ne $updated) {
            $newVersion = $updated.Version
        }

        if ($null -eq $newVersion) {
            Write-Warning "Impossibile verificare la versione finale di Visual Studio Community."
        }
        elseif ($newVersion -lt $VisualStudioTargetVersion) {

            Write-Warning "La versione finale di Visual Studio Community ($newVersion) è inferiore a quella richiesta ($VisualStudioTargetVersion)."
            $UpdateFailed = $true
        }
        else {
            Write-Host "Visual Studio Community aggiornato correttamente. Versione finale: $newVersion"
        }
    }
}
catch {

    Write-Host "ERRORE Visual Studio Community: $($_.Exception.Message)"
    $UpdateFailed = $true
}

Remove-Item $VisualStudioInstallerPath -Force -ErrorAction SilentlyContinue

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
