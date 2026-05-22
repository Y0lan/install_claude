#!/usr/bin/env bash
# ============================================================================
# WSL Ubuntu 22.04 - Linux-side bootstrap
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
have_deb() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
missing_debs() {
  local pkg
  for pkg in "$@"; do
    have_deb "$pkg" || printf '%s\n' "$pkg"
  done
}
retry() {
  local tries="$1"; shift
  local delay=2
  local rc=0
  local i
  for ((i = 1; i <= tries; i++)); do
    if "$@"; then return 0; fi
    rc=$?
    if [ "$i" -lt "$tries" ]; then
      log "WARN: command failed (exit $rc), retrying in ${delay}s: $*"
      sleep "$delay"
      delay=$((delay * 2))
    fi
  done
  return "$rc"
}

if [ "$EUID" -eq 0 ]; then
  echo "Don't run install.sh as root. Run as your normal user." >&2
  exit 1
fi
if ! have sudo; then
  echo "sudo not found - is this Ubuntu?" >&2; exit 1
fi

USER_NAME="$(whoami)"
if ! sudo -n true 2>/dev/null; then
  echo "FATAL: passwordless sudo is not configured for $USER_NAME. Re-run bootstrap.ps1 so it can write /etc/sudoers.d/99-${USER_NAME}-nopasswd." >&2
  exit 100
fi
log "User: $USER_NAME - home: $HOME - skip-skill-setup: $SKIP_SKILL_SETUP"
log "Expect 10-30 min total (apt updates, npm globals, gstack runs playwright install ~300MB)."
log "A few steps will pause for input - that's intentional:"
log "  - gstack/setup asks about skill name prefix (10s timeout, default is fine)"
log "  - npx claude-mem install: pick Claude Code + Codex for harness, then Claude Code for provider"
log "  - claude OAuth at the very end (browser-based, no typing)"
log "Answer at your own pace - nothing is on a hard deadline."

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
log "Checking apt base packages"
# Dpkg options applied to EVERY apt-get install/upgrade so maintainer-conflict
# prompts ("keep current config? use new?") never surface and hang reruns.
APT_OPTS=(-o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef")
APT_PACKAGES=(
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
)
mapfile -t MISSING_APT_PACKAGES < <(missing_debs "${APT_PACKAGES[@]}")
if [ "${#MISSING_APT_PACKAGES[@]}" -gt 0 ]; then
  log "Installing missing apt package(s): ${MISSING_APT_PACKAGES[*]}"
  retry 3 sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
  retry 3 sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_OPTS[@]}" "${MISSING_APT_PACKAGES[@]}"
else
  log "Base apt packages already installed; skipping apt update/install"
fi

# fd-find ships as `fdfind` on Ubuntu - symlink to fd
mkdir -p "$HOME/.local/bin"
if have fdfind && ! have fd; then
  ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
fi
if have batcat && ! have bat; then
  ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
fi
# Make sure ~/.local/bin is in PATH for the rest of this script
export PATH="$HOME/.local/bin:$PATH"

install_eza_if_needed() {
  if have eza; then
    log "eza already installed; skipping"
    return 0
  fi

  if apt-cache show eza >/dev/null 2>&1; then
    log "Installing eza"
    if retry 2 sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_OPTS[@]}" eza; then
      return 0
    fi
  else
    log "eza is not available in current apt sources; adding eza community apt repo"
  fi

  local key_tmp eza_arch
  key_tmp="$(mktemp)"
  if retry 3 wget -qO "$key_tmp" https://raw.githubusercontent.com/eza-community/eza/main/deb.asc &&
     sudo mkdir -p /etc/apt/keyrings &&
     sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/gierens.gpg "$key_tmp"; then
    rm -f "$key_tmp"
    eza_arch="$(dpkg --print-architecture)"
    echo "deb [arch=$eza_arch signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    if retry 3 sudo DEBIAN_FRONTEND=noninteractive apt-get update -y &&
       retry 3 sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_OPTS[@]}" eza; then
      return 0
    fi
  else
    rm -f "$key_tmp"
  fi

  log "WARN: eza install failed; listing aliases will fall back to GNU ls"
  return 1
}
install_eza_if_needed || true

# ---------- 3. Google Chrome .deb (real .deb - snap chromium is broken in WSL) ----------
log "Checking Google Chrome (real .deb; snap chromium doesn't work in WSL)"
if ! have google-chrome; then
  TMPDEB="$(mktemp --suffix=.deb)"
  if ! retry 3 wget -qO "$TMPDEB" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb; then
    rm -f "$TMPDEB"
    echo "FATAL: Google Chrome download failed. Re-run install.sh to retry." >&2
    exit 100
  fi
  if ! retry 3 sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_OPTS[@]}" "$TMPDEB"; then
    rm -f "$TMPDEB"
    echo "FATAL: Google Chrome install failed. Re-run install.sh to retry." >&2
    exit 100
  fi
  rm -f "$TMPDEB"
else
  log "Google Chrome already installed; skipping download"
fi
# Convenience symlink: `chromium` resolves to Chrome. Note: this is Chrome with
# a chromium-named symlink, NOT actual Chromium-browser. Most tools that want
# "a chromium binary" (puppeteer, playwright, lighthouse) accept Chrome here.
if ! have chromium && have google-chrome; then
  sudo ln -sf "$(command -v google-chrome)" /usr/local/bin/chromium
fi

# ---------- 4. Node.js (NodeSource LTS) ----------
log "Checking Node.js LTS"
if ! have node || ! node --version 2>/dev/null | grep -qE '^v(20|22|24)\.'; then
  NODESOURCE_SETUP="$(mktemp)"
  if ! retry 3 curl -fsSL -o "$NODESOURCE_SETUP" https://deb.nodesource.com/setup_lts.x; then
    rm -f "$NODESOURCE_SETUP"
    echo "FATAL: NodeSource setup download failed. Re-run install.sh to retry." >&2
    exit 100
  fi
  if ! sudo -E bash "$NODESOURCE_SETUP"; then
    rm -f "$NODESOURCE_SETUP"
    echo "FATAL: NodeSource setup failed. Re-run install.sh to retry." >&2
    exit 100
  fi
  rm -f "$NODESOURCE_SETUP"
  if ! retry 3 sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_OPTS[@]}" nodejs; then
    echo "FATAL: Node.js install failed. Re-run install.sh to retry." >&2
    exit 100
  fi
else
  log "Node.js already installed; skipping NodeSource download"
fi
# Sanity-check npm exists before we touch its config (NodeSource ships npm with nodejs)
if ! have npm; then
  echo "FATAL: node/npm install failed. Check NodeSource setup output above." >&2
  exit 100
fi

# user-local npm prefix so `npm i -g` doesn't need sudo
mkdir -p "$HOME/.npm-global"
if [ "$(npm config get prefix 2>/dev/null || true)" != "$HOME/.npm-global" ]; then
  log "Configuring npm user-global prefix at ~/.npm-global"
  npm config set prefix "$HOME/.npm-global"
else
  log "npm user-global prefix already configured; skipping"
fi
export PATH="$HOME/.npm-global/bin:$PATH"

# ---------- 5. Bun ----------
log "Checking Bun"
if ! have bun; then
  BUN_INSTALLER="$(mktemp)"
  if ! retry 3 curl -fsSL -o "$BUN_INSTALLER" https://bun.sh/install; then
    rm -f "$BUN_INSTALLER"
    echo "FATAL: Bun installer download failed. Re-run install.sh to retry." >&2
    exit 100
  fi
  if ! bash "$BUN_INSTALLER"; then
    rm -f "$BUN_INSTALLER"
    echo "FATAL: Bun install failed. Re-run install.sh to retry." >&2
    exit 100
  fi
  rm -f "$BUN_INSTALLER"
else
  log "Bun already installed; skipping download"
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
  if ! sudo chsh -s "$ZSH_BIN" "$USER_NAME"; then
    log "WARN: chsh failed; shortcut still launches zsh explicitly"
  fi
fi

# Pre-backup existing .zshrc BEFORE oh-my-zsh installer (which may overwrite it).
# Glob check so reruns don't keep stamping new backups (round-2 finding).
shopt -s nullglob 2>/dev/null || setopt +o nomatch 2>/dev/null || true
existing_backups=( "$HOME"/.zshrc.pre-bootstrap.* )
shopt -u nullglob 2>/dev/null || true
if [ -f "$HOME/.zshrc" ] && [ "${#existing_backups[@]}" -eq 0 ]; then
  cp "$HOME/.zshrc" "$HOME/.zshrc.pre-bootstrap.$(date +%s)"
fi

# Sentinel-file checks instead of directory checks - catches half-installed
# state from killed/aborted previous runs.
if [ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
  [ -d "$HOME/.oh-my-zsh" ] && rm -rf "$HOME/.oh-my-zsh"
  log "Installing oh-my-zsh"
  OMZ_INSTALLER="$(mktemp)"
  if ! retry 3 curl -fsSL -o "$OMZ_INSTALLER" https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh; then
    rm -f "$OMZ_INSTALLER"
    echo "FATAL: oh-my-zsh installer download failed. Re-run install.sh to retry." >&2
    exit 100
  fi
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh "$OMZ_INSTALLER" || {
      rm -f "$OMZ_INSTALLER"
      echo "FATAL: oh-my-zsh install failed. Re-run install.sh to retry." >&2
      exit 100
    }
  rm -f "$OMZ_INSTALLER"
else
  log "oh-my-zsh already installed; skipping download"
fi

# zsh plugins
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
clone_if_needed() {
  local repo="$1" dest="$2" sentinel="$3"
  local name
  name="$(basename "$dest")"
  if [ ! -f "$dest/$sentinel" ]; then
    [ -d "$dest" ] && rm -rf "$dest"
    log "Installing $name"
    retry 3 git clone --depth=1 "$repo" "$dest"
    log "$name cloned"
  else
    log "$name already installed; skipping clone"
  fi
}
clone_if_needed https://github.com/zsh-users/zsh-autosuggestions       "$ZSH_CUSTOM/plugins/zsh-autosuggestions"       "zsh-autosuggestions.zsh"
clone_if_needed https://github.com/zsh-users/zsh-syntax-highlighting   "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"   "zsh-syntax-highlighting.zsh"
clone_if_needed https://github.com/sindresorhus/pure.git                "$HOME/.zsh/pure"                                "pure.zsh"

# ---------- 7. .zshrc (managed-block - user edits outside markers are preserved) ----------
log "Writing managed block in ~/.zshrc"
ZSHRC="$HOME/.zshrc"
START_MARKER='# >>> claude-bootstrap >>>'
END_MARKER='# <<< claude-bootstrap <<<'

MANAGED_TMP="$(mktemp)"
cat > "$MANAGED_TMP" <<'BLOCK'
# (auto-managed by ~/install.sh - content between the markers is overwritten on rerun)
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

# ===== navigation =====
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi
zd() {
  if (( $# == 0 )); then
    builtin cd ~ || return
  elif [[ -d $1 ]]; then
    builtin cd "$1" || return
  elif command -v z >/dev/null 2>&1; then
    z "$@"
  else
    builtin cd "$@"
  fi
}
alias cd='zd'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# ===== listing =====
if command -v eza >/dev/null 2>&1; then
  alias l='eza --icons=auto'
  alias ls='eza -lh --group-directories-first --icons=auto'
  alias ll='eza -lh --group-directories-first --icons=auto'
  alias la='eza -lha --group-directories-first --icons=auto'
  alias lsa='ls -a'
  alias lt='eza --tree --level=2 --long --icons --git'
  alias lta='lt -a'
else
  alias l='command ls --color=auto'
  alias ls='command ls -lh --group-directories-first --color=auto'
  alias ll='command ls -lh --group-directories-first --color=auto'
  alias la='command ls -lha --group-directories-first --color=auto'
  alias lsa='command ls -a --color=auto'
  alias lt='find . -maxdepth 2 -print'
  alias lta='find . -maxdepth 2 -print'
fi

# ===== AI / Omarchy-style =====
alias c='codex'
alias cx='printf "\033[2J\033[3J\033[H" && claude --permission-mode bypassPermissions'
alias t='tmux attach || tmux new -s Work'
alias ic='tdl c'
alias ix='tdl cx'
alias icx='tdl c cx'

# ===== git =====
alias g='git'
alias gst='git status'
alias gco='git checkout'
alias gp='git pull'
alias gP='git push'
alias gcm='git commit -m'
alias gcam='git commit -a -m'
alias gcad='git commit -a --amend'
alias glog='git log --oneline --graph --decorate -20'

# ===== Kubernetes =====
alias k='kubectl'
alias kx='kubectx'
alias kn='kubens'

# ===== tools / utils =====
alias d='docker'
alias r='rails'
alias ff="fzf --preview 'bat --style=numbers --color=always {}'"
alias eff='$EDITOR "$(ff)"'
alias decompress='tar -xzf'
alias reload='source ~/.bashrc'
alias claude-mem='bun worker-service.cjs'
please() {
  local last_cmd
  last_cmd="$(fc -ln -1)"
  print -r -- "sudo $last_cmd"
  eval "sudo $last_cmd"
}
path() {
  print -l ${(s.:.)PATH}
}

# Omarchy-style tmux AI layout: editor on the left, agent pane(s) on the right.
tdl() {
  [[ -z ${1:-} ]] && { echo "Usage: tdl <c|cx|codex|other_ai> [<second_ai>]"; return 1; }
  [[ -z ${TMUX:-} ]] && { echo "You must start tmux to use tdl."; return 1; }

  local current_dir="$PWD"
  local editor_pane="$TMUX_PANE"
  local ai="$1"
  local ai2="${2:-}"
  local ai_pane ai2_pane editor_cmd

  tmux rename-window -t "$editor_pane" "$(basename "$current_dir")"
  tmux split-window -v -p 15 -t "$editor_pane" -c "$current_dir"
  ai_pane=$(tmux split-window -h -p 30 -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')

  if [[ -n "$ai2" ]]; then
    ai2_pane=$(tmux split-window -v -t "$ai_pane" -c "$current_dir" -P -F '#{pane_id}')
    tmux send-keys -t "$ai2_pane" "$ai2" C-m
  fi

  tmux send-keys -t "$ai_pane" "$ai" C-m
  if command -v nvim >/dev/null 2>&1; then
    editor_cmd="nvim ."
  else
    editor_cmd="${EDITOR:-vim} ."
  fi
  tmux send-keys -t "$editor_pane" "$editor_cmd" C-m
  tmux select-pane -t "$editor_pane"
}

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
    echo "First launch - opening Claude Code for OAuth login..."
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
      echo "(first-run marker kept - OAuth doesn't look complete yet; will retry next zsh)"
    fi
    unset _claude_rc _authed _p
  fi
fi
BLOCK

# Marker-pair sanity check. If both markers exist (in order) -> in-place splice.
# If only one marker exists -> file is corrupted; back it up and write a fresh
# one (don't risk eating everything after a lone start marker).
# Use awk for counting: grep -c prints '0' AND exits non-zero on no match,
# so `grep -c ... || echo 0` produced "0\n0" - failing later integer compares.
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
  # No markers - append fresh block, preserve any existing content
  {
    if [ -f "$ZSHRC" ]; then cat "$ZSHRC"; echo ""; fi
    echo "$START_MARKER"
    cat "$MANAGED_TMP"
    echo "$END_MARKER"
  } > "$ZSHRC.new"
  mv "$ZSHRC.new" "$ZSHRC"
fi
rm -f "$MANAGED_TMP"
log "~/.zshrc managed block ready"

# ---------- 8. Claude Code ----------
log "Checking Claude Code (@anthropic-ai/claude-code)"
if ! have claude; then
  log "Installing Claude Code CLI"
  if ! retry 2 npm install -g @anthropic-ai/claude-code; then
    echo "FATAL: claude-code install failed. Try: npm i -g @anthropic-ai/claude-code" >&2
    exit 100
  fi
else
  log "Claude Code already installed; skipping npm install"
fi

# ---------- 9. OpenAI Codex CLI ----------
log "Checking OpenAI Codex CLI (@openai/codex)"
if ! have codex; then
  log "Installing OpenAI Codex CLI"
  if ! retry 2 npm install -g @openai/codex; then
    echo "FATAL: codex install failed. Try: npm i -g @openai/codex" >&2
    exit 100
  fi
else
  log "Codex already installed; skipping npm install"
fi

# ---------- 10. claude-mem (proper plugin install, not just the npm package) ----------
# Upstream docs explicitly say: DO NOT 'npm install -g claude-mem' - that only
# drops the SDK without registering the Claude Code hooks or starting the worker.
# `npx claude-mem install` is the canonical installer; it's interactive and asks
# for harness + provider. For this setup: Claude Code + Codex for harness,
# then Claude Code for provider.
log "Installing claude-mem (pick Claude Code + Codex for harness, then Claude Code for provider)"
CLAUDE_MEM_SETTINGS="$HOME/.claude-mem/settings.json"
CLAUDE_MEM_PLUGIN_DIR="$HOME/.claude/plugins/marketplaces/thedotmack"
if [ -f "$CLAUDE_MEM_SETTINGS" ]; then
  log "claude-mem already configured; skipping"
else
  if [ -d "$CLAUDE_MEM_PLUGIN_DIR" ]; then
    log "claude-mem plugin dir exists but settings are missing; re-running installer"
  fi
  if ! npx --yes claude-mem@latest install; then
    log "WARN: claude-mem install exited non-zero - run 'npx claude-mem install' manually"
    SKILL_FAILURES+=("claude-mem install failed")
  fi
fi

# ---------- 11. Claude skills (~/.claude/skills/) ----------
log "Setting up ~/.claude/skills/"
PERSONAL_SKILLS_DIR="$HOME/.claude/skills"
SKILL_REPO_CACHE="$HOME/.cache/install_claude/skill-repos"
mkdir -p "$PERSONAL_SKILLS_DIR" "$SKILL_REPO_CACHE"

install_gstack() {
  local name="$1" url="$2"
  local dest="$PERSONAL_SKILLS_DIR/$name"
  if [ -z "$url" ]; then
    log "  $name: SKIPPED (no repo URL)"
    return 0
  fi
  if [ -d "$dest/.git" ]; then
    if git -C "$dest" rev-parse --verify HEAD >/dev/null 2>&1; then
      log "  $name: already cloned (not auto-updated; run 'git -C $dest pull' to refresh)"
      return 0
    fi
    log "  $name: removing incomplete previous clone"
    rm -rf "$dest"
  fi
  if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
    log "  $name: WARN - $dest exists and is not a git repo. Skipping. Remove it manually to re-clone."
    SKILL_FAILURES+=("$name (existing non-git dir at $dest)")
    return 0
  fi
  # Empty placeholder dir? rmdir so clone can create it cleanly.
  [ -d "$dest" ] && rmdir "$dest" 2>/dev/null || true

  if retry 3 git clone --depth=1 "$url" "$dest"; then
    log "  $name: cloned"
    if [ "$SKIP_SKILL_SETUP" = "1" ]; then
      log "  $name: skipped upstream setup (--no-skill-setup)"
    else
      # Run upstream setup/install scripts if present.
      # SECURITY: this executes code from the cloned repo. You opted in by
      # listing the URL above. Run with --no-skill-setup to disable.
      if [ -x "$dest/setup" ]; then
        log "  $name: running ./setup (interactive - answer prompts or wait for timeout)"
        if ! ( cd "$dest" && ./setup ); then
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
    log "  $name: WARN - clone failed from $url"
    SKILL_FAILURES+=("$name <- $url (clone failed)")
  fi
}

clone_or_update_skill_repo() {
  local name="$1" url="$2" dest="$3"
  if [ -d "$dest/.git" ]; then
    if git -C "$dest" rev-parse --verify HEAD >/dev/null 2>&1; then
      log "  $name: cached repo already present; skipping git pull"
      return 0
    fi
    log "  $name: removing incomplete cached clone"
    rm -rf "$dest"
  elif [ -e "$dest" ]; then
    log "  $name: removing non-git cached path"
    rm -rf "$dest"
  fi

  if retry 3 git clone --depth=1 "$url" "$dest"; then
    log "  $name: cached clone ready"
    return 0
  fi

  log "  $name: WARN - clone failed from $url"
  SKILL_FAILURES+=("$name <- $url (clone failed)")
  return 1
}

cleanup_invisible_wrapper_clone() {
  local name="$1" expected="$2"
  local dest="$PERSONAL_SKILLS_DIR/$name"
  local remote=""
  if [ ! -d "$dest/.git" ] || [ -f "$dest/SKILL.md" ]; then
    return 0
  fi
  remote="$(git -C "$dest" config --get remote.origin.url 2>/dev/null || true)"
  case "$remote" in
    *"$expected"*)
      log "  $name: removing previous invisible wrapper clone from ~/.claude/skills"
      rm -rf "$dest"
      ;;
  esac
}

install_visible_skill_dir() {
  local src="$1" source_label="$2"
  local skill_name dest tmp
  if [ ! -f "$src/SKILL.md" ]; then
    return 1
  fi

  skill_name="$(basename "$src")"
  dest="$PERSONAL_SKILLS_DIR/$skill_name"
  tmp="$dest.tmp.$$"

  if [ -e "$dest" ]; then
    if [ -f "$dest/.claude-bootstrap-managed" ] && [ -f "$dest/SKILL.md" ]; then
      log "  /$skill_name: already installed; skipping copy"
      return 0
    elif [ -f "$dest/SKILL.md" ]; then
      log "  /$skill_name: exists and is not bootstrap-managed; leaving it alone"
      return 0
    fi
    log "  /$skill_name: WARN - path exists but is not a visible skill; skipping"
    SKILL_FAILURES+=("$skill_name (existing non-skill path at $dest)")
    return 0
  fi

  rm -rf "$tmp"
  mkdir -p "$tmp"
  if ( cd "$src" && tar --exclude='.git' -cf - . ) | ( cd "$tmp" && tar -xf - ); then
    {
      echo "source=$source_label"
      echo "installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$tmp/.claude-bootstrap-managed"
    rm -rf "$dest"
    mv "$tmp" "$dest"
    log "  /$skill_name: installed"
  else
    rm -rf "$tmp"
    log "  /$skill_name: WARN - copy failed from $src"
    SKILL_FAILURES+=("$skill_name (copy failed)")
  fi
}

install_skill_bundle() {
  local name="$1" url="$2" expected_remote="$3"
  local cache="$SKILL_REPO_CACHE/$name"
  local installed=0 roots=() root skill_md skill_dir

  cleanup_invisible_wrapper_clone "$name" "$expected_remote"
  if ! clone_or_update_skill_repo "$name" "$url" "$cache"; then
    return 0
  fi

  if [ -f "$cache/SKILL.md" ]; then
    install_visible_skill_dir "$cache" "$name"
    installed=$((installed + 1))
  fi

  roots=("$cache/skills" "$cache/.claude/skills")
  for root in "${roots[@]}"; do
    if [ ! -d "$root" ]; then
      continue
    fi
    while IFS= read -r -d '' skill_md; do
      skill_dir="$(dirname "$skill_md")"
      install_visible_skill_dir "$skill_dir" "$name"
      installed=$((installed + 1))
    done < <(find "$root" -mindepth 2 -maxdepth 2 -name SKILL.md -print0 | sort -z)
  done

  if [ "$installed" -eq 0 ]; then
    log "  $name: WARN - no visible SKILL.md files found in repo root, skills/, or .claude/skills/"
    SKILL_FAILURES+=("$name (no visible skills found)")
  else
    log "  $name: exposed $installed visible skill(s)"
  fi
}

# Canonical repos (verified May 2026 - change if upstream moves):
GSTACK_REPO="https://github.com/garrytan/gstack.git"
KARPATHY_REPO="https://github.com/forrestchang/andrej-karpathy-skills.git"
SUPERPOWERS_REPO="https://github.com/obra/superpowers.git"
MATT_POCOCK_REPO="https://github.com/mattpocock/skills.git"

install_gstack       "gstack"                 "$GSTACK_REPO"
install_skill_bundle "andrej-karpathy-skills" "$KARPATHY_REPO"     "andrej-karpathy-skills"
install_skill_bundle "superpowers"            "$SUPERPOWERS_REPO"  "obra/superpowers"
install_skill_bundle "matt-pocock-skills"     "$MATT_POCOCK_REPO"  "mattpocock/skills"

# Alternative install path for superpowers (via Claude Code marketplace, after OAuth):
#   /plugin install superpowers@claude-plugins-official

# ---------- 12. First-run marker (so .zshrc auto-launches claude on first interactive zsh) ----------
# Only create if claude is actually installed AND user isn't already logged in.
# Detection is heuristic - we check known credential paths. Proper file-vs-dir
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

# ---------- 13. Done - summary ----------
log "===== install.sh complete ====="
echo ""
echo "  Shell:      zsh + Pure prompt"
echo "  Node:       $(node --version 2>/dev/null || echo 'missing')"
echo "  Bun:        $(bun --version 2>/dev/null || echo 'missing')"
echo "  Chrome:     $(google-chrome --version 2>/dev/null || echo 'missing')"
echo "  Claude:     $(claude --version 2>/dev/null || echo 'missing')"
echo "  Codex:      $(codex --version 2>/dev/null || echo 'missing')"
if [ -f "$HOME/.claude-mem/settings.json" ]; then
  echo "  claude-mem: configured"
elif [ -d "$HOME/.claude/plugins/marketplaces/thedotmack" ]; then
  echo "  claude-mem: partial (plugin dir exists, settings missing)"
else
  echo "  claude-mem: missing"
fi
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
#   1..99      = N skill failures (partial - user can re-run to retry)
#   100+       = fatal (npm missing, claude install failed, etc.) - already exited above
n="${#SKILL_FAILURES[@]}"
[ "$n" -gt 99 ] && n=99
exit "$n"
