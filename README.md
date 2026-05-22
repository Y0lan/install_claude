# install_claude

Bootstrap a Windows dev machine with WSL2 Ubuntu 22.04, Claude Code, Codex, Bun, Node, Chrome, zsh, tmux, useful aliases, and Claude skills.

The script is rerunnable. If something is already installed, it skips that step.

End result:
- Desktop shortcut: `Ubuntu-22.04 (zsh).lnk`
- Desktop shortcut: `Claude Code (auto).lnk`
- WSL opens in `~` with zsh and a neutral dark Windows Terminal theme
- First launch opens Claude Code for OAuth

## 1. Open Admin PowerShell

Open **PowerShell as Administrator**.

Do not run these commands inside WSL.

## 2. Pick One Command

### Normal install or update

Use this first. It keeps an existing `Ubuntu-22.04` distro and fills in whatever is missing.

```powershell
Remove-Item -Recurse -Force "$env:TEMP\install_claude" -ErrorAction SilentlyContinue; git clone https://github.com/Y0lan/install_claude "$env:TEMP\install_claude"; cd "$env:TEMP\install_claude"; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

### Fresh install

Use this only when you want to delete Ubuntu and start over.

This permanently deletes existing Ubuntu WSL distro(s), including all Linux files inside them.

```powershell
Remove-Item -Recurse -Force "$env:TEMP\install_claude" -ErrorAction SilentlyContinue; git clone https://github.com/Y0lan/install_claude "$env:TEMP\install_claude"; cd "$env:TEMP\install_claude"; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1 -CleanInstall
```

### Retry after a failed run

If the repo was already cloned and a run stopped halfway through:

```powershell
cd "$env:TEMP\install_claude"; git pull; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

If a new fix was pushed and `git pull` complains, force the temp clone back to GitHub:

```powershell
cd "$env:TEMP\install_claude"; git fetch origin; git reset --hard origin/main; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

## 3. Reboot If Asked

If the script says WSL features were enabled and asks for a reboot:

1. Reboot Windows.
2. Open **Admin PowerShell** again.
3. Run the retry command:

```powershell
cd "$env:TEMP\install_claude"; git pull; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

## 4. Answer Prompts

During install you may see these prompts:

- `gstack` skill prefix: press Enter or accept the default.
- `claude-mem`: choose `claude-code` for IDE and `claude` for provider.
- Claude OAuth: sign in in the browser when Claude opens.

## 5. Use It

After the script finishes:

- Open `Claude Code (auto).lnk` to launch Claude with bypass permissions.
- Open `Ubuntu-22.04 (zsh).lnk` for a normal WSL terminal.
- If Claude was already open, restart it so newly installed skills appear.

Inside Claude, check:

```text
/skills
```

For Matt Pocock skills, run:

```text
/setup-matt-pocock-skills
```

## 6. Quick Verify

Paste this inside the WSL zsh terminal:

```bash
echo "--- versions ---"; node --version; bun --version; google-chrome --version | head -1; claude --version; codex --version; echo "--- visible skills ---"; find ~/.claude/skills -mindepth 2 -maxdepth 2 -name SKILL.md -printf '%h\n' | xargs -r -n1 basename | sort; echo "--- shell ---"; echo "$SHELL"
```

You should see versions for Node, Bun, Chrome, Claude, and Codex, plus visible skills such as:

```text
gstack
karpathy-guidelines
setup-matt-pocock-skills
using-superpowers
```

## Daily Shortcuts

Useful aliases added to zsh:

```bash
c       # codex
cx      # clear screen, then claude --permission-mode bypassPermissions
t       # tmux attach || tmux new -s Work
ic      # tmux layout with codex
ix      # tmux layout with cx
icx     # tmux layout with codex + cx

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
reload  # source ~/.bashrc
please  # rerun last command with sudo
path    # print PATH line by line
```

## What Gets Installed

- WSL2 Ubuntu 22.04
- Passwordless sudo for the Linux user
- systemd in WSL
- zsh, oh-my-zsh, Pure prompt, tmux, fzf, ripgrep, fd, bat, eza
- Node LTS, Bun, Google Chrome
- Claude Code, OpenAI Codex CLI, claude-mem
- Claude skills from gstack, Karpathy, Superpowers, and Matt Pocock
- FiraCode Nerd Font Mono
- Windows Terminal profile and desktop shortcuts

## Files

- `bootstrap.ps1`: Windows/Admin PowerShell bootstrap
- `install.sh`: Linux-side installer, rerunnable inside WSL with `bash ~/install.sh`
