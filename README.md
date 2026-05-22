# install_claude

Guide d’installation complet pour préparer un environnement de dev dans **WSL2 Ubuntu 22.04** avec Claude Code, Codex, Bun, Node, zsh, tmux, `gstack`, Superpowers, `claude-mem` et les alias utiles.

Ce guide est volontairement strict : on repart sur un **Ubuntu 22.04 propre**, parce que c’est la version supportée par ce setup.

## Avant de commencer

À savoir :

- lancez les commandes Windows dans **PowerShell administrateur**
- ne lancez pas ces commandes depuis WSL
- l’installation peut prendre 10 à 30 minutes
- si un Ubuntu WSL existe déjà, **Entrée le supprime**
- tapez `KEEP` seulement si vous voulez reprendre une installation existante

Attention : supprimer Ubuntu WSL efface tous les fichiers Linux de cette distribution.

## Résultat final

À la fin, vous aurez :

- `Ubuntu-22.04` dans WSL2
- un utilisateur Linux avec `sudo` sans mot de passe
- un raccourci Bureau `Ubuntu-22.04 (zsh).lnk`
- un raccourci Bureau `Claude Code (auto).lnk`
- Claude Code, Codex, Bun, Node, Chrome, zsh, tmux, eza, fzf, ripgrep, bat
- `claude-mem`, `gstack` et Superpowers installés
- Karpathy et Matt Pocock à finaliser avec quelques commandes après le login Claude

## Étape 1 - Ouvrir PowerShell admin

Ouvrez le menu Démarrer, cherchez **PowerShell**, puis choisissez **Exécuter en tant qu’administrateur**.

Vous devez voir une fenêtre PowerShell avec des droits admin.

## Étape 2 - Lancer l’installation propre

Collez toute cette commande dans PowerShell admin :

```powershell
Remove-Item -Recurse -Force "$env:TEMP\install_claude" -ErrorAction SilentlyContinue; git clone https://github.com/Y0lan/install_claude "$env:TEMP\install_claude"; cd "$env:TEMP\install_claude"; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1 -CleanInstall
```

Si le script détecte un Ubuntu WSL existant, il demande :

```text
Delete existing Ubuntu WSL distro(s)? [DELETE/keep] (default: DELETE)
```

Répondez :

- **Entrée** pour supprimer Ubuntu et repartir proprement
- `KEEP` pour garder Ubuntu et reprendre/compléter l’installation

Pour une installation normale chez un dev, appuyez sur **Entrée**.

## Étape 3 - Répondre aux prompts

Pendant l’installation, vous pouvez voir quelques questions.

Pour `gstack` :

```text
Appuyez sur Entrée.
```

Le choix par défaut est OK.

Pour `claude-mem` :

```text
Harness: choisissez Claude Code et Codex
Provider: choisissez Claude Code
```

Le script ne lance pas automatiquement le login Claude. C’est volontaire : ouvrir Chrome Linux/WSLg depuis WSL peut freezer certains PC Windows.

## Étape 4 - Si Windows demande un redémarrage

Si le script dit qu’un reboot est nécessaire :

1. Redémarrez Windows.
2. Rouvrez PowerShell en administrateur.
3. Collez :

```powershell
cd "$env:TEMP\install_claude"; git pull; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

Quand Ubuntu est redétecté, tapez :

```text
KEEP
```

Ne pressez pas Entrée à ce moment-là, sinon Ubuntu sera supprimé et l’installation recommencera.

## Étape 5 - Si l’installation s’arrête ou échoue

Relancez simplement :

```powershell
cd "$env:TEMP\install_claude"; git pull; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

Quand Ubuntu est redétecté :

- tapez `KEEP` pour reprendre
- appuyez sur Entrée uniquement si vous voulez tout supprimer et recommencer

Si `git pull` refuse à cause de changements locaux :

```powershell
cd "$env:TEMP\install_claude"; git fetch origin; git reset --hard origin/main; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

## Étape 6 - Se connecter à Claude Code

Ouvrez le raccourci Bureau :

```text
Ubuntu-22.04 (zsh).lnk
```

Dans le terminal WSL, lancez :

```bash
claude-login
```

Le terminal affiche une URL et essaie de la copier dans le presse-papiers Windows.

Ouvrez cette URL dans votre navigateur Windows normal.

Si Claude affiche un prompt de login dans le terminal, appuyez sur :

```text
c
```

Puis ouvrez l’URL copiée dans le navigateur Windows.

## Étape 7 - Se connecter à Codex

Dans le terminal WSL, lancez :

```bash
codex
```

Suivez le login demandé par Codex.

Claude et Codex doivent tous les deux être connectés si vous voulez les faire travailler ensemble.

## Étape 8 - Finaliser les skills Karpathy

Après le login Claude, ouvrez Claude Code et collez :

```text
/plugin marketplace add forrestchang/andrej-karpathy-skills
/plugin install andrej-karpathy-skills@karpathy-skills
```

Ces commandes installent les guidelines Karpathy via le plugin Claude Code officiel du repo.

## Étape 9 - Finaliser les skills Matt Pocock

Dans le terminal WSL, collez :

```bash
npx skills@latest add mattpocock/skills
```

Pendant le choix des skills, vérifiez que `setup-matt-pocock-skills` est sélectionné.

Ensuite, dans Claude Code, lancez cette commande **dans chaque repo de projet à configurer** :

```text
/setup-matt-pocock-skills
```

Cette étape configure le repo courant : `AGENTS.md` ou `CLAUDE.md`, tracker, labels, docs. Il faut donc la refaire une fois par projet.

## Étape 10 - Vérifier que tout marche

Dans le terminal WSL, collez :

```bash
echo "--- versions ---"; node --version; bun --version; google-chrome --version | head -1; claude --version; codex --version; echo "--- skills visibles ---"; find ~/.claude/skills -mindepth 2 -maxdepth 2 -name SKILL.md -printf '%h\n' | xargs -r -n1 basename | sort; echo "--- shell ---"; echo "$SHELL"
```

Vous devez voir :

- une version Node
- une version Bun
- une version Chrome
- une version Claude
- une version Codex
- `gstack`
- `using-superpowers`

Après les étapes Karpathy et Matt Pocock, vous devriez aussi voir :

- `karpathy-guidelines`
- `setup-matt-pocock-skills`

## Étape 11 - Utiliser Claude en mode auto

Une fois Claude connecté, ouvrez le raccourci Bureau :

```text
Claude Code (auto).lnk
```

Ce raccourci lance :

```bash
claude --permission-mode bypassPermissions
```

Le raccourci Ubuntu normal ne lance pas Claude. Il ouvre seulement WSL en zsh.

## Commandes utiles

Dans WSL :

```bash
c              # codex
cx             # clear + claude --permission-mode bypassPermissions
claude-login   # login Claude sans ouvrir Chrome Linux/WSLg
t              # tmux attach || tmux new -s Work
ic             # tmux layout avec codex
ix             # tmux layout avec cx
icx            # tmux layout avec codex + cx

l              # eza --icons=auto
ls             # eza -lh --group-directories-first --icons=auto
ll             # eza -lh --group-directories-first --icons=auto
la             # eza -lha --group-directories-first --icons=auto

g              # git
gst            # git status
gco            # git checkout
gp             # git pull
gP             # git push
gcm            # git commit -m
gcam           # git commit -a -m
glog           # git log --oneline --graph --decorate -20

..             # cd ..
...            # cd ../..
reload         # source ~/.bashrc
please         # relance la dernière commande avec sudo
path           # affiche PATH ligne par ligne
```

## Skills installés

Installés automatiquement :

- `claude-mem`
- `gstack`
- Superpowers

À finaliser après login :

- Karpathy : `/plugin marketplace add ...` puis `/plugin install ...`
- Matt Pocock : `npx skills@latest add mattpocock/skills`, puis `/setup-matt-pocock-skills`

Repères :

- `claude-mem` garde du contexte/mémoire entre les sessions.
- Karpathy ajoute des règles plus strictes de raisonnement et de simplicité.
- `gstack` ajoute des workflows orientés agent.
- Matt Pocock ajoute des skills de dev TypeScript/PRD/issues/diagnostic.
- Superpowers ajoute des commandes et habitudes de travail Claude Code.

Exemple utile à demander à Claude :

```text
Challenge ton plan avec Codex avant de modifier le code.
```

## Dépannage

### Le terminal affiche encore “First launch - opening Claude Code”

Relancez le setup en gardant Ubuntu :

```powershell
cd "$env:TEMP\install_claude"; git pull; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

Quand il demande quoi faire avec Ubuntu, tapez :

```text
KEEP
```

### Le login Claude freeze Windows

N’ouvrez pas Chrome Linux depuis WSL.

Utilisez :

```bash
claude-login
```

Puis ouvrez l’URL dans le navigateur Windows.

### Je veux repartir de zéro

Relancez la commande d’installation propre de l’étape 2 et appuyez sur Entrée quand Ubuntu est détecté.

### J’ai déjà un Ubuntu avec des fichiers importants

Tapez `KEEP` quand le script demande quoi faire avec Ubuntu.

Mais pour l’installation standard de l’équipe, le chemin recommandé reste Ubuntu 22.04 propre.

## Détails techniques

Le script installe :

- WSL2 Ubuntu 22.04
- systemd dans WSL
- sudo sans mot de passe pour l’utilisateur Linux
- zsh, oh-my-zsh, Pure prompt
- tmux, fzf, ripgrep, fd, bat, eza
- Node LTS, Bun, Google Chrome
- Claude Code, OpenAI Codex CLI, claude-mem
- FiraCode Nerd Font Mono
- profil Windows Terminal et raccourcis Bureau

Fichiers du dépôt :

- `bootstrap.ps1` : script Windows lancé en PowerShell admin
- `install.sh` : script Linux lancé dans WSL, relançable avec `bash ~/install.sh`
