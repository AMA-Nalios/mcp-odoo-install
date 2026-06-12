# Installation du serveur MCP Odoo (mcp-server-odoo) pour Claude Desktop et Claude Code
# Edite directement les fichiers de config JSON (pas besoin de la CLI `claude`)

# Force TLS 1.2 (necessaire sur Windows PowerShell 5.1 pour acceder a astral.sh/github.com)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath;$env:USERPROFILE\.local\bin"
}

function Find-Uvx {
    Refresh-Path
    $cmd = Get-Command uvx -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = "$env:USERPROFILE\.local\bin\uvx.exe"
    if (Test-Path $fallback) { return $fallback }
    return $null
}

function Install-Uv {
    Write-Host "uvx non trouve, installation de uv..."
    try {
        $installScript = (Invoke-WebRequest -Uri "https://astral.sh/uv/install.ps1" -UseBasicParsing).Content
        Invoke-Expression $installScript
    } catch {
        Write-Host "Erreur pendant le telechargement/installation de uv :"
        Write-Host $_.Exception.Message
        return $false
    }
    return $true
}

function Update-McpConfig {
    param(
        [string]$ConfigPath,
        [bool]$IncludeType,
        [string]$Label,
        [string]$UvxPath,
        [string]$McpName,
        [string]$OdooUrl,
        [string]$OdooDb,
        [string]$OdooUser,
        [string]$OdooApiKey
    )

    $dir = Split-Path -Parent $ConfigPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if (-not (Test-Path $ConfigPath)) {
        "{}" | Set-Content $ConfigPath -Encoding UTF8
    }

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if (-not $config.PSObject.Properties.Name.Contains("mcpServers")) {
        $config | Add-Member -MemberType NoteProperty -Name mcpServers -Value (New-Object PSObject)
    }

    $envBlock = [PSCustomObject]@{
        ODOO_URL               = $OdooUrl
        ODOO_DB                = $OdooDb
        ODOO_USER              = $OdooUser
        ODOO_API_KEY           = $OdooApiKey
        ODOO_YOLO              = "true"
        ODOO_MCP_DEFAULT_LIMIT = "100"
        ODOO_MCP_MAX_LIMIT     = "1000"
    }

    if ($IncludeType) {
        $odooEntry = [PSCustomObject]@{
            type    = "stdio"
            command = $UvxPath
            args    = @("mcp-server-odoo@0.4.0")
            env     = $envBlock
        }
    } else {
        $odooEntry = [PSCustomObject]@{
            command = $UvxPath
            args    = @("mcp-server-odoo@0.4.0")
            env     = $envBlock
        }
    }

    if ($config.mcpServers.PSObject.Properties.Name.Contains($McpName)) {
        $config.mcpServers.$McpName = $odooEntry
    } else {
        $config.mcpServers | Add-Member -MemberType NoteProperty -Name $McpName -Value $odooEntry
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
    Write-Host "$Label mis a jour : $ConfigPath"
}

function Install-McpOdoo {
    $ErrorActionPreference = "Stop"
    Write-Host "=== Installation MCP Server Odoo ==="
    Write-Host ""

    # 1. Verifier/installer uv (fournit uvx)
    $uvxPath = Find-Uvx
    if (-not $uvxPath) {
        if (-not (Install-Uv)) {
            Write-Host ""
            Write-Host "Impossible d'installer uv automatiquement."
            Write-Host "Essaie manuellement : winget install astral-sh.uv -e"
            Write-Host "puis redemarre PowerShell et relance ce script."
            return
        }
        $uvxPath = Find-Uvx
        if (-not $uvxPath) {
            Write-Host ""
            Write-Host "Erreur : uvx introuvable apres installation."
            Write-Host "Verifie que ce dossier contient uvx.exe : $env:USERPROFILE\.local\bin"
            Write-Host "Sinon, redemarre PowerShell (pour rafraichir le PATH) et relance ce script."
            return
        }
    }
    Write-Host "uvx trouve : $uvxPath"
    Write-Host ""

    # 2. Demander les identifiants Odoo
    Write-Host "Pour info :"
    Write-Host "  - URL Odoo : l'adresse de votre instance (ex: https://nalios.odoo.com)"
    Write-Host "  - Base de donnees : visible dans le selecteur de base au login, ou dans l'URL"
    Write-Host "  - Email / utilisateur : votre identifiant de connexion Odoo"
    Write-Host "  - Cle API : Odoo > votre profil (en haut a droite) > Compte > Securite du compte > Nouvelle cle API"
    Write-Host ""
    $mcpName = Read-Host "Nom du serveur MCP (ex: odoo) [odoo]"
    if ([string]::IsNullOrWhiteSpace($mcpName)) { $mcpName = "odoo" }
    $odooUrl = Read-Host "URL Odoo (ex: https://nalios.odoo.com)"
    $odooDb = Read-Host "Nom de la base de donnees"
    $odooUser = Read-Host "Email / utilisateur Odoo"
    $odooApiKeySecure = Read-Host "Cle API Odoo" -AsSecureString
    $odooApiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($odooApiKeySecure))
    Write-Host ""

    # 3. Mettre a jour les configs (Claude Desktop + Claude Code)
    $updateArgs = @{
        UvxPath    = $uvxPath
        McpName    = $mcpName
        OdooUrl    = $odooUrl
        OdooDb     = $odooDb
        OdooUser   = $odooUser
        OdooApiKey = $odooApiKey
    }

    # Claude Desktop
    $desktopConfig = "$env:APPDATA\Claude\claude_desktop_config.json"
    if (Test-Path "$env:APPDATA\Claude") {
        Update-McpConfig -ConfigPath $desktopConfig -IncludeType $false -Label "Claude Desktop" @updateArgs
    } else {
        Write-Host "Claude Desktop non detecte ($desktopConfig) - etape ignoree."
    }

    # Claude Code (config utilisateur globale)
    $claudeCodeConfig = "$env:USERPROFILE\.claude.json"
    if (Test-Path $claudeCodeConfig) {
        Update-McpConfig -ConfigPath $claudeCodeConfig -IncludeType $true -Label "Claude Code" @updateArgs
    } else {
        Write-Host "Config Claude Code non trouvee ($claudeCodeConfig) - etape ignoree."
    }

    Write-Host ""
    Write-Host "=== Termine ==="
    Write-Host "Redemarre Claude Desktop et Claude Code pour activer le serveur MCP '$mcpName'."
}

try {
    Install-McpOdoo
} catch {
    Write-Host ""
    Write-Host "Erreur inattendue : $($_.Exception.Message)"
}
Write-Host ""
Read-Host "Appuie sur Entree pour fermer cette fenetre" | Out-Null
