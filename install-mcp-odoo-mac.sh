#!/bin/bash
# Installation du serveur MCP Odoo (mcp-server-odoo) pour Claude Desktop et Claude Code
# Edite directement les fichiers de config JSON (pas besoin de la CLI `claude`)
set -euo pipefail

echo "=== Installation MCP Server Odoo ==="
echo ""

# 1. Verifier/installer uv (fournit uvx)
if ! command -v uvx &>/dev/null; then
    echo "uvx non trouve, installation de uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi
UVX_PATH=$(command -v uvx)
echo "uvx trouve : $UVX_PATH"
echo ""

# 2. Demander les identifiants Odoo
echo "Pour info :"
echo "  - URL Odoo : l'adresse de votre instance (ex: https://nalios.odoo.com)"
echo "  - Base de donnees : visible dans le selecteur de base au login, ou dans l'URL"
echo "  - Email / utilisateur : votre identifiant de connexion Odoo"
echo "  - Cle API : Odoo > votre profil (en haut a droite) > Compte > Securite du compte > Nouvelle cle API"
echo ""
read -rp "Nom du serveur MCP (ex: odoo) [odoo] : " MCP_NAME </dev/tty
MCP_NAME="${MCP_NAME:-odoo}"
read -rp "URL Odoo (ex: https://nalios.odoo.com) : " ODOO_URL </dev/tty
read -rp "Nom de la base de donnees : " ODOO_DB </dev/tty
read -rp "Email / utilisateur Odoo : " ODOO_USER </dev/tty
read -rsp "Cle API Odoo : " ODOO_API_KEY </dev/tty
echo ""
echo ""

# 3. Mettre a jour les fichiers de config (Claude Desktop + Claude Code)
update_config() {
    local config_path="$1"
    local include_type="$2"
    local label="$3"

    mkdir -p "$(dirname "$config_path")"
    if [ ! -f "$config_path" ]; then
        echo "{}" > "$config_path"
    fi

    python3 - "$config_path" "$UVX_PATH" "$ODOO_URL" "$ODOO_DB" "$ODOO_USER" "$ODOO_API_KEY" "$include_type" "$label" "$MCP_NAME" <<'EOF'
import json, sys

config_path, uvx_path, url, db, user, api_key, include_type, label, mcp_name = sys.argv[1:10]

with open(config_path) as f:
    config = json.load(f)

config.setdefault("mcpServers", {})

entry = {
    "command": uvx_path,
    "args": ["mcp-server-odoo@0.4.0"],
    "env": {
        "ODOO_URL": url,
        "ODOO_DB": db,
        "ODOO_USER": user,
        "ODOO_API_KEY": api_key,
        "ODOO_YOLO": "true",
        "ODOO_MCP_DEFAULT_LIMIT": "100",
        "ODOO_MCP_MAX_LIMIT": "1000",
    },
}
if include_type == "1":
    entry = {"type": "stdio", **entry}

config["mcpServers"][mcp_name] = entry

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

print(f"{label} mis a jour : {config_path}")
EOF
}

# Claude Desktop
DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
if [ -d "$HOME/Library/Application Support/Claude" ]; then
    update_config "$DESKTOP_CONFIG" "0" "Claude Desktop"
else
    echo "Claude Desktop non detecte ($DESKTOP_CONFIG) - etape ignoree."
fi

# Claude Code (config utilisateur globale)
CLAUDE_CODE_CONFIG="$HOME/.claude.json"
if [ -f "$CLAUDE_CODE_CONFIG" ]; then
    update_config "$CLAUDE_CODE_CONFIG" "1" "Claude Code"
else
    echo "Config Claude Code non trouvee ($CLAUDE_CODE_CONFIG) - etape ignoree."
fi

echo ""
echo "=== Termine ==="
echo "Redemarre Claude Desktop et Claude Code pour activer le serveur MCP '$MCP_NAME'."
