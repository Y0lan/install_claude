# install_claude

Installe un environnement de dev complet dans **WSL2 Ubuntu 22.04** :
Claude Code, Codex, Bun, Node, Chrome, zsh, tmux, des alias utiles et les skills Claude.

Le setup repart volontairement sur un **Ubuntu 22.04 propre**. Les autres Ubuntu WSL sont supprimés, car seule la version 22.04 est supportée ici.

## Résultat attendu

À la fin, vous aurez :

- un raccourci Bureau `Ubuntu-22.04 (zsh).lnk`
- un raccourci Bureau `Claude Code (auto).lnk`
- un terminal WSL propre, en `zsh`, ouvert dans `~`
- Claude Code prêt à connecter manuellement, sans ouverture automatique du navigateur WSL
- Claude Code, Codex, `gstack`, Superpowers et `claude-mem` prêts à l’emploi

## 1. Ouvrir PowerShell en administrateur

Ouvrez **PowerShell en tant qu’administrateur**.

Important : ne lancez pas ces commandes dans WSL.

## 2. Installer proprement

Cette commande supprime les distributions Ubuntu WSL existantes, puis recrée un `Ubuntu-22.04` propre.

Attention : tous les fichiers Linux dans les Ubuntu WSL supprimés seront perdus.

```powershell
Remove-Item -Recurse -Force "$env:TEMP\install_claude" -ErrorAction SilentlyContinue; git clone https://github.com/Y0lan/install_claude "$env:TEMP\install_claude"; cd "$env:TEMP\install_claude"; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1 -CleanInstall
```

Si le script détecte un Ubuntu WSL existant, il demandera confirmation :

- **Entrée** : supprime Ubuntu et repart de zéro
- `KEEP` : garde Ubuntu et ajoute ce qui manque

## 3. Si le script demande un redémarrage

Si le script active WSL et demande de redémarrer :

1. Redémarrez Windows.
2. Rouvrez **PowerShell en administrateur**.
3. Lancez la reprise :

```powershell
cd "$env:TEMP\install_claude"; git pull; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

Quand le script redétecte Ubuntu après le reboot, tapez `KEEP` si vous voulez continuer l’installation déjà commencée. Appuyez sur Entrée uniquement si vous voulez vraiment repartir de zéro.

## 4. Si l’installation échoue au milieu

Relancez simplement :

```powershell
cd "$env:TEMP\install_claude"; git pull; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

Quand le script demande quoi faire avec Ubuntu, tapez `KEEP` pour reprendre sans supprimer. Appuyez sur Entrée pour tout effacer et recommencer proprement.

Si `git pull` refuse à cause de changements locaux dans le dossier temporaire :

```powershell
cd "$env:TEMP\install_claude"; git fetch origin; git reset --hard origin/main; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

## 5. Répondre aux questions pendant l’installation

Vous pouvez voir quelques prompts :

- `gstack` : appuyez sur Entrée, le choix par défaut est OK.
- `claude-mem` : choisissez `Claude Code` et `Codex` pour le harness, puis `Claude Code` pour le provider.

Le script ne lance plus automatiquement le login Claude, parce que l’ouverture d’un navigateur Linux/WSLg depuis WSL peut freezer certains PC Windows.

## 6. Utiliser l’environnement

Après l’installation :

- ouvrez `Ubuntu-22.04 (zsh).lnk` pour un terminal WSL normal
- lancez `claude-login`
- ouvrez l’URL affichée dans votre navigateur Windows
- si Claude affiche un prompt de login, appuyez sur `c` pour copier l’URL, puis ouvrez-la dans le navigateur Windows
- après connexion, ouvrez `Claude Code (auto).lnk` pour lancer Claude en mode auto
- si Claude était déjà ouvert, fermez-le puis rouvrez-le pour voir les nouveaux skills

Dans Claude, vérifiez les skills avec :

```text
/skills
```

### Finaliser les skills Karpathy et Matt Pocock

Le script installe `gstack`, Superpowers et tente de préparer les autres skills. Pour Karpathy et Matt Pocock, le plus fiable est de finir avec les commandes officielles après le premier login Claude.

Dans Claude Code, collez :

```text
/plugin marketplace add forrestchang/andrej-karpathy-skills
/plugin install andrej-karpathy-skills@karpathy-skills
```

Dans le terminal WSL, collez :

```bash
npx skills@latest add mattpocock/skills
```

Choisissez les skills voulus et vérifiez que `/setup-matt-pocock-skills` est sélectionné. Ensuite lancez cette commande **dans le repo du projet à configurer** :

```text
/setup-matt-pocock-skills
```

Cette dernière étape configure le repo courant (`AGENTS.md` ou `CLAUDE.md`, tracker, labels, docs). Il faut donc la lancer une fois par projet.

## 7. Ce qu’il faut savoir sur les skills

Le setup installe automatiquement :

- `claude-mem`
- `gstack`
- Superpowers

À finaliser après login :

- Karpathy skills : commandes `/plugin marketplace add ...` puis `/plugin install ...`
- Matt Pocock skills : `npx skills@latest add mattpocock/skills`, puis `/setup-matt-pocock-skills` par repo

Connectez-vous à **Claude Code** et à **Codex**. Les deux doivent être authentifiés pour travailler ensemble correctement.

Exemple d’usage utile dans Claude :

```text
Challenge ton plan avec Codex avant de modifier le code.
```

Autres repères :

- `claude-mem` garde du contexte/mémoire entre les sessions.
- Karpathy apporte des règles de raisonnement et de travail plus strictes pour Claude Code.
- `gstack` ajoute des workflows orientés agent et setup de skills.
- Matt Pocock ajoute des skills de dev TypeScript/PRD/issues/diagnostic. Lancez `/setup-matt-pocock-skills` dans chaque repo où vous voulez les utiliser.
- Superpowers ajoute des commandes et habitudes de travail Claude Code.

## 8. Vérifier rapidement

Dans le terminal WSL, collez :

```bash
echo "--- versions ---"; node --version; bun --version; google-chrome --version | head -1; claude --version; codex --version; echo "--- skills visibles ---"; find ~/.claude/skills -mindepth 2 -maxdepth 2 -name SKILL.md -printf '%h\n' | xargs -r -n1 basename | sort; echo "--- shell ---"; echo "$SHELL"
```

Vous devez voir des versions pour Node, Bun, Chrome, Claude et Codex, puis au minimum :

```text
gstack
using-superpowers
```

Après les commandes de finalisation, vous devriez aussi voir `karpathy-guidelines` et `setup-matt-pocock-skills`.

## Alias utiles

Les alias principaux dans zsh :

```bash
c       # codex
cx      # efface l’écran puis lance claude --permission-mode bypassPermissions
claude-login # login Claude sans ouvrir automatiquement Chrome Linux/WSLg
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
- skills Claude : gstack et Superpowers automatiques; Karpathy et Matt Pocock à finaliser après login
- FiraCode Nerd Font Mono
- profil Windows Terminal et raccourcis Bureau

## Fichiers du dépôt

- `bootstrap.ps1` : script Windows à lancer en PowerShell admin
- `install.sh` : script Linux lancé dans WSL, relançable avec `bash ~/install.sh`
