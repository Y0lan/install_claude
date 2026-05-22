#!/usr/bin/env bash
# ============================================================================
# WSL Ubuntu 22.04 — Linux-side bootstrap
# Run as your normal (non-root) Linux user. Invoked automatically by
# bootstrap.ps1, or run manually with:
#   bash ~/install.sh                # default: clone + run upstream setup
#   bash ~/install.sh --no-skill-setup   # clone, but do NOT run upstream setup/install scripts
# ============================================================================
set -euo pipefail

# ---------- args ----------
SKIP_SKILL_SETUP=0
for arg in "$@"; do
  case "$arg" in
    --no-skill-setup) SKIP_SKILL_SETUP=1 ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown arg: $arg (use --help)" >&2; exit 2 ;;
  esac
done

# ---------- helpers ----------
log() { printf '\033[1;36m[%(%H:%M:%S)T]\033[0m %s\n' -1 "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

if [ "$EUID" -eq 0 ]; then
  echo "Don't run install.sh as root. Run as your normal user." >&2
  exit 1
fi
if ! have sudo; then
  echo "sudo not found — is this Ubuntu?" >&2; exit 1
fi

USER_NAME="$(whoami)"
log "User: $USER_NAME — home: $HOME — skip-skill-setup: $SKIP_SKILL_SETUP"
log "Expect 10-30 min total (apt updates, npm globals, gstack runs playwright install ~300MB)."
log "No interactive prompts. gstack may ask one question with a 10s timeout — we pass -q to skip it."

# Accumulator for skill-clone failures (reported at end, doesn't abort the script)
declare -a SKILL_FAILURES=()

# ---------- 1. passwordless sudo (idempotent) ----------
SUDOERS_FILE="/etc/sudoers.d/99-${USER_NAME}-nopasswd"
if ! sudo test -f "$SUDOERS_FILE"; then
  log "Configuring passwordless sudo (you may be asked for your password ONE last time)"
  echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" | sudo tee "$SUDOERS_FILE" >/dev/null
  sudo chmod 0440 "$SUDOERS_FILE"
fi

# ---------- 2. apt base packages ----------
log "apt update + base packages"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl wget ca-certificates gnupg lsb-release \
  git build-essential pkg-config \
  zsh unzip zip tar \
  jq ripgrep fd-find fzf bat \
  htop tmux vim nano less tree \
  python3 python3-pip python3-venv \
  software-properties-common xdg-utils \
  fonts-firacode \
  libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
  libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
  libgbm1 libpango-1.0-0 libcairo2 libasound2

# fd-find ships as `fdfind` on Ubuntu — symlink to fd
mkdir -p "$HOME/.local/bin"
if have fdfind && ! have fd; then
  ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
fi
if have batcat && ! have bat; then
  ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
fi
# Make sure ~/.local/bin is in PATH for the rest of this script
export PATH="$HOME/.local/bin:$PATH"

# ---------- 3. Google Chrome .deb (real .deb — snap chromium is broken in WSL) ----------
log "Installing Google Chrome (real .deb; snap chromium doesn't work in WSL)"
if ! have google-chrome; then
  TMPDEB="$(mktemp --suffix=.deb)"
  wget -qO "$TMPDEB" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$TMPDEB"
  rm -f "$TMPDEB"
fi
# Convenience symlink: `chromium` resolves to Chrome. Note: this is Chrome with
# a chromium-named symlink, NOT actual Chromium-browser. Most tools that want
# "a chromium binary" (puppeteer, playwright, lighthouse) accept Chrome here.
if ! have chromium && have google-chrome; then
  sudo ln -sf "$(command -v google-chrome)" /usr/local/bin/chromium
fi

# ---------- 4. Node.js (NodeSource LTS) ----------
log "Installing Node.js LTS"
if ! have node || ! node --version 2>/dev/null | grep -qE '^v(20|22|24)\.'; then
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
fi
# Sanity-check npm exists before we touch its config (NodeSource ships npm with nodejs)
if ! have npm; then
  echo "FATAL: node/npm install failed. Check NodeSource setup output above." >&2
  exit 100
fi

# user-local npm prefix so `npm i -g` doesn't need sudo
log "Configuring npm user-global prefix at ~/.npm-global"
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"

# ---------- 5. Bun ----------
log "Installing Bun"
if ! have bun; then
  curl -fsSL https://bun.sh/install | bash
fi
export PATH="$HOME/.bun/bin:$PATH"

# ---------- 6. zsh + oh-my-zsh + Pure ----------
ZSH_BIN="$(command -v zsh)"
log "Ensuring $ZSH_BIN is registered in /etc/shells"
if ! grep -qxF "$ZSH_BIN" /etc/shells; then
  echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
fi
log "Setting zsh as default shell for $USER_NAME"
if [ "$(getent passwd "$USER_NAME" | cut -d: -f7)" != "$ZSH_BIN" ]; then
  sudo chsh -s "$ZSH_BIN" "$USER_NAME"
fi

# Pre-backup existing .zshrc BEFORE oh-my-zsh installer (which may overwrite it).
# Glob check so reruns don't keep stamping new backups (round-2 finding).
shopt -s nullglob 2>/dev/null || setopt +o nomatch 2>/dev/null || true
existing_backups=( "$HOME"/.zshrc.pre-bootstrap.* )
shopt -u nullglob 2>/dev/null || true
if [ -f "$HOME/.zshrc" ] && [ "${#existing_backups[@]}" -eq 0 ]; then
  cp "$HOME/.zshrc" "$HOME/.zshrc.pre-bootstrap.$(date +%s)"
fi

# Sentinel-file checks instead of directory checks — catches half-installed
# state from killed/aborted previous runs.
if [ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
  [ -d "$HOME/.oh-my-zsh" ] && rm -rf "$HOME/.oh-my-zsh"
  log "Installing oh-my-zsh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# zsh plugins
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
clone_if_needed() {
  local repo="$1" dest="$2" sentinel="$3"
  if [ ! -f "$dest/$sentinel" ]; then
    [ -d "$dest" ] && rm -rf "$dest"
    git clone --depth=1 "$repo" "$dest"
  fi
}
clone_if_needed https://github.com/zsh-users/zsh-autosuggestions       "$ZSH_CUSTOM/plugins/zsh-autosuggestions"       "zsh-autosuggestions.zsh"
clone_if_needed https://github.com/zsh-users/zsh-syntax-highlighting   "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"   "zsh-syntax-highlighting.zsh"
clone_if_needed https://github.com/sindresorhus/pure.git                "$HOME/.zsh/pure"                                "pure.zsh"

# ---------- 7. .zshrc (managed-block — user edits outside markers are preserved) ----------
log "Writing managed block in ~/.zshrc"
ZSHRC="$HOME/.zshrc"
START_MARKER='# >>> claude-bootstrap >>>'
END_MARKER='# <<< claude-bootstrap <<<'

MANAGED_TMP="$(mktemp)"
cat > "$MANAGED_TMP" <<'BLOCK'
# (auto-managed by ~/install.sh — content between the markers is overwritten on rerun)
# Anything OUTSIDE the markers is preserved.

# ===== PATH =====
typeset -U path
path=(
  "$HOME/.local/bin"
  "$HOME/.bun/bin"
  "$HOME/.npm-global/bin"
  "$HOME/.cargo/bin"
  $path
)
export PATH

# ===== oh-my-zsh =====
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""   # Pure handles the prompt
plugins=(git docker docker-compose npm node z zsh-autosuggestions zsh-syntax-highlighting)
source "$ZSH/oh-my-zsh.sh"

# ===== Pure prompt =====
fpath+=("$HOME/.zsh/pure")
autoload -U promptinit && promptinit
prompt pure

# ===== Bun completions =====
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# ===== history =====
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

# ===== aliases =====
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -20'
alias ..='cd ..'
alias ...='cd ../..'

# ===== fzf =====
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh
[ -f /usr/share/doc/fzf/examples/completion.zsh ]   && source /usr/share/doc/fzf/examples/completion.zsh

# ===== always start in $HOME on interactive login =====
[[ $- == *i* && -z ${WSL_STARTUP_DONE-} ]] && { export WSL_STARTUP_DONE=1; cd "$HOME"; }

# ===== first-run hook: launch claude OAuth =====
# Marker removed ONLY if claude exits cleanly AND we can see actual credentials
# on disk afterward (otherwise the user quit before completing OAuth).
if [[ -f "$HOME/.claude-firstrun" && -z ${CLAUDE_FIRSTRUN_DONE-} ]]; then
  export CLAUDE_FIRSTRUN_DONE=1
  if command -v claude >/dev/null 2>&1; then
    echo ""
    echo "First launch — opening Claude Code for OAuth login..."
    echo "(Close this terminal mid-OAuth and the next zsh will retry.)"
    echo ""
    claude
    _claude_rc=$?
    # Proper file-vs-directory predicates. `-s` returns true on non-empty dirs
    # on Linux (ext4 reports dir size > 0), so it can't be applied to dirs.
    # ls -A on a regular file also yields garbage. Split the two cases.
    _authed=0
    for _p in "$HOME/.config/claude" "$HOME/.claude/credentials" "$HOME/.claude/.credentials.json"; do
      if [ -d "$_p" ]; then
        if [ -n "$(ls -A "$_p" 2>/dev/null)" ]; then _authed=1; break; fi
      elif [ -f "$_p" ]; then
        if [ -s "$_p" ]; then _authed=1; break; fi
      fi
    done
    if [ "$_claude_rc" = 0 ] && [ "$_authed" = 1 ]; then
      rm -f "$HOME/.claude-firstrun"
    else
      echo "(first-run marker kept — OAuth doesn't look complete yet; will retry next zsh)"
    fi
    unset _claude_rc _authed _p
  fi
fi
BLOCK

# Marker-pair sanity check. If both markers exist (in order) → in-place splice.
# If only one marker exists → file is corrupted; back it up and write a fresh
# one (don't risk eating everything after a lone start marker).
# Use awk for counting: grep -c prints '0' AND exits non-zero on no match,
# so `grep -c ... || echo 0` produced "0\n0" — failing later integer compares.
if [ -f "$ZSHRC" ]; then
  has_start=$(awk -v m="$START_MARKER" '$0==m{c++} END{print c+0}' "$ZSHRC")
  has_end=$(awk   -v m="$END_MARKER"   '$0==m{c++} END{print c+0}' "$ZSHRC")
else
  has_start=0; has_end=0
fi

if [ "$has_start" -ge 1 ] && [ "$has_end" -ge 1 ]; then
  # Verify start comes before end (line numbers)
  start_line=$(grep -nFx "$START_MARKER" "$ZSHRC" | head -1 | cut -d: -f1)
  end_line=$(grep   -nFx "$END_MARKER"   "$ZSHRC" | head -1 | cut -d: -f1)
  if [ "$start_line" -lt "$end_line" ]; then
    TMP="$(mktemp)"
    awk -v sm="$START_MARKER" -v em="$END_MARKER" -v mfile="$MANAGED_TMP" '
      $0 == sm { print; while ((getline ln < mfile) > 0) print ln; close(mfile); skip=1; next }
      $0 == em { print; skip=0; next }
      !skip { print }
    ' "$ZSHRC" > "$TMP"
    mv "$TMP" "$ZSHRC"
  else
    log "WARN: $ZSHRC has markers out of order; backing up and rewriting"
    cp "$ZSHRC" "$ZSHRC.corrupted.$(date +%s)"
    { echo "$START_MARKER"; cat "$MANAGED_TMP"; echo "$END_MARKER"; } > "$ZSHRC"
  fi
elif [ "$has_start" -ge 1 ] || [ "$has_end" -ge 1 ]; then
  log "WARN: $ZSHRC has only one marker (corrupted). Backing up and rewriting from scratch."
  cp "$ZSHRC" "$ZSHRC.corrupted.$(date +%s)"
  { echo "$START_MARKER"; cat "$MANAGED_TMP"; echo "$END_MARKER"; } > "$ZSHRC"
else
  # No markers — append fresh block, preserve any existing content
  {
    if [ -f "$ZSHRC" ]; then cat "$ZSHRC"; echo ""; fi
    echo "$START_MARKER"
    cat "$MANAGED_TMP"
    echo "$END_MARKER"
  } > "$ZSHRC.new"
  mv "$ZSHRC.new" "$ZSHRC"
fi
rm -f "$MANAGED_TMP"

# ---------- 8. Claude Code ----------
log "Installing Claude Code (@anthropic-ai/claude-code)"
if ! have claude; then
  if ! npm install -g @anthropic-ai/claude-code; then
    echo "FATAL: claude-code install failed. Try: npm i -g @anthropic-ai/claude-code" >&2
    exit 100
  fi
fi

# ---------- 9. claude-mem ----------
log "Installing claude-mem"
if ! have claude-mem; then
  npm install -g claude-mem || log "WARN: claude-mem install failed — try 'npm i -g claude-mem' later"
fi

# ---------- 10. Claude skills (~/.claude/skills/) ----------
log "Setting up ~/.claude/skills/"
mkdir -p "$HOME/.claude/skills"

install_skill() {
  local name="$1" url="$2"
  local dest="$HOME/.claude/skills/$name"
  if [ -z "$url" ]; then
    log "  $name: SKIPPED (no repo URL)"
    return 0
  fi
  if [ -d "$dest/.git" ]; then
    log "  $name: already cloned (not auto-updated; run 'git -C $dest pull' to refresh)"
    return 0
  fi
  if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
    log "  $name: WARN — $dest exists and is not a git repo. Skipping. Remove it manually to re-clone."
    SKILL_FAILURES+=("$name (existing non-git dir at $dest)")
    return 0
  fi
  # Empty placeholder dir? rmdir so clone can create it cleanly.
  [ -d "$dest" ] && rmdir "$dest" 2>/dev/null || true

  if git clone --depth=1 "$url" "$dest"; then
    log "  $name: cloned"
    if [ "$SKIP_SKILL_SETUP" = "1" ]; then
      log "  $name: skipped upstream setup (--no-skill-setup)"
    else
      # Run upstream setup/install scripts if present.
      # SECURITY: this executes code from the cloned repo. You opted in by
      # listing the URL above. Run with --no-skill-setup to disable.
      # gstack/setup has a 10s-timeout prompt about skill name prefix; -q skips it
      # and picks the default. Other upstream setups don't have known prompts.
      local setup_args=()
      [ "$name" = "gstack" ] && setup_args=("-q")

      if [ -x "$dest/setup" ]; then
        log "  $name: running ./setup ${setup_args[*]}"
        if ! ( cd "$dest" && ./setup "${setup_args[@]}" ); then
          log "  $name: WARN setup exited non-zero"
          SKILL_FAILURES+=("$name (setup script failed)")
        fi
      elif [ -x "$dest/install.sh" ]; then
        log "  $name: running ./install.sh"
        if ! ( cd "$dest" && bash ./install.sh ); then
          log "  $name: WARN install.sh exited non-zero"
          SKILL_FAILURES+=("$name (install.sh failed)")
        fi
      fi
    fi
  else
    log "  $name: WARN — clone failed from $url"
    SKILL_FAILURES+=("$name <- $url (clone failed)")
  fi
}

# Canonical repos (verified May 2026 — change if upstream moves):
GSTACK_REPO="https://github.com/garrytan/gstack.git"
KARPATHY_REPO="https://github.com/forrestchang/andrej-karpathy-skills.git"
SUPERPOWERS_REPO="https://github.com/obra/superpowers.git"
MATT_POCOCK_REPO="https://github.com/mattpocock/skills.git"

install_skill "gstack"                  "$GSTACK_REPO"
install_skill "andrej-karpathy-skills"  "$KARPATHY_REPO"
install_skill "superpowers"             "$SUPERPOWERS_REPO"
install_skill "matt-pocock-skills"      "$MATT_POCOCK_REPO"

# Alternative install path for superpowers (via Claude Code marketplace, after OAuth):
#   /plugin install superpowers@claude-plugins-official

# ---------- 11. First-run marker (so .zshrc auto-launches claude on first interactive zsh) ----------
# Only create if claude is actually installed AND user isn't already logged in.
# Detection is heuristic — we check known credential paths. Proper file-vs-dir
# predicates: `-s` is only valid on files (returns true on non-empty dirs on
# some filesystems); `ls -A` only makes sense on dirs.
CLAUDE_CRED_PATHS=("$HOME/.config/claude" "$HOME/.claude/credentials" "$HOME/.claude/.credentials.json")
already_authed=0
for p in "${CLAUDE_CRED_PATHS[@]}"; do
  if [ -d "$p" ]; then
    [ -n "$(ls -A "$p" 2>/dev/null)" ] && { already_authed=1; break; }
  elif [ -f "$p" ]; then
    [ -s "$p" ] && { already_authed=1; break; }
  fi
done
if [ "$already_authed" = "0" ]; then
  touch "$HOME/.claude-firstrun"
fi

# ---------- 12. Done — summary ----------
log "===== install.sh complete ====="
echo ""
echo "  Shell:      zsh + Pure prompt"
echo "  Node:       $(node --version 2>/dev/null || echo 'missing')"
echo "  Bun:        $(bun --version 2>/dev/null || echo 'missing')"
echo "  Chrome:     $(google-chrome --version 2>/dev/null || echo 'missing')"
echo "  Claude:     $(claude --version 2>/dev/null || echo 'missing')"
echo "  claude-mem: $(claude-mem --version 2>/dev/null || echo 'missing')"
echo ""

if [ "${#SKILL_FAILURES[@]}" -gt 0 ]; then
  log "WARN: ${#SKILL_FAILURES[@]} skill repo(s) had issues:"
  for f in "${SKILL_FAILURES[@]}"; do echo "    - $f"; done
  echo ""
  echo "  Re-run install.sh after fixing the above to retry just the failed skills."
  echo "  (Successful clones are detected and skipped.)"
  echo ""
fi

echo "  Next: close this shell, open 'Ubuntu-22.04 (zsh)' desktop shortcut."
echo "        zsh will start in ~ and launch \`claude\` for OAuth automatically."
echo ""

# Exit-code convention (so bootstrap.ps1 can distinguish):
#   0          = everything OK
#   1..99      = N skill failures (partial — user can re-run to retry)
#   100+       = fatal (npm missing, claude install failed, etc.) — already exited above
n="${#SKILL_FAILURES[@]}"
[ "$n" -gt 99 ] && n=99
exit "$n"
