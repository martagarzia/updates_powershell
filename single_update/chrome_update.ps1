$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# dichiarazione delle variabili
# $ va sempre messo prima di una variabile in PowerShell, altrimenti la parola viene trattata come testo.
$RebootRequired = $false
$UpdateFailed = $false

#versione nuova del prodotto
$ChromeTargetVersion = [version]"154.0.8037.92"

#url del file di installazione
$ChromeInstallerUrl =
    "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"

#percorso del file di installazione
$ChromeInstallerPath =
    Join-Path $env:TEMP "GoogleChromeEnterprise64.msi"

#funzione che ottiene la versione attuale del prodotto
function Get-ChromeVersion {

    $versions = $null

    $versions = @(
        Get-ItemProperty -Path @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        ) -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "Google Chrome" } |
        ForEach-Object {
            try { [version]$_.DisplayVersion } catch { }
        }
    )

    return ($versions | Sort-Object -Descending | Select-Object -First 1)
}

# orario di inizio dello script
$startTime = Get-Date
# inizializziamo a 0 come codice di uscita
$exitCode = 0 # prodotto ok (aggiornato, gia aggiornato o assente)
$exitText = "Esito Action1: OK."

try {

    $currentVersion = Get-ChromeVersion

    # -eq è l'operatore di uguaglianza ==
    if ($null -eq $currentVersion) {
        Write-Host "Google Chrome non è stato rilevato. Aggiornamento ignorato."
    }
    # -ge è l'operatore di maggiore o uguale >=
    elseif ($currentVersion -ge $ChromeTargetVersion) {
        Write-Host "Chrome è già aggiornato. Versione installata: $currentVersion"
    }
    else {

        Write-Host "Aggiornamento da $currentVersion a $ChromeTargetVersion"

        # Usiamo ` perchè spezziamo la riga di Invoke-WebRequest in più linee per rendere i parametri più leggibili.
        # Il backtick deve essere l'ultimo carattere della riga: un commento sulla riga successiva chiude il comando.
        # -Uri è un parametro di Invoke-WebRequest che indica l'indirizzo di una risorsa, in questo caso l'url di installazione del prodotto.
        # -OutFile è un parametro di Invoke-WebRequest che indica dove salvare sul disco il file scaricato.
        # -UseBasicParsing è un parametro di Invoke-WebRequest che dice a PowerShell di scaricare la pagina con un lettore semplice, piuttosto che Internet Explorer.
        # -TimeoutSec è un parametro di Invoke-WebRequest che indica per quanti secondi il download può restare in attesa prima di essere interrotto. In questo caso 10 minuti.
        # -UserAgent è un parametro di Invoke-WebRequest che dice al server chi sta scaricando il file, altrimenti PowerShell userebbe un identificativo generico che alcuni siti rifiutano.
        # | è l'operatore pipe: intercetta il risultato di Invoke-WebRequest e lo passa a Out-Null.
        # Out-Null prende il risultato passato da | e lo butta via, in modo che PowerShell non mostri il risultato nel log.
        Invoke-WebRequest `
            -Uri $ChromeInstallerUrl `
            -OutFile $ChromeInstallerPath `
            -UseBasicParsing `
            -TimeoutSec 600 `
            -UserAgent "Action1-SoftwareUpdate/1.0" |
            Out-Null

        # Start-Process è un cmdlet di PowerShell che avvia un processo. Il nome è sempre composto da un verbo e da un nome.
        # msiexec.exe è il programma esterno che Start-Process avvia.
        # -ArgumentList è un parametro di Start-Process che contiene gli argomenti che PowerShell passa al programma appena avviato.
        # /i dice a Windows Installer di installare un pacchetto MSI.
        # "$ChromeInstallerPath" è il percorso reale del file MSI.
        # /quiet esegue l'installazione senza finestre e senza chiedere conferma.
        # /norestart impedisce a msiexec di riavviare il PC da solo, anche se l'installazione lo richiederebbe.
        # -PassThru dice a Start-Process di restituire l'oggetto del processo appena avviato, così puoi salvarlo in $process.
        # -Wait blocca lo script finché msiexec.exe non ha terminato l'installazione.
        # Il codice di uscita del processo viene salvato nella proprietà ExitCode.
        $process = Start-Process `
            msiexec.exe `
            -ArgumentList "/i `"$ChromeInstallerPath`" /quiet /norestart" `
            -PassThru `
            -Wait

        # Write-Host è un cmdlet (comando) di PowerShell che scrive un messaggio sullo schermo, qui nel log di Action1.
        # $() è l'operatore di sottoespressione. Le parentesi dicono a PowerShell: calcola quello che c'è dentro e metti il risultato al posto di $().
        # $process è la variabile che contiene l'oggetto del processo msiexec.exe
        # . è l'operatore di proprietà. Dice a PowerShell: prendi la proprietà ExitCode dell'oggetto $process.
        # ExitCode è una proprietà di default di ogni processo, dove viene salvato il codice di uscita del processo, ad es: 0 se il processo termina correttamente, 3010 se il processo termina con un riavvio richiesto, ecc.
        Write-Host "Codice uscita MSI: $($process.ExitCode)" 

        if ($process.ExitCode -eq 3010) {
            $RebootRequired = $true
        }

        # -ne è l'operatore di disuguaglianza !=
        # -and è l'operatore AND logico
        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
            throw "Installazione Google Chrome fallita. Codice: $($process.ExitCode)"
        }

        # Start-Sleep è un cmdlet (comando) verbo-nome di PowerShell che fa attendere il processo corrente un certo numero di secondi.
        # -Seconds è un parametro di Start-Sleep che indica per quanti secondi attendere.
        Start-Sleep -Seconds 3

        $newVersion = Get-ChromeVersion

        # In PowerShell $null va a sinistra, altrimenti potrebbe avere comportamento inatteso.
        if ($null -eq $newVersion) {
            Write-Warning "Impossibile verificare la versione finale di Chrome."
        }
        # -lt è l'operatore di minore di <
        elseif ($newVersion -lt $ChromeTargetVersion) {

            Write-Warning "La versione finale di Chrome ($newVersion) è inferiore a quella richiesta ($ChromeTargetVersion)."
            $UpdateFailed = $true
        }
        else {
            # -Host è un parametro di Write-Host che indica che il messaggio deve essere scritto sullo schermo.
            Write-Host "Chrome aggiornato correttamente. Versione finale: $newVersion"
        }
    }
}
# catch è la clausola di gestione degli errori. Viene eseguita se il blocco try genera un errore.
catch {
    # $_ è una variabile speciale di PowerShell che contiene l'oggetto dell'errore corrente.
    # $_.Exception.Message vuol dire il messaggio (Message) dell'errore/eccezione (Exception) che è accaduto in questo oggetto ($_).
    Write-Host "ERRORE Google Chrome: $($_.Exception.Message)"
    $UpdateFailed = $true
}

# Remove-Item è un cmdlet (comando) verbo-nome di PowerShell che elimina un file o una cartella.
# il file di installazione viene scaricato in una cartella temporanea, al termine dell'installazione quindi viene eliminato perchè non serve più.
Remove-Item $ChromeInstallerPath -Force -ErrorAction SilentlyContinue

if ($UpdateFailed -eq $true) {

    $exitCode = 1 # errore, non riavviare
    $exitText = "Esito Action1: FALLITO."
}
elseif ($RebootRequired -eq $true) {

    $exitCode = 3010 # ok, ma serve riavvio (impostare reboot Action1 su 3010)
    $exitText = "Esito Action1: OK, riavvio richiesto (3010)."
}

#Get-Date è un cmdlet (comando) verbo-nome di PowerShell che restituisce l'ora corrente.
# ora corrente (Get-Date) - ora di inizio (startTime) = tempo trascorso
# ToString è un metodo di .NET che trasforma un valore in un testo, in questo caso dandogli il formato ora:minuti:secondi.
Write-Host ("Fine: " + ((Get-Date) - $startTime).ToString("hh\:mm\:ss"))
Write-Host $exitText

exit $exitCode
