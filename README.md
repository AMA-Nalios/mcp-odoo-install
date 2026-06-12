# Installation MCP Server Odoo

Scripts d'installation du serveur MCP `mcp-server-odoo` pour Claude Desktop et Claude Code.

## Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/AMA-Nalios/mcp-odoo-install/main/install-mcp-odoo-windows.ps1 | iex
```

## Mac

```bash
curl -LsSf https://raw.githubusercontent.com/AMA-Nalios/mcp-odoo-install/main/install-mcp-odoo-mac.sh | bash
```

## Ce que fait le script

- Installe `uv`/`uvx` si nécessaire
- Demande l'URL Odoo, la base de données, l'utilisateur et la clé API
- Configure le serveur MCP `odoo` dans Claude Desktop et Claude Code

Après l'installation, redémarrer Claude Desktop et Claude Code.
