# install_claude

Installe un environnement de dev complet dans **WSL2 Ubuntu 22.04** :
Claude Code, Codex, Bun, Node, Chrome, zsh, tmux, des alias utiles et les skills Claude.

Le setup repart volontairement sur un **Ubuntu 22.04 propre**. Les autres Ubuntu WSL sont supprimés, car seule la version 22.04 est supportée ici.

## Résultat attendu

À la fin, vous aurez :

- un raccourci Bureau `Ubuntu-22.04 (zsh).lnk`
- un raccourci Bureau `Claude Code (auto).lnk`
- un terminal WSL propre, en `zsh`, ouvert dans `~`
- Claude Code qui se lance pour la connexion OAuth
- Claude Code, Codex et les skills prêts à l’emploi

## 1. Ouvrir PowerShell en administrateur

Ouvrez **PowerShell en tant qu’administrateur**.

Important : ne lancez pas ces commandes dans WSL.

## 2. Installer proprement

Cette commande supprime les distributions Ubuntu WSL existantes, puis recrée un `Ubuntu-22.04` propre.

Attention : tous les fichiers Linux dans les Ubuntu WSL supprimés seront perdus.

```powershell
Remove-Item -Recurse -Force "$env:TEMP\install_claude" -ErrorAction SilentlyContinue; git clone https://github.com/Y0lan/install_claude "$env:TEMP\install_claude"; cd "$env:TEMP\install_claude"; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1 -CleanInstall
```

## 3. Si le script demande un redémarrage

Si le script active WSL et demande de redémarrer :

1. Redémarrez Windows.
2. Rouvrez **PowerShell en administrateur**.
3. Lancez la reprise :

```powershell
cd "$env:TEMP\install_claude"; git pull; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

Ne relancez pas `-CleanInstall` après le reboot, sinon Ubuntu sera supprimé une deuxième fois.

## 4. Si l’installation échoue au milieu

Relancez simplement :

```powershell
cd "$env:TEMP\install_claude"; git pull; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

Si `git pull` refuse à cause de changements locaux dans le dossier temporaire :

```powershell
cd "$env:TEMP\install_claude"; git fetch origin; git reset --hard origin/main; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

## 5. Répondre aux questions pendant l’installation

Vous pouvez voir quelques prompts :

- `gstack` : appuyez sur Entrée, le choix par défaut est OK.
- `claude-mem` : choisissez `Claude Code` et `Codex` pour le harness, puis `Claude Code` pour le provider.
- OAuth Claude : connectez-vous dans le navigateur quand Claude s’ouvre.

## 6. Utiliser l’environnement

Après l’installation :

- ouvrez `Claude Code (auto).lnk` pour lancer Claude en mode auto
- ouvrez `Ubuntu-22.04 (zsh).lnk` pour un terminal WSL normal
- si Claude était déjà ouvert, fermez-le puis rouvrez-le pour voir les nouveaux skills

Dans Claude, vérifiez les skills avec :

```text
/skills
```

Pour les skills Matt Pocock, lancez ensuite cette commande **dans le repo du projet à configurer** :

```text
/setup-matt-pocock-skills
```

Cette étape vient du quickstart officiel de `mattpocock/skills`. Elle n’est pas lancée automatiquement parce qu’elle configure le repo courant (`AGENTS.md` ou `CLAUDE.md`, tracker, labels, docs). Il faut donc la lancer une fois par projet.

## 7. Vérifier rapidement

Dans le terminal WSL, collez :

```bash
echo "--- versions ---"; node --version; bun --version; google-chrome --version | head -1; claude --version; codex --version; echo "--- skills visibles ---"; find ~/.claude/skills -mindepth 2 -maxdepth 2 -name SKILL.md -printf '%h\n' | xargs -r -n1 basename | sort; echo "--- shell ---"; echo "$SHELL"
```

Vous devez voir des versions pour Node, Bun, Chrome, Claude et Codex, puis des skills comme :

```text
gstack
karpathy-guidelines
setup-matt-pocock-skills
using-superpowers
```

## Alias utiles

Les alias principaux dans zsh :

```bash
c       # codex
cx      # efface l’écran puis lance claude --permission-mode bypassPermissions
t       # tmux attach || tmux new -s Work
ic      # layout tmux avec codex
ix      # layout tmux avec cx
icx     # layout tmux avec codex + cx

l       # eza --icons=auto
ls      # eza -lh --group-directories-first --icons=auto
ll      # eza -lh --group-directories-first --icons=auto
la      # eza -lha --group-directories-first --icons=auto

g       # git
gst     # git status
gco     # git checkout
gp      # git pull
gP      # git push
gcm     # git commit -m
gcam    # git commit -a -m
glog    # git log --oneline --graph --decorate -20

..      # cd ..
...     # cd ../..
reload  # recharge ~/.bashrc
please  # relance la dernière commande avec sudo
path    # affiche PATH ligne par ligne
```

## Ce qui est installé

- WSL2 Ubuntu 22.04
- sudo sans mot de passe pour l’utilisateur Linux
- systemd dans WSL
- zsh, oh-my-zsh, Pure prompt, tmux, fzf, ripgrep, fd, bat, eza
- Node LTS, Bun, Google Chrome
- Claude Code, OpenAI Codex CLI, claude-mem
- skills Claude : gstack, Karpathy, Superpowers, Matt Pocock
- FiraCode Nerd Font Mono
- profil Windows Terminal et raccourcis Bureau

## Fichiers du dépôt

- `bootstrap.ps1` : script Windows à lancer en PowerShell admin
- `install.sh` : script Linux lancé dans WSL, relançable avec `bash ~/install.sh`
