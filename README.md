# Installation MCP Server Odoo

Scripts d'installation du serveur MCP `mcp-server-odoo` pour Claude Desktop et Claude Code.

## Windows

1. Appuie sur `Win` + `R`, tape `powershell`, puis `Entrée`
2. Colle cette commande dans la fenêtre PowerShell (pas dans cmd !) :

```powershell
irm https://raw.githubusercontent.com/AMA-Nalios/mcp-odoo-install/main/install-mcp-odoo-windows.ps1 | iex
```

> **Important :** ne pas télécharger et double-cliquer le fichier `.ps1` — coller la commande dans PowerShell comme indiqué ci-dessus.

## Mac

Ouvre un Terminal et colle :

```bash
curl -LsSf https://raw.githubusercontent.com/AMA-Nalios/mcp-odoo-install/main/install-mcp-odoo-mac.sh | bash
```

## Ce que fait le script

- Installe `uv`/`uvx` si nécessaire
- Demande l'URL Odoo, la base de données, l'utilisateur et la clé API
- Configure le serveur MCP dans Claude Desktop et Claude Code

Après l'installation, redémarrer Claude Desktop et Claude Code.
