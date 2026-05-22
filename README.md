# install_claude

One-shot bootstrap for a clean **WSL2 Ubuntu 22.04** dev box with Claude Code, OpenAI Codex CLI, gstack, Bun, Node, Google Chrome, zsh + Pure prompt, FiraCode Nerd Font, and the karpathy / superpowers / matt-pocock / claude-mem skill packs.

End state: open a Desktop shortcut -> lands in `~` in `zsh` -> Claude Code opens for OAuth automatically.

## Run it

Open an **Administrator PowerShell** window, then paste one of these.

### First time (or after a fresh re-clone)

```powershell
git clone https://github.com/Y0lan/install_claude "$env:TEMP\install_claude"; cd "$env:TEMP\install_claude"; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

### Re-run after a reboot, a fix, or any partial install

Pulls the latest version of the scripts and re-runs from the existing clone. Every step is idempotent, so this picks up cleanly from wherever the previous run stopped:

```powershell
cd "$env:TEMP\install_claude"; git pull; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

### Force-update and try again

Use this if a previous run failed and you want the newest update before each retry. It overwrites local changes inside the temp clone, then re-runs the idempotent bootstrap. Paste the same line again after any recoverable failure:

```powershell
cd "$env:TEMP\install_claude"; git fetch origin; git reset --hard origin/main; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

If you used a custom Linux username, keep passing it on every retry:

```powershell
cd "$env:TEMP\install_claude"; git fetch origin; git reset --hard origin/main; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1 -Username nicolenguon
```

### Nuke and start over (clean re-clone)

If you suspect the local clone is in a weird state and you want a guaranteed fresh start:

```powershell
Remove-Item -Recurse -Force "$env:TEMP\install_claude"; git clone https://github.com/Y0lan/install_claude "$env:TEMP\install_claude"; cd "$env:TEMP\install_claude"; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

If WSL features had to be enabled for the first time, the script will tell you to reboot - reboot, then paste the **Re-run** line above.

## What it does

- Enables WSL + Virtual Machine Platform (exits cleanly with a reboot prompt if needed)
- Reuses existing `Ubuntu-22.04` without prompting to destroy it; `-CleanInstall` is the only WSL wipe path
- Installs Ubuntu-22.04 as the default WSL distro
- Provisions your Linux user with **passwordless sudo** and `systemd` enabled
- Installs Node LTS, Bun, Google Chrome (real `.deb`, not snap), zsh + oh-my-zsh + Pure prompt, `eza`, ripgrep, fd, fzf, bat, etc.
- Installs Claude Code (`claude`), OpenAI Codex CLI (`codex`, aliased as `c`), `claude-mem`, and exposes visible Claude skills in `~/.claude/skills/<skill-name>/SKILL.md` from:
  - [`garrytan/gstack`](https://github.com/garrytan/gstack)
  - [`forrestchang/andrej-karpathy-skills`](https://github.com/forrestchang/andrej-karpathy-skills)
  - [`obra/superpowers`](https://github.com/obra/superpowers)
  - [`mattpocock/skills`](https://github.com/mattpocock/skills)
- Installs **FiraCode Nerd Font Mono** (ligatures, single-cell glyphs - clean Powerline alignment)
- Patches Windows Terminal: neutral dark background, default font, default profile points at Ubuntu-22.04, opens in `~` with `zsh -l`
- Creates a Desktop shortcut `Ubuntu-22.04 (zsh).lnk`
- Creates a Desktop shortcut `Claude Code (auto).lnk` that opens WSL and launches `claude --permission-mode bypassPermissions`
- Opens a fresh terminal at the end -> first-run hook auto-launches `claude` for OAuth

## Options

```powershell
.\bootstrap.ps1 -Username yolan          # Linux username (default: your lowercased Windows username)
.\bootstrap.ps1 -Distro   Ubuntu-22.04   # WSL distro name
.\bootstrap.ps1 -CleanInstall            # auto-WIPE existing Ubuntu distros (skips the prompt - automation only)
```

Inside WSL, you can re-run `install.sh` any time:

```bash
bash ~/install.sh                 # full re-run (idempotent; cloned skills are detected and skipped)
bash ~/install.sh --no-skill-setup   # clone skills but do NOT execute their setup scripts
```

`install.sh` exit codes:
- `0` - everything OK
- `1..99` - that many skill repos had clone or setup failures (warning; the rest installed fine)
- `100+` - fatal (npm missing, Claude Code install failed, etc.) - `bootstrap.ps1` aborts before launching Claude

## Verify it worked

After OAuth completes, double-click the desktop shortcut and paste this one-liner inside zsh:

```bash
echo "--- versions ---"; node --version; bun --version; google-chrome --version | head -1; claude --version; codex --version; [ -f ~/.claude-mem/settings.json ] && echo "claude-mem: installed (settings.json present)" || echo "claude-mem: missing"; echo "--- visible skills ---"; find ~/.claude/skills -mindepth 2 -maxdepth 2 -name SKILL.md -printf '%h\n' | xargs -r -n1 basename | sort; echo "--- shell ---"; echo "shell: $SHELL"; grep -c '^prompt pure' ~/.zshrc && echo "pure prompt: configured"
```

Expected output (versions will differ; the structure is what matters):

```
--- versions ---
v22.x.x
1.x.x
Google Chrome 1xx.x.x.x
1.x.x (Claude Code)
0.x.x (Codex CLI)
claude-mem: installed (settings.json present)
--- visible skills ---
gstack
karpathy-guidelines
setup-matt-pocock-skills
using-superpowers
...more Matt Pocock and Superpowers skills...
--- shell ---
shell: /usr/bin/zsh
1
pure prompt: configured
```

## A few prompts you'll see during install (and what to answer)

The bootstrap will pause for input three times. None are blocking deadlines:

1. **gstack skill prefix** (10s timeout, default works) - chooses whether gstack skills surface as `/skill-name` or `/gstack-*`. Pick whichever you prefer.
2. **claude-mem install** - asks for IDE and LLM provider. Answer `claude-code` and `claude` unless you have a reason not to.
3. **Claude Code OAuth** at the very end - opens your browser. Sign in, paste the redirect URL back into the terminal if it asks. If you close mid-flow, the next time you open the desktop shortcut zsh will retry.

If any line says "command not found" or a skill is missing, just re-run `bash ~/install.sh` - it picks up where it left off and reports anything that failed in its final summary. Claude Code discovers only directories shaped like `~/.claude/skills/<skill-name>/SKILL.md`, so the installer exposes child skills from bundle repos directly under `~/.claude/skills/`.

## Shell shortcuts

The managed zsh block includes these aliases and helpers:

```bash
# AI / Omarchy-style
c     # codex
cx    # clear screen, then claude --permission-mode bypassPermissions
ic    # tdl c
ix    # tdl cx
icx   # tdl c cx
t     # tmux attach || tmux new -s Work

# Navigation
..    # cd ..
...   # cd ../..
....  # cd ../../..
cd    # zd, with zoxide support when zoxide is installed

# Listing
l     # eza --icons=auto
ls    # eza -lh --group-directories-first --icons=auto
ll    # eza -lh --group-directories-first --icons=auto
la    # eza -lha --group-directories-first --icons=auto
lsa   # ls -a
lt    # eza --tree --level=2 --long --icons --git
lta   # lt -a

# Git
g     # git
gst   # git status
gco   # git checkout
gp    # git pull
gP    # git push
gcm   # git commit -m
gcam  # git commit -a -m
gcad  # git commit -a --amend
glog  # git log --oneline --graph --decorate -20

# Kubernetes
k     # kubectl
kx    # kubectx
kn    # kubens

# Tools / utils
d          # docker
r          # rails
ff         # fzf with bat preview
eff        # edit fzf-selected file
decompress # tar -xzf
please     # re-run last command with sudo
path       # print PATH line by line
reload     # source ~/.bashrc
claude-mem # bun worker-service.cjs
```

## What's in the repo

- `bootstrap.ps1` - Windows side (PowerShell, runs once as Admin)
- `install.sh` - Linux side (bash, runs inside the WSL distro, can be re-run standalone)

Both files are reviewed against `codex` 4 times for shell-quoting bugs, idempotency holes, JSONC traps, and Windows/WSL edge cases. Final pass returned "no further critical findings".
