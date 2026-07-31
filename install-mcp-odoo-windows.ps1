# Installation du serveur MCP Odoo (mcp-server-odoo) pour Claude Desktop
# Usage : irm https://raw.githubusercontent.com/AMA-Nalios/mcp-odoo-install/main/install-mcp-odoo-windows.ps1 | iex
# Usage (test de la generation JSON, sans toucher a la vraie config) : .\install-mcp-odoo-windows.ps1 -Test
#
# Notes fiabilite Windows :
#  - UV_LINK_MODE=copy : evite le verrou de fichier (os error 32) lors de l'install de pywin32
#    (uv hard-linke des .pyd mappes en memoire -> Windows refuse de supprimer le temporaire).
#  - Pre-install de mcp-server-odoo a l'installation : Claude Desktop ne fait AUCUNE install
#    au lancement (plus de race pywin32 / plus d'echec au premier demarrage).
#  - Les args du serveur incluent "--python 3.12" pour taper exactement le meme cache que le pre-install.

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

# Pre-installe mcp-server-odoo dans le cache uv (copy mode + retry + purge builds-v0)
# pour que Claude Desktop n'ait RIEN a installer au lancement -> plus d'echec pywin32.
function Preinstall-McpServerOdoo {
    param([string]$UvxPath)

    Write-Host "Pre-installation de mcp-server-odoo (30-60s, evite l'erreur pywin32 au 1er lancement)..."
    $env:UV_LINK_MODE = "copy"
    for ($i = 1; $i -le 4; $i++) {
        # --help declenche la resolution + l'install puis rend la main (pas de serveur lance)
        & $UvxPath --python 3.12 mcp-server-odoo@0.4.0 --help 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "mcp-server-odoo pre-installe (cache chaud)." -ForegroundColor Green
            return $true
        }
        Write-Host "  tentative $i echouee -> purge du cache builds-v0 et nouvel essai..."
        Remove-Item "$env:LOCALAPPDATA\uv\cache\builds-v0" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    Write-Host "Pre-install non confirmee ; Claude Desktop reessaiera au lancement." -ForegroundColor Yellow
    return $false
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
        command = $uvxPath
        # --python 3.12 : meme interpreteur que le pre-install -> cache partage, aucune reinstall au lancement.
        args    = @("--python", "3.12", "mcp-server-odoo@0.4.0")
        env     = [PSCustomObject]@{
            ODOO_URL               = $odooUrl
            ODOO_DB                = $odooDB
            ODOO_USER              = $odooUser
            ODOO_API_KEY           = $odooApiKey
            ODOO_YOLO              = "true"
            ODOO_MCP_DEFAULT_LIMIT = "100"
            ODOO_MCP_MAX_LIMIT     = "1000"
            # copy au lieu de hard-link : evite le verrou de fichier pywin32 (os error 32) au cas ou.
            UV_LINK_MODE           = "copy"
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
        if ($reparsed.mcpServers.$mcpName.command -ne $uvxPath) {
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
    Write-Host "=== Test de generation (fausses infos, Find-Uvx reellement execute) ===" -ForegroundColor Cyan
    Write-Host ""

    # Reproduit le cas qui a fait planter Claude Desktop : uvx installe via WinGet
    # (pas dans le PATH ni les emplacements par defaut), nom d'utilisateur accentue.
    $tmpRoot   = Join-Path ([System.IO.Path]::GetTempPath()) "mcp-odoo-test"
    $tmpConfig = Join-Path $tmpRoot "test_claude_desktop_config.json"
    if (Test-Path $tmpRoot) { Remove-Item $tmpRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

    # Fausse arborescence WinGet avec un utilisateur accentue, comme sur la machine de Clemence
    $fakeLocalAppData = Join-Path $tmpRoot "ClémencedeWouters\AppData\Local"
    $fakePkgDir = Join-Path $fakeLocalAppData "Microsoft\WinGet\Packages\astral-sh.uv_Microsoft.Winget.Source_8wekyb3d8bbwe"
    New-Item -ItemType Directory -Path $fakePkgDir -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $fakePkgDir "uvx.exe") -Force | Out-Null

    # NB : on teste directement Find-UvxInWinGetPackages, pas Find-Uvx en entier.
    # Sous Windows, [Environment]::GetEnvironmentVariable("Path","Machine"/"User") lit le
    # registre systeme ; hors Windows (donc sur ce Mac), ces scopes n'existent pas et
    # GetEnvironmentVariable retombe sur le PATH reel du process, ce qui ferait
    # remonter le vrai uvx de la machine et fausserait le test. La partie PATH/PATH par
    # defaut de Find-Uvx ne peut donc etre validee de maniere fiable que sur un vrai Windows.
    $script:uvxPath = Find-UvxInWinGetPackages -LocalAppData $fakeLocalAppData

    $expectedUvxPath = Join-Path $fakePkgDir "uvx.exe"
    if ($uvxPath -ne $expectedUvxPath) {
        Write-Host "Echec : Find-UvxInWinGetPackages a renvoye '$uvxPath' au lieu de '$expectedUvxPath'." -ForegroundColor Red
        Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
        return
    }
    Write-Host "OK : Find-UvxInWinGetPackages a bien detecte le chemin WinGet calcule :" -ForegroundColor Green
    Write-Host "  $uvxPath"
    Write-Host "(le fallback PATH/USERPROFILE de Find-Uvx n'est pas testable de facon fiable hors Windows)" -ForegroundColor DarkGray
    Write-Host ""

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
        if ($cmd -ne $uvxPath) {
            Write-Host "Echec : le chemin relu ($cmd) ne correspond pas au chemin calcule ($uvxPath)." -ForegroundColor Red
        } else {
            Write-Host "OK : JSON valide, chemin de commande calcule par Find-Uvx correctement echappe et relu :" -ForegroundColor Green
            Write-Host "  $cmd"
        }
        # Verifie que les nouveaux champs de fiabilite sont bien presents
        $a = $reparsed.mcpServers.odoo.args
        if (($a -contains "--python") -and ($a -contains "3.12")) {
            Write-Host "OK : args incluent --python 3.12." -ForegroundColor Green
        } else {
            Write-Host "Echec : --python 3.12 absent des args." -ForegroundColor Red
        }
        if ($reparsed.mcpServers.odoo.env.UV_LINK_MODE -eq "copy") {
            Write-Host "OK : UV_LINK_MODE=copy present." -ForegroundColor Green
        } else {
            Write-Host "Echec : UV_LINK_MODE=copy absent." -ForegroundColor Red
        }
    } catch {
        Write-Host "Echec : JSON invalide genere ($($_.Exception.Message))" -ForegroundColor Red
    } finally {
        Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Main {
    Write-Host "=== Installation MCP Server Odoo ===" -ForegroundColor Cyan
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

    # 1. uvx
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

    # Pre-installer Python 3.12 via uv pour eviter le telechargement au premier lancement
    Write-Host "Pre-installation de Python 3.12 via uv (peut prendre quelques instants)..."
    & $uvxPath --help 2>&1 | Out-Null  # s'assure que uv est initialise
    $uvBin = Split-Path $uvxPath
    $uvExe = Join-Path $uvBin "uv.exe"
    if (Test-Path $uvExe) {
        & $uvExe python install 3.12 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "Python 3.12 installe." }
        else { Write-Host "Python 3.12 deja present ou telechargement ignore." }
    }
    Write-Host ""

    # 1b. Pre-installer mcp-server-odoo (le vrai fix : rien a installer au lancement de Claude Desktop)
    Preinstall-McpServerOdoo -UvxPath $uvxPath | Out-Null
    Write-Host ""

    # 2. Identifiants Odoo
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

    # 3. Claude Desktop
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