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

## Installation manuelle (Windows)

Si le script automatique ne fonctionne pas, voici les étapes manuelles.

### 1. Installer uv

Dans PowerShell (pas cmd) :

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

La commande affiche le chemin d'installation, par exemple :
`C:\Users\TonNom\.local\bin`

### 2. Ajouter uv au PATH

Copie-colle le chemin affiché dans la commande suivante (remplace le chemin) :

```powershell
$env:PATH = "C:\Users\TonNom\.local\bin;$env:PATH"
```

### 3. Installer Python 3.12

```powershell
uv python install 3.12
```

### 4. Configurer le MCP manuellement

Ouvre le fichier de config Claude Desktop :
`C:\Users\TonNom\AppData\Roaming\Claude\claude_desktop_config.json`

Ajoute le bloc suivant dans la section `mcpServers` (en remplaçant les valeurs) :

```json
"mcpServers": {
  "nalios": {
    "command": "C:\\Users\\TonNom\\.local\\bin\\uvx.exe",
    "args": [
      "mcp-server-odoo@0.4.0"
    ],
    "env": {
      "ODOO_URL": "https://ton-instance.odoo.com",
      "ODOO_DB": "nom-de-la-base",
      "ODOO_USER": "ton@email.com",
      "ODOO_API_KEY": "ta_cle_api",
      "ODOO_YOLO": "true",
      "ODOO_MCP_DEFAULT_LIMIT": "100",
      "ODOO_MCP_MAX_LIMIT": "1000"
    }
  }
}
```

> Le chemin vers `uvx.exe` est celui affiché à l'étape 1, avec `\uvx.exe` ajouté à la fin. Les backslashes doivent être doublés (`\\`) dans le JSON.

---

## Ce que fait le script

- Installe `uv`/`uvx` si nécessaire
- Demande l'URL Odoo, la base de données, l'utilisateur et la clé API
- Configure le serveur MCP dans Claude Desktop et Claude Code

Après l'installation, redémarrer Claude Desktop et Claude Code.
