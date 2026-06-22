# Installation du serveur MCP Odoo (mcp-server-odoo) pour Claude Desktop
# Usage : irm https://raw.githubusercontent.com/AMA-Nalios/mcp-odoo-install/main/install-mcp-odoo-windows.ps1 | iex

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

function Find-Uvx {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path    = "$machinePath;$userPath;$env:USERPROFILE\.local\bin;$env:LOCALAPPDATA\uv\bin"

    $cmd = Get-Command uvx -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    foreach ($p in @(
        "$env:USERPROFILE\.local\bin\uvx.exe",
        "$env:LOCALAPPDATA\uv\bin\uvx.exe"
    )) { if (Test-Path $p) { return $p } }

    return $null
}

function Install-Uv {
    Write-Host "uvx non trouve, installation de uv..."

    $pip = Get-Command pip -ErrorAction SilentlyContinue
    if ($pip) {
        Write-Host "pip detecte, tentative via pip..."
        & pip install uv --quiet
        if ($LASTEXITCODE -eq 0) { Write-Host "uv installe via pip."; return $true }
    }

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

function Update-Config {
    param([string]$ConfigPath, [string]$Label)

    $dir = Split-Path $ConfigPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (-not (Test-Path $ConfigPath)) { '{}' | Set-Content $ConfigPath -Encoding UTF8 }

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
        args    = @("mcp-server-odoo@0.4.0")
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

    $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
    Write-Host "$Label mis a jour : $ConfigPath"
}

function Main {
    Write-Host "=== Installation MCP Server Odoo ===" -ForegroundColor Cyan
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
    $secure          = Read-Host "Cle API Odoo" -AsSecureString
    $script:odooApiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    )
    Write-Host ""

    # 3. Claude Desktop
    $configPath = Find-ClaudeDesktopConfig
    if ($configPath) {
        Update-Config -ConfigPath $configPath -Label "Claude Desktop"
    } else {
        Write-Host "Claude Desktop non detecte automatiquement."
        Write-Host "Pour trouver le chemin : Claude Desktop > Parametres > Developpeur > Modifier la configuration"
        $custom = Read-Host "Chemin vers claude_desktop_config.json (vide pour ignorer)"
        if ($custom) { Update-Config -ConfigPath $custom.Trim('"') -Label "Claude Desktop" }
    }

    Write-Host ""
    Write-Host "=== Termine ===" -ForegroundColor Green
    Write-Host "Redemarre Claude Desktop pour activer le serveur MCP '$mcpName'."
}

try {
    Main
} catch {
    Write-Host ""
    Write-Host "Erreur : $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""
Read-Host "Appuie sur Entree pour fermer" | Out-Null
