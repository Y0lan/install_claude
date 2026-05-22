# install_claude

One-shot bootstrap for a clean **WSL2 Ubuntu 22.04** dev box with Claude Code, gstack, Bun, Node, Google Chrome, zsh + Pure prompt, FiraCode Nerd Font, and the karpathy / superpowers / matt-pocock / claude-mem skill packs.

End state: open a Desktop shortcut → lands in `~` in `zsh` → Claude Code opens for OAuth automatically.

## Run it

Open an **Administrator PowerShell** window, then paste this single line:

```powershell
git clone https://github.com/Y0lan/install_claude "$env:TEMP\install_claude"; cd "$env:TEMP\install_claude"; Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
```

That's it. If WSL features had to be enabled for the first time, the script will tell you to reboot — reboot, then paste the same line again (every step is idempotent and resumes cleanly).

## What it does

- Enables WSL + Virtual Machine Platform (exits cleanly with a reboot prompt if needed)
- Detects existing `Ubuntu*` distros and offers a `WIPE`-confirmed clean install (case-sensitive — typo-proof)
- Installs Ubuntu-22.04 as the default WSL distro
- Provisions your Linux user with **passwordless sudo** and `systemd` enabled
- Installs Node LTS, Bun, Google Chrome (real `.deb`, not snap), zsh + oh-my-zsh + Pure prompt, ripgrep, fd, fzf, bat, etc.
- Installs Claude Code (`claude`), `claude-mem`, and clones into `~/.claude/skills/`:
  - [`garrytan/gstack`](https://github.com/garrytan/gstack)
  - [`forrestchang/andrej-karpathy-skills`](https://github.com/forrestchang/andrej-karpathy-skills)
  - [`obra/superpowers`](https://github.com/obra/superpowers)
  - [`mattpocock/skills`](https://github.com/mattpocock/skills)
- Installs **FiraCode Nerd Font Mono** (ligatures, single-cell glyphs — clean Powerline alignment)
- Patches Windows Terminal: default font, default profile points at Ubuntu-22.04, opens in `~` with `zsh -l`
- Creates a Desktop shortcut `Ubuntu-22.04 (zsh).lnk`
- Opens a fresh terminal at the end → first-run hook auto-launches `claude` for OAuth

## Options

```powershell
.\bootstrap.ps1 -Username yolan          # Linux username (default: your lowercased Windows username)
.\bootstrap.ps1 -Distro   Ubuntu-22.04   # WSL distro name
.\bootstrap.ps1 -CleanInstall            # auto-WIPE existing Ubuntu distros (skips the prompt — automation only)
```

Inside WSL, you can re-run `install.sh` any time:

```bash
bash ~/install.sh                 # full re-run (idempotent; cloned skills are detected and skipped)
bash ~/install.sh --no-skill-setup   # clone skills but do NOT execute their setup scripts
```

`install.sh` exit codes:
- `0` — everything OK
- `1..99` — that many skill repos had clone or setup failures (warning; the rest installed fine)
- `100+` — fatal (npm missing, Claude Code install failed, etc.) — `bootstrap.ps1` aborts before launching Claude

## Verify it worked

After OAuth completes, double-click the desktop shortcut and paste this one-liner inside zsh:

```bash
echo "--- versions ---"; node --version; bun --version; google-chrome --version | head -1; claude --version; [ -f ~/.claude-mem/settings.json ] && echo "claude-mem: installed (settings.json present)" || echo "claude-mem: missing"; echo "--- skills ---"; ls -1 ~/.claude/skills/; echo "--- shell ---"; echo "shell: $SHELL"; grep -c '^prompt pure' ~/.zshrc && echo "pure prompt: configured"
```

Expected output (versions will differ; the structure is what matters):

```
--- versions ---
v22.x.x
1.x.x
Google Chrome 1xx.x.x.x
1.x.x (Claude Code)
claude-mem: installed (settings.json present)
--- skills ---
andrej-karpathy-skills
gstack
matt-pocock-skills
superpowers
--- shell ---
shell: /usr/bin/zsh
1
pure prompt: configured
```

## A few prompts you'll see during install (and what to answer)

The bootstrap will pause for input three times. None are blocking deadlines:

1. **gstack skill prefix** (10s timeout, default works) — chooses whether gstack skills surface as `/skill-name` or `/gstack-*`. Pick whichever you prefer.
2. **claude-mem install** — asks for IDE and LLM provider. Answer `claude-code` and `claude` unless you have a reason not to.
3. **Claude Code OAuth** at the very end — opens your browser. Sign in, paste the redirect URL back into the terminal if it asks. If you close mid-flow, the next time you open the desktop shortcut zsh will retry.

If any line says "command not found" or a skill is missing, just re-run `bash ~/install.sh` — it picks up where it left off and reports anything that failed in its final summary.

## What's in the repo

- `bootstrap.ps1` — Windows side (PowerShell, runs once as Admin)
- `install.sh` — Linux side (bash, runs inside the WSL distro, can be re-run standalone)

Both files are reviewed against `codex` 4 times for shell-quoting bugs, idempotency holes, JSONC traps, and Windows/WSL edge cases. Final pass returned "no further critical findings".
