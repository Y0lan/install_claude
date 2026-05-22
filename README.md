# install_claude

Installe **WSL2 Ubuntu 22.04** avec Claude Code, Codex, Bun, Node, zsh, tmux, et les skills (`gstack`, `claude-mem`, Superpowers, Matt Pocock, Karpathy).

> Tout se lance depuis **PowerShell administrateur**, pas depuis WSL.
> Si un Ubuntu WSL existe déjà, il sera **supprimé** (sauf si vous tapez `KEEP`).

## 1. Installer

PowerShell admin :

```powershell
Remove-Item -Recurse -Force "$env:TEMP\install_claude" -ErrorAction SilentlyContinue; git clone https://github.com/Y0lan/install_claude "$env:TEMP\install_claude"; cd "$env:TEMP\install_claude"; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1 -CleanInstall
```

Pendant l’install :
- `gstack` / Matt Pocock → laissez les défauts (Entrée)
- `claude-mem` → cochez **Claude Code + Codex CLI**, puis choisissez **Claude Code** pour la suite
- si Windows demande un reboot, redémarrez puis relancez (voir §4)

## 2. Se connecter

Ouvrez le raccourci Bureau **`Ubuntu-22.04 (zsh).lnk`**, puis :

```bash
claude-login   # copie l’URL, ouvrez-la dans votre navigateur Windows
codex          # login Codex
```

## 3. Finaliser les skills

Dans Claude Code :

```text
/plugin marketplace add forrestchang/andrej-karpathy-skills
/plugin install andrej-karpathy-skills@karpathy-skills
```

Dans **chaque repo** où vous voulez Matt Pocock :

```text
/setup-matt-pocock-skills
```

## 4. Relancer si ça plante

```powershell
cd "$env:TEMP\install_claude"; git pull; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

Quand Ubuntu est redétecté → tapez **`KEEP`** (Entrée = tout supprimer).

Si `git pull` refuse :

```powershell
git fetch origin; git reset --hard origin/main
```

## Utiliser Claude

- **`Claude Code (auto).lnk`** → Claude en `bypassPermissions`
- **`Ubuntu-22.04 (zsh).lnk`** → terminal WSL seul

Alias utiles dans WSL : `c` (codex), `cx` (claude auto), `claude-login`, `t` (tmux), `gst` / `gp` / `gP` (git).

## Notes

- `claude-mem` = mémoire entre sessions
- `gstack` = workflows agent (`/ship`, `/review`, `/browse`…)
- Superpowers = habitudes Claude Code
- Karpathy = règles strictes de raisonnement
- Matt Pocock = TS / PRD / issues
- Claude **et** Codex doivent être loggés pour qu’ils collaborent.
