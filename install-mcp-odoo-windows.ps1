# Installation du serveur MCP Odoo (mcp-server-odoo) pour Claude Desktop et Claude Code
# Edite directement les fichiers de config JSON (pas besoin de la CLI `claude`)
$ErrorActionPreference = "Stop"

Write-Host "=== Installation MCP Server Odoo ==="
Write-Host ""

# 1. Verifier/installer uv (fournit uvx)
$uvx = Get-Command uvx -ErrorAction SilentlyContinue
if (-not $uvx) {
    Write-Host "uvx non trouve, installation de uv..."
    irm https://astral.sh/uv/install.ps1 | iex
    $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
    $uvx = Get-Command uvx -ErrorAction SilentlyContinue
    if (-not $uvx) {
        Write-Host "Erreur : uvx introuvable apres installation. Redemarre le terminal et relance ce script."
        exit 1
    }
}
$uvxPath = $uvx.Source
Write-Host "uvx trouve : $uvxPath"
Write-Host ""

# 2. Demander les identifiants Odoo
$odooUrl = Read-Host "URL Odoo (ex: https://nalios.odoo.com)"
$odooDb = Read-Host "Nom de la base de donnees"
$odooUser = Read-Host "Email / utilisateur Odoo"
$odooApiKeySecure = Read-Host "Cle API Odoo" -AsSecureString
$odooApiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($odooApiKeySecure))
Write-Host ""

function Update-McpConfig {
    param(
        [string]$ConfigPath,
        [bool]$IncludeType,
        [string]$Label
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
        ODOO_URL               = $odooUrl
        ODOO_DB                = $odooDb
        ODOO_USER              = $odooUser
        ODOO_API_KEY           = $odooApiKey
        ODOO_YOLO              = "true"
        ODOO_MCP_DEFAULT_LIMIT = "100"
        ODOO_MCP_MAX_LIMIT     = "1000"
    }

    if ($IncludeType) {
        $odooEntry = [PSCustomObject]@{
            type    = "stdio"
            command = $uvxPath
            args    = @("mcp-server-odoo@0.4.0")
            env     = $envBlock
        }
    } else {
        $odooEntry = [PSCustomObject]@{
            command = $uvxPath
            args    = @("mcp-server-odoo@0.4.0")
            env     = $envBlock
        }
    }

    if ($config.mcpServers.PSObject.Properties.Name.Contains("odoo")) {
        $config.mcpServers.odoo = $odooEntry
    } else {
        $config.mcpServers | Add-Member -MemberType NoteProperty -Name odoo -Value $odooEntry
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
    Write-Host "$Label mis a jour : $ConfigPath"
}

# Claude Desktop
$desktopConfig = "$env:APPDATA\Claude\claude_desktop_config.json"
if (Test-Path "$env:APPDATA\Claude") {
    Update-McpConfig -ConfigPath $desktopConfig -IncludeType $false -Label "Claude Desktop"
} else {
    Write-Host "Claude Desktop non detecte ($desktopConfig) - etape ignoree."
}

# Claude Code (config utilisateur globale)
$claudeCodeConfig = "$env:USERPROFILE\.claude.json"
if (Test-Path $claudeCodeConfig) {
    Update-McpConfig -ConfigPath $claudeCodeConfig -IncludeType $true -Label "Claude Code"
} else {
    Write-Host "Config Claude Code non trouvee ($claudeCodeConfig) - etape ignoree."
}

Write-Host ""
Write-Host "=== Termine ==="
Write-Host "Redemarre Claude Desktop et Claude Code pour activer le serveur MCP 'odoo'."
