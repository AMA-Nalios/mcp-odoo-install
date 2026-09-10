# Installation du serveur MCP Odoo (mcp-server-odoo) pour Claude Desktop
# Variante "installation persistante" : pour les postes ou l'utilisateur n'a pas les
# droits admin (impossible d'exclure le cache uv de l'antivirus) et ou l'erreur pywin32
# (os error 32 : fichier utilise par un autre processus) revient a chaque redemarrage
# de Claude Desktop. Cause : avec uvx, Claude Desktop reconstruit un environnement
# ephemere et reinstalle pywin32 a CHAQUE lancement -> nouvelle course avec le scan
# antivirus temps reel a chaque fois, meme si un lancement precedent a reussi.
#
# Ici, mcp-server-odoo est installe une seule fois de facon persistante via
# "uv tool install" (aucun droit admin requis), et Claude Desktop appelle ensuite
# directement l'executable installe. Plus aucune installation ne se produit au
# lancement de Claude Desktop -> plus de course, plus de boucle d'echec.
#
# Contrepartie : pour changer de version de mcp-server-odoo plus tard, il faut
# relancer ce script (ou "uv tool install mcp-server-odoo==X.Y.Z --force") au lieu
# de simplement changer le pin dans la config.
#
# Python signe (python.org) au lieu du build uv non signe + UV_PYTHON_PREFERENCE=only-system :
# evite le blocage "Une strategie de controle d'application a bloque ce fichier" (os error 4551)
# par Smart App Control (Windows 11) ou un antivirus avec controle d'application, qui bloquent
# les builds Python "standalone" non signes que uv telecharge par defaut.
#
# Usage : irm https://raw.githubusercontent.com/AMA-Nalios/mcp-odoo-install/main/install-mcp-odoo-windows-persistent.ps1 | iex
# Usage (test de la generation JSON, sans toucher a la vraie config) : .\install-mcp-odoo-windows-persistent.ps1 -Test

param([switch]$Test)

# Force TLS 1.2 (necessaire sur Windows PowerShell 5.1)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Find-ClaudeDesktopConfig {
    # Installeur classique
    if (Test-Path "$env:APPDATA\Claude") {
        return "$env:APPDATA\Claude\claude_desktop_config.json"
    }
    # Microsoft Store (Claude_pzs8sxrjxfjjc ou variante)
    $pkg = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Claude_*" -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if ($pkg) {
        $msPath = "$($pkg.FullName)\LocalCache\Roaming\Claude"
        if (Test-Path $msPath) {
            return "$msPath\claude_desktop_config.json"
        }
    }
    return $null
}

# Isolee dans sa propre fonction (parametre explicite) pour pouvoir la tester
# independamment du PATH reel de la machine (cf. Test-ConfigGeneration).
function Find-UvxInWinGetPackages {
    param([string]$LocalAppData)

    $wingetPkg = Get-ChildItem "$LocalAppData\Microsoft\WinGet\Packages" -Filter "astral-sh.uv_*" -Directory -ErrorAction SilentlyContinue |
                 Select-Object -First 1
    if ($wingetPkg) {
        $p = Join-Path $wingetPkg.FullName "uvx.exe"
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Find-Uvx {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path    = "$machinePath;$userPath;$env:USERPROFILE\.local\bin;$env:LOCALAPPDATA\uv\bin"

    $cmd = Get-Command uvx -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    foreach ($p in @(
        "$env:USERPROFILE\.local\bin\uvx.exe",
        "$env:LOCALAPPDATA\uv\bin\uvx.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\uvx.exe"
    )) { if (Test-Path $p) { return $p } }

    # Installe via winget : chemin non ajoute au PATH avant relance de session, on cherche dans le dossier Packages
    $p = Find-UvxInWinGetPackages -LocalAppData $env:LOCALAPPDATA
    if ($p) { return $p }

    return $null
}

function Install-Uv {
    Write-Host "uvx non trouve, installation de uv..."

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host "winget detecte, tentative via winget..."
        & winget install astral-sh.uv -e --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) { Write-Host "uv installe via winget."; return $true }
    }

    Write-Host "Tentative via l'installeur officiel astral.sh..."
    # Lance dans un sous-processus pour eviter que le exit de l'installeur ferme notre session
    & powershell.exe -NoProfile -Command "(New-Object System.Net.WebClient).DownloadString('https://astral.sh/uv/install.ps1') | Invoke-Expression"
    return ($LASTEXITCODE -eq 0)
}

# --- Smart App Control (Windows 11 22H2+) ---------------------------------
# Bloque silencieusement les binaires "non reconnus" (dont les builds Python
# standalone non signes que uv telecharge par defaut), meme sur un poste
# perso sans aucune politique IT d'entreprise. Message typique : "Une
# strategie de controle d'application a bloque ce fichier" (os error 4551).

function Get-SmartAppControlState {
    try {
        $val = Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" -Name "VerifiedAndReputablePolicyState" -ErrorAction Stop
        return $val   # 0 = Desactive, 1 = Actif (bloquant), 2 = Evaluation
    } catch {
        return $null  # cle absente -> Windows 10, ou Smart App Control jamais initialise
    }
}

function Disable-SmartAppControlIfActive {
    $state = Get-SmartAppControlState
    if ($null -eq $state -or $state -eq 0) {
        Write-Host "Smart App Control : inactif, rien a faire." -ForegroundColor DarkGray
        return
    }

    $label = if ($state -eq 2) { "en evaluation" } else { "actif" }
    Write-Host ""
    Write-Host "Smart App Control detecte ($label) : c'est probablement la cause d'un blocage" -ForegroundColor Yellow
    Write-Host "('Une strategie de controle d'application a bloque ce fichier')." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Ce script utilise par ailleurs un Python signe (python.org) pour eviter" -ForegroundColor Yellow
    Write-Host "d'avoir a le desactiver. Le desactiver reste optionnel." -ForegroundColor Yellow
    Write-Host "ATTENTION : une fois desactive, impossible de le reactiver sans reinstaller Windows." -ForegroundColor Yellow
    $answer = Read-Host "Tenter de le desactiver quand meme maintenant ? (o/N)"
    if ($answer -notmatch '^[oOyY]') {
        Write-Host "Ok, on laisse Smart App Control tel quel." -ForegroundColor DarkGray
        return
    }

    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" -Name "VerifiedAndReputablePolicyState" -Value 0 -ErrorAction Stop
        Write-Host "Smart App Control desactive via le registre. Un redemarrage est necessaire pour que ce soit pris en compte." -ForegroundColor Green
    } catch {
        Write-Host "Echec de la desactivation automatique (droits insuffisants ou cle protegee par Windows)." -ForegroundColor Red
        Write-Host "A faire manuellement : Parametres > Confidentialite et securite > Securite Windows >"
        Write-Host "  App et controle du navigateur > Controle des applications et des pilotes > Smart App Control > Desactiver."
        try { Start-Process "ms-settings:windowsdefender" -ErrorAction SilentlyContinue } catch {}
    }
}

# --- Python signe (python.org) au lieu du build uv non signe --------------
# uv telecharge par defaut un build Python "standalone" (python-build-standalone,
# non signe) : c'est ce binaire (et ses DLL) que Smart App Control / un
# antivirus avec controle d'application bloquent. On installe/reutilise a la
# place un Python officiel python.org (signe Python Software Foundation) et on
# force uv a l'utiliser tel quel, sans jamais telecharger son propre build.

function Get-LatestPython312Version {
    try {
        $html = Invoke-RestMethod -Uri "https://www.python.org/ftp/python/" -TimeoutSec 10
        $versions = [regex]::Matches($html, '3\.12\.\d+/') | ForEach-Object { $_.Value.TrimEnd('/') }
        $versions = $versions | Sort-Object { [version]$_ } -Unique
        if ($versions) { return $versions[-1] }
    } catch {}
    return "3.12.10"  # repli si python.org n'est pas joignable au moment de l'install
}

function Find-SignedPython312 {
    foreach ($root in @("HKCU:\SOFTWARE\Python\PythonCore\3.12\InstallPath", "HKLM:\SOFTWARE\Python\PythonCore\3.12\InstallPath")) {
        try {
            $installDir = (Get-ItemProperty -Path $root -Name "(default)" -ErrorAction Stop)."(default)"
        } catch { continue }
        if ($installDir) {
            $exe = Join-Path $installDir "python.exe"
            if (Test-Path $exe) { return $exe }
        }
    }
    return $null
}

function Install-SignedPython312 {
    $version = Get-LatestPython312Version
    Write-Host "Installation de Python $version signe (python.org)..."
    $installerPath = Join-Path $env:TEMP "python-$version-amd64.exe"
    try {
        Invoke-WebRequest -Uri "https://www.python.org/ftp/python/$version/python-$version-amd64.exe" -OutFile $installerPath -UseBasicParsing
    } catch {
        Write-Host "Echec du telechargement de Python $version depuis python.org : $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    # Install par utilisateur (pas de droits admin requis), avec le lanceur py.exe
    & $installerPath /quiet InstallAllUsers=0 PrependPath=0 Include_launcher=1 Include_test=0 Include_pip=1 | Out-Null
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    return Find-SignedPython312
}

function Get-SignedPython {
    $exe = Find-SignedPython312
    if ($exe) {
        Write-Host "Python signe deja present : $exe"
        return $exe
    }
    $exe = Install-SignedPython312
    if ($exe) {
        Write-Host "Python signe installe : $exe" -ForegroundColor Green
        return $exe
    }
    Write-Host "Impossible d'obtenir un Python signe, on retombe sur le build gere par uv (peut etre bloque)." -ForegroundColor Yellow
    return $null
}

# Installe mcp-server-odoo de facon persistante (retry + purge builds-v0, comme le
# pre-install de la version uvx) afin qu'il ne reste plus jamais rien a installer,
# ni maintenant ni au prochain lancement de Claude Desktop.
function Install-McpServerOdooTool {
    param([string]$UvExe, [string]$PythonArg)

    Write-Host "Installation persistante de mcp-server-odoo (uv tool install, 30-60s)..."
    $env:UV_LINK_MODE = "copy"
    $env:UV_PYTHON_PREFERENCE = "only-system"
    for ($i = 1; $i -le 6; $i++) {
        & $UvExe tool install "mcp-server-odoo==0.4.0" --python $PythonArg --force 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "mcp-server-odoo installe." -ForegroundColor Green
            return $true
        }
        Write-Host "  tentative $i echouee -> purge du cache builds-v0 et nouvel essai..."
        Remove-Item "$env:LOCALAPPDATA\uv\cache\builds-v0" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }
    return $false
}

function Get-UvToolBinDir {
    param([string]$UvExe)
    $out = & $UvExe tool dir --bin 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) { return ($out | Select-Object -Last 1).Trim() }
    return "$env:USERPROFILE\.local\bin"
}

# Windows PowerShell 5.1 ecrit un BOM UTF-8 avec Set-Content -Encoding UTF8, ce que le
# parseur JSON de Claude Desktop n'accepte pas (il reinitialise alors le fichier de config
# au demarrage). On force donc un UTF-8 sans BOM via .NET.
function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Update-Config {
    param([string]$ConfigPath, [string]$Label)

    $dir = Split-Path $ConfigPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (-not (Test-Path $ConfigPath)) { Write-Utf8NoBom -Path $ConfigPath -Content '{}' }

    $raw = (Get-Content $ConfigPath -Raw -ErrorAction SilentlyContinue) -as [string]
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = '{}' }

    try { $config = $raw | ConvertFrom-Json }
    catch { $config = [PSCustomObject]@{} }

    if ($null -eq $config -or $config -isnot [PSCustomObject]) { $config = [PSCustomObject]@{} }

    if ($null -eq $config.PSObject.Properties["mcpServers"] -or $config.mcpServers -isnot [PSCustomObject]) {
        if ($null -ne $config.PSObject.Properties["mcpServers"]) { $config.PSObject.Properties.Remove("mcpServers") }
        Add-Member -InputObject $config -MemberType NoteProperty -Name "mcpServers" -Value ([PSCustomObject]@{})
    }

    $entry = [PSCustomObject]@{
        # Executable installe par "uv tool install" : Claude Desktop le lance directement,
        # sans passer par uvx -> aucune installation/reconstruction au demarrage.
        command = $mcpExePath
        args    = @()
        env     = [PSCustomObject]@{
            ODOO_URL               = $odooUrl
            ODOO_DB                = $odooDB
            ODOO_USER              = $odooUser
            ODOO_API_KEY           = $odooApiKey
            ODOO_YOLO              = "true"
            ODOO_MCP_DEFAULT_LIMIT = "100"
            ODOO_MCP_MAX_LIMIT     = "1000"
        }
    }

    if ($null -ne $config.mcpServers.PSObject.Properties[$mcpName]) {
        $config.mcpServers.$mcpName = $entry
    } else {
        Add-Member -InputObject $config.mcpServers -MemberType NoteProperty -Name $mcpName -Value $entry
    }

    $json = $config | ConvertTo-Json -Depth 10

    # Validation : round-trip du JSON genere pour s'assurer qu'il est bien forme
    # avant d'ecraser la config existante (evite de crasher Claude Desktop au demarrage)
    try {
        $reparsed = $json | ConvertFrom-Json
        if ($reparsed.mcpServers.$mcpName.command -ne $mcpExePath) {
            throw "le chemin de commande ne correspond pas apres relecture du JSON"
        }
    } catch {
        Write-Host "Erreur : le JSON genere pour $Label est invalide, ecriture annulee ($($_.Exception.Message))" -ForegroundColor Red
        return
    }

    Write-Utf8NoBom -Path $ConfigPath -Content $json
    Write-Host "$Label mis a jour : $ConfigPath"
}

function Test-ConfigGeneration {
    Write-Host "=== Test de generation (fausses infos) ===" -ForegroundColor Cyan
    Write-Host ""

    $tmpRoot   = Join-Path ([System.IO.Path]::GetTempPath()) "mcp-odoo-test-persistent"
    $tmpConfig = Join-Path $tmpRoot "test_claude_desktop_config.json"
    if (Test-Path $tmpRoot) { Remove-Item $tmpRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

    $script:mcpExePath = Join-Path $tmpRoot ".local\bin\mcp-server-odoo.exe"
    $script:mcpName    = "odoo"
    $script:odooUrl    = "https://exemple.odoo.com"
    $script:odooDB     = "exemple-db"
    $script:odooUser   = "test@exemple.com"
    $script:odooApiKey = "fake-api-key-1234567890"

    Update-Config -ConfigPath $tmpConfig -Label "Test"

    if (-not (Test-Path $tmpConfig)) {
        Write-Host "Echec : le fichier de test n'a pas ete cree." -ForegroundColor Red
        Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($tmpConfig)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Host "Echec : le fichier ecrit contient un BOM UTF-8 (Claude Desktop risque de crasher au parsing)." -ForegroundColor Red
    } else {
        Write-Host "OK : pas de BOM UTF-8 en tete de fichier." -ForegroundColor Green
    }

    try {
        $reparsed = Get-Content $tmpConfig -Raw | ConvertFrom-Json
        $cmd = $reparsed.mcpServers.odoo.command
        if ($cmd -ne $mcpExePath) {
            Write-Host "Echec : le chemin relu ($cmd) ne correspond pas au chemin calcule ($mcpExePath)." -ForegroundColor Red
        } else {
            Write-Host "OK : JSON valide, chemin de l'executable correctement echappe et relu :" -ForegroundColor Green
            Write-Host "  $cmd"
        }
    } catch {
        Write-Host "Echec : JSON invalide genere ($($_.Exception.Message))" -ForegroundColor Red
    } finally {
        Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Main {
    Write-Host "=== Installation MCP Server Odoo (variante persistante, sans droits admin) ===" -ForegroundColor Cyan
    Write-Host ""

    # 0. Config Claude Desktop (verifie en premier pour eviter de tout faire pour rien)
    $script:configPath = Find-ClaudeDesktopConfig
    if (-not $configPath) {
        Write-Host "Claude Desktop non detecte automatiquement." -ForegroundColor Yellow
        Write-Host "Pour trouver le chemin : Claude Desktop > Parametres > Developpeur > Modifier la configuration"
        $custom = Read-Host "Chemin vers claude_desktop_config.json (vide pour annuler)"
        if ($custom) {
            $script:configPath = $custom.Trim('"')
        } else {
            Write-Host ""
            Write-Host "Installation annulee : impossible de localiser la config Claude Desktop." -ForegroundColor Red
            return
        }
    }
    Write-Host "Config Claude Desktop trouvee : $configPath"
    Write-Host ""

    # 1. Smart App Control (best-effort, avec confirmation avant toute modification)
    Disable-SmartAppControlIfActive
    Write-Host ""

    # 2. uvx (utilise uniquement pour installer, jamais reference dans la config finale)
    $script:uvxPath = Find-Uvx
    if (-not $uvxPath) {
        if (-not (Install-Uv)) {
            Write-Host ""
            Write-Host "Impossible d'installer uv. Essaie manuellement : winget install astral-sh.uv -e"
            return
        }
        $script:uvxPath = Find-Uvx
        if (-not $uvxPath) {
            Write-Host "Erreur : uvx introuvable apres installation."
            return
        }
    }
    Write-Host "uvx trouve : $uvxPath"

    $uvBin = Split-Path $uvxPath
    $uvExe = Join-Path $uvBin "uv.exe"
    if (-not (Test-Path $uvExe)) {
        Write-Host "Erreur : uv.exe introuvable a cote de uvx.exe ($uvBin)." -ForegroundColor Red
        return
    }
    Write-Host ""

    # 2b. Python signe (python.org) : evite que uv telecharge son propre build non signe,
    # bloquable par Smart App Control / un antivirus avec controle d'application.
    $script:pythonArg = Get-SignedPython
    if (-not $pythonArg) { $script:pythonArg = "3.12" }  # repli : comportement d'origine (build uv)
    Write-Host ""

    # 2c. Installation persistante (le vrai fix : plus rien a installer au lancement de
    # Claude Desktop, donc plus de course avec l'antivirus a chaque redemarrage).
    if (-not (Install-McpServerOdooTool -UvExe $uvExe -PythonArg $pythonArg)) {
        Write-Host ""
        Write-Host "Installation impossible apres plusieurs tentatives (probablement un verrou antivirus recurrent)." -ForegroundColor Red
        Write-Host "Reessaie de relancer ce script ; si ca persiste, il faudra une exclusion antivirus cote IT."
        return
    }

    $toolBinDir = Get-UvToolBinDir -UvExe $uvExe
    $script:mcpExePath = Join-Path $toolBinDir "mcp-server-odoo.exe"
    if (-not (Test-Path $mcpExePath)) {
        Write-Host "Erreur : executable mcp-server-odoo introuvable dans $toolBinDir apres installation." -ForegroundColor Red
        return
    }
    Write-Host "Executable installe : $mcpExePath"
    Write-Host ""

    # 3. Identifiants Odoo
    Write-Host "Pour info :"
    Write-Host "  - URL Odoo        : l'adresse de votre instance (ex: https://nalios.odoo.com)"
    Write-Host "  - Base de donnees : visible dans le selecteur de base au login, ou dans l'URL"
    Write-Host "  - Email / user    : votre identifiant de connexion Odoo"
    Write-Host "  - Cle API         : Odoo > profil > Compte > Securite du compte > Nouvelle cle API"
    Write-Host ""
    $script:mcpName  = Read-Host "Nom du serveur MCP [odoo]"
    if (-not $mcpName) { $script:mcpName = "odoo" }
    $script:odooUrl  = Read-Host "URL Odoo (ex: https://nalios.odoo.com)"
    $script:odooDB   = Read-Host "Nom de la base de donnees"
    $script:odooUser = Read-Host "Email / utilisateur Odoo"
    # Pas de -AsSecureString : la console Windows gere mal le collage en mode masque
    # (bracketed paste), ce qui ne recupere qu'un seul caractere au lieu de la cle complete.
    $script:odooApiKey = Read-Host "Cle API Odoo"
    Write-Host ""

    # 4. Claude Desktop
    Update-Config -ConfigPath $configPath -Label "Claude Desktop"

    Write-Host ""
    Write-Host "=== Termine ===" -ForegroundColor Green
    Write-Host "Redemarre Claude Desktop pour activer le serveur MCP '$mcpName'."
}

try {
    if ($Test) { Test-ConfigGeneration } else { Main }
} catch {
    Write-Host ""
    Write-Host "Erreur : $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""
Read-Host "Appuie sur Entree pour fermer" | Out-Null
