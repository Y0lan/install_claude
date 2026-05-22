# install_claude

Installe **WSL2 Ubuntu 22.04** avec Claude Code, Codex, Bun, Node, zsh, tmux, et les skills (`gstack`, `claude-mem`, Superpowers, Matt Pocock, Karpathy).

> Tout se lance depuis **PowerShell administrateur**, pas depuis WSL.
> Si un Ubuntu WSL existe déjà, il sera **supprimé** (sauf si vous tapez `KEEP`).

## 1. Installer

PowerShell admin :

```powershell
Remove-Item -Recurse -Force "$env:TEMP\install_claude" -ErrorAction SilentlyContinue; git clone https://github.com/Y0lan/install_claude "$env:TEMP\install_claude"; cd "$env:TEMP\install_claude"; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1 -CleanInstall
```

Pendant l’install, répondez exactement ceci aux prompts :

**`gstack`** → Entrée (défauts).

**`claude-mem`** (dans l’ordre) :
1. IDE → cochez **Claude Code** + **Codex CLI**
2. Worker → **Claude Agent SDK**
3. Plan → **Subscription Plan**
4. Modèle → **Haiku 4.5**

**Matt Pocock (`SKILLS`)** :
1. Skills → **tout cocher** (`Espace` sur chaque, puis `Entrée`)
2. Tapez `claude`, sélectionnez **Claude**, `Entrée`
3. **Global**, `Entrée`
4. **Symlink**, `Entrée`
5. Laissez l’install se terminer

**`find-skills`** → **Yes**.

Si Windows demande un reboot, redémarrez puis relancez (voir §4).

## 2. Se connecter

Dans le terminal WSL qui s’ouvre à la fin de l’install (ou via **`Ubuntu-22.04 (zsh).lnk`**) :

```bash
cx
```

Puis :
1. `Entrée`, `Entrée`
2. Tapez `c` (login navigateur)
3. Copiez l’URL → ouvrez-la dans **Chrome Windows** → collez l’URL
4. Récupérez le code de Claude et collez-le dans le terminal

C’est fini ! Pensez aussi à `codex` une fois pour logger Codex.

## 3. Finaliser les skills

Dans Claude Code, lancez les deux commandes Karpathy **une à la fois** (attendez la fin de la première avant la seconde).

D’abord, ajoutez la marketplace :

```text
/plugin marketplace add forrestchang/andrej-karpathy-skills
```

Puis installez le plugin :

```text
/plugin install andrej-karpathy-skills@karpathy-skills
```

Ensuite, dans **chaque repo** où vous voulez Matt Pocock :

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

**Lancez toujours Claude depuis WSL avec `cx`** — pas via un raccourci Windows.

```bash
cx
```

`cx` = `claude --permission-mode bypassPermissions` dans le terminal WSL. C’est la seule façon fiable d’avoir le bon environnement (Node, Bun, `claude-mem`, skills…).

Autres alias WSL : `c` (codex), `claude-login`, `t` (tmux), `gst` / `gp` / `gP` (git).

## Notes

- `claude-mem` = mémoire entre sessions — UI dispo sur <http://localhost:37700>
- `gstack` = workflows agent (`/ship`, `/review`, `/browse`…)
- Superpowers = habitudes Claude Code
- Karpathy = règles strictes de raisonnement
- Matt Pocock = TS / PRD / issues
- Claude **et** Codex doivent être loggés pour qu’ils collaborent.

---

🚀 **Vos launchers sont sur le Bureau Windows !**
- **`Ubuntu-22.04 (zsh).lnk`** → terminal WSL (lancez `cx` dedans)
- **`Claude Code (auto).lnk`** → Claude direct en mode auto
