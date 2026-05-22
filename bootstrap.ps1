#Requires -RunAsAdministrator
# ============================================================================
# WSL2 Ubuntu 22.04 dev box - Windows-side bootstrap
# Run ONCE in an Administrator PowerShell window:
#
#   Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
#
# Optional args:
#   -Username yolan        # Linux username (defaults to your Windows user, lowercased)
#   -Distro   Ubuntu-22.04 # WSL distro name
# ============================================================================

[CmdletBinding()]
param(
  [string]$Distro   = "Ubuntu-22.04",
  [string]$Username = ($env:USERNAME.ToLower() -replace '[^a-z0-9_-]', ''),
  # If set, existing Ubuntu* distros are wiped WITHOUT the interactive
  # "WIPE" confirmation. DANGEROUS - only use this for automation/CI when
  # you've already confirmed the box has no data you care about.
  [switch]$CleanInstall
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Log($msg, $color = "Cyan") {
  Write-Host ""
  Write-Host "==> $msg" -ForegroundColor $color
}
function Warn($msg) { Write-Host "    ! $msg" -ForegroundColor Yellow }
function Die ($msg) { Write-Host "    X $msg" -ForegroundColor Red; exit 1 }

# Strip CR bytes so any here-string we hand to bash inside WSL has pure LF endings.
# Git on Windows defaults to core.autocrlf=true, which CRLF-ifies any text file
# on checkout. Bash chokes on `set -e\r` and on heredoc delimiters that don't
# match because of trailing \r. .gitattributes prevents this on FUTURE clones;
# this function fixes it at runtime for clones already done.
function ConvertTo-LfText {
  param([string]$s)
  return ($s -replace "`r`n", "`n") -replace "`r", "`n"
}

# Native-exe call helper. $ErrorActionPreference="Stop" does NOT trap non-zero
# exits from native binaries (wsl.exe, dism.exe, etc.) - only from PowerShell
# cmdlets. We have to check $LASTEXITCODE ourselves every time.
function Invoke-Native {
  param([string]$Label, [scriptblock]$Block, [int[]]$AllowedExitCodes = @(0))
  $oldEap = $ErrorActionPreference
  try {
    # Windows PowerShell turns native stderr (wsl.exe, dism.exe, etc.) into
    # NativeCommandError records. With ErrorActionPreference=Stop, harmless WSL
    # warnings can otherwise abort before we inspect $LASTEXITCODE.
    $ErrorActionPreference = "Continue"
    & $Block
    $rc = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $oldEap
  }
  if ($AllowedExitCodes -notcontains $rc) {
    Die "$Label failed (exit $rc). Stopping bootstrap; rerun after fixing."
  }
  return $rc
}

function Invoke-NativeCaptured {
  param([scriptblock]$Block)
  $oldEap = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    $output = & $Block 2>&1
    $rc = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $oldEap
  }
  $text = (($output | ForEach-Object { $_.ToString() }) -join "`n")
  return [pscustomobject]@{ ExitCode = $rc; Output = $text }
}

# ---------- 0. Validate args (Linux username regex; refuses injection chars) ----------
if ([string]::IsNullOrWhiteSpace($Username)) {
  Die "Could not derive a valid Linux username. Pass -Username <name>."
}
if ($Username -notmatch '^[a-z_][a-z0-9_-]{0,30}$') {
  Die "Invalid Linux username '$Username'. Must be: lowercase letter or '_' at start, then [a-z0-9_-], max 31 chars. Override with -Username <name>."
}
if ($Distro -notmatch '^[A-Za-z0-9._-]+$') {
  Die "Invalid distro name '$Distro'. Letters/digits/dot/underscore/dash only."
}

# ---------- 1. Detect / enable WSL ----------
# IMPORTANT: on modern Win10/11, `wsl --install` ships WSL as a Microsoft Store
# package and does NOT flip the legacy optional-feature flags. A fully working
# WSL machine can therefore show both features as 'Disabled'. If we trust those
# flags blindly, we'll loop forever asking for reboots on every run.
# Truth source: does `wsl --status` actually exit 0? If yes, WSL works, period.
function Test-WslWorks {
  $cmd = Get-Command wsl.exe -ErrorAction SilentlyContinue
  if (-not $cmd) { return $false }
  # --status is non-interactive, fast, exits 0 only when WSL is functional.
  $result = Invoke-NativeCaptured { & $cmd.Source --status }
  return ($result.ExitCode -eq 0)
}

if (Test-WslWorks) {
  Log "WSL is already functional (skipping optional-feature enablement)"
} else {
  Log "WSL not yet functional - checking optional features"
  $needReboot = $false
  $features = @(
    @{ Name = 'Microsoft-Windows-Subsystem-Linux'; Pretty = 'WSL' },
    @{ Name = 'VirtualMachinePlatform';            Pretty = 'Virtual Machine Platform' }
  )
  foreach ($f in $features) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $f.Name).State
    switch ($state) {
      'Enabled'        { } # nothing to do
      'EnablePending'  { Warn "$($f.Pretty) is already EnablePending - reboot needed"; $needReboot = $true }
      'Disabled'       {
        Log "Enabling $($f.Pretty)"
        Enable-WindowsOptionalFeature -Online -FeatureName $f.Name -All -NoRestart | Out-Null
        $needReboot = $true
      }
      'DisablePending' {
        Warn "$($f.Pretty) is mid-disable; re-enabling and queuing for reboot"
        Enable-WindowsOptionalFeature -Online -FeatureName $f.Name -All -NoRestart | Out-Null
        $needReboot = $true
      }
      default { Warn "$($f.Pretty) is in unexpected state '$state' - continuing anyway" }
    }
  }
  if ($needReboot) {
    Write-Host ""
    Write-Host "  WSL features need activation - REBOOT REQUIRED before they take effect." -ForegroundColor Yellow
    Write-Host "  Reboot Windows, then re-run this script (see README - 'Re-run' command)." -ForegroundColor Yellow
    Write-Host "  Everything done so far is idempotent." -ForegroundColor Yellow
    Write-Host ""
    exit 0
  }
  # Features were already Enabled but wsl.exe still failed. Step 2's `wsl --update`
  # may fix that by installing the WSL Store package + kernel. Continue.
}

# ---------- 2. WSL update + default version ----------
Log "Updating WSL kernel (best-effort)"
try {
  $updateResult = Invoke-NativeCaptured { wsl --update --web-download }
  if ($updateResult.Output) { Write-Host $updateResult.Output }
  if ($updateResult.ExitCode -ne 0) { Warn "wsl --update exited $($updateResult.ExitCode) (often fine on locked-down corp machines)" }
} catch {
  Warn "wsl --update failed (often fine on locked-down corp machines): $_"
}
Log "Setting WSL default version to 2"
$setVersion = Invoke-NativeCaptured { wsl --set-default-version 2 }
if ($setVersion.ExitCode -ne 0) { Die "wsl --set-default-version 2 failed (exit $($setVersion.ExitCode)). Check WSL install/update output above." }

# ---------- 3. Install Ubuntu-22.04 (no auto-launch) ----------
# Normalize `wsl -l -q` output: strips NULs (UTF-16 artifact) and CRs.
function Get-InstalledDistros {
  $result = Invoke-NativeCaptured { wsl -l -q }
  $raw = $result.Output
  ($raw -replace "`0","" -split "`r?`n") | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }
}

# 3a. Detect existing Ubuntu* distros. Normal reruns never prompt to destroy
# anything; they reuse $Distro if present and apply missing/bootstrap state
# idempotently. -CleanInstall is the explicit destructive path for automation.
$existingUbuntu = @(Get-InstalledDistros | Where-Object { $_ -match '^Ubuntu' })
if ($existingUbuntu.Count -gt 0) {
  Write-Host ""
  Write-Host "Detected existing WSL Ubuntu distro(s):" -ForegroundColor Yellow
  foreach ($d in $existingUbuntu) { Write-Host "    - $d" -ForegroundColor Yellow }
  Write-Host ""

  $shouldWipe = $false
  if ($CleanInstall) {
    Warn "-CleanInstall flag set: wiping listed distros without prompting."
    $shouldWipe = $true
  }

  if ($shouldWipe) {
    foreach ($d in $existingUbuntu) {
      Log "Unregistering $d (PERMANENT DELETE)" "Red"
      $null = Invoke-NativeCaptured { wsl --terminate $d }
      $unregister = Invoke-NativeCaptured { wsl --unregister $d }
      if ($unregister.Output) { Write-Host $unregister.Output }
      if ($unregister.ExitCode -ne 0) { Die "wsl --unregister $d failed (exit $($unregister.ExitCode)). Aborting before partial state can cause confusion." }
    }
    Log "Wipe complete. Continuing with clean install of $Distro." "Green"
    # Re-query so subsequent checks see the fresh state.
    $existingUbuntu = @()
  } else {
    if ($existingUbuntu -contains $Distro) {
      Log "$Distro already exists - reusing it and applying any missing bootstrap state." "Cyan"
    } else {
      Log "Keeping existing Ubuntu distros. $Distro will be installed alongside them if missing." "Cyan"
    }
  }
}

if ((Get-InstalledDistros) -notcontains $Distro) {
  Log "Installing $Distro (no launch)"
  $installResult = Invoke-NativeCaptured { wsl --install -d $Distro --no-launch }
  if ($installResult.Output) { Write-Host $installResult.Output }
  if ($installResult.ExitCode -ne 0) { Die "wsl --install -d $Distro failed (exit $($installResult.ExitCode)). Check the output above; common cause: distro name unsupported on this WSL build. Try 'wsl --list --online' to see valid names." }
} else {
  Log "$Distro already installed (reusing existing)"
}

# Wait for registration
$tries = 0
while ((Get-InstalledDistros) -notcontains $Distro) {
  Start-Sleep -Seconds 2
  if (++$tries -gt 60) { Die "$Distro did not register within 2 minutes." }
}

# ---------- 4. First-launch init - fresh WSL distros need OOBE before root provisioning works ----------
Log "Ensuring $Distro is initialized (this may take ~10s the first time)"
$initTries = 0
while ($true) {
  $probe = Invoke-NativeCaptured { wsl -d $Distro -u root -- bash -c "echo ok" }
  if ($probe.ExitCode -eq 0 -and $probe.Output -match "ok") { break }
  if (++$initTries -gt 30) { Die "$Distro failed to initialize after 60s. Try: wsl --terminate $Distro ; wsl --unregister $Distro ; rerun." }
  Start-Sleep -Seconds 2
}

# ---------- 5. Create Linux user with passwordless sudo (as root) ----------
Log "Provisioning Linux user '$Username' inside $Distro"
# PowerShell expands $Username here; bash sees fully-resolved values. Username
# was regex-validated above, so it's safe to interpolate.
$bashUser = @"
set -e
if ! id -u '$Username' >/dev/null 2>&1; then
  useradd -m -s /bin/bash '$Username'
  passwd -d '$Username'
  usermod -aG sudo '$Username'
fi
echo '$Username ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-$Username-nopasswd
chmod 0440 /etc/sudoers.d/99-$Username-nopasswd
mkdir -p /usr/lib/binfmt.d
printf ':WSLInterop:M::MZ::/init:PF\n' > /usr/lib/binfmt.d/WSLInterop.conf
cat > /etc/wsl.conf <<'WSLCONF'
[user]
default=$Username
[boot]
systemd=true
[interop]
enabled=true
appendWindowsPath=true
WSLCONF
"@
$bashUser = ConvertTo-LfText $bashUser
$provision = Invoke-NativeCaptured { wsl -d $Distro -u root -- bash -c $bashUser }
if ($provision.Output) { Write-Host $provision.Output }
if ($provision.ExitCode -ne 0) { Die "User provisioning inside $Distro failed (wsl exit $($provision.ExitCode)). See output above." }

# Belt-and-suspenders: also try the legacy per-distro launcher exe (ubuntu2204.exe,
# ubuntu.exe). These exist only on Microsoft-Store-distribution installs from the
# old AppX days. On modern Store-package WSL the exes are absent and /etc/wsl.conf
# (written above) is the canonical source of truth; the loop silently no-ops then,
# which is correct.
$launcherSet = $false
foreach ($l in @("ubuntu2204.exe","ubuntu.exe")) {
  $cmd = Get-Command $l -ErrorAction SilentlyContinue
  if ($cmd) { & $cmd.Source config --default-user $Username 2>$null | Out-Null; $launcherSet = $true; break }
}
if (-not $launcherSet) {
  Log "(no legacy launcher.exe found - relying on /etc/wsl.conf for default user)"
}

# ---------- 6. Default WSL distro ----------
Log "Setting $Distro as default WSL distro"
$setDefault = Invoke-NativeCaptured { wsl --set-default $Distro }
if ($setDefault.Output) { Write-Host $setDefault.Output }
if ($setDefault.ExitCode -ne 0) { Die "wsl --set-default $Distro failed (exit $($setDefault.ExitCode))." }

# Terminate so wsl.conf takes effect on next launch
$null = Invoke-NativeCaptured { wsl --terminate $Distro }

# ---------- 7. Copy install.sh into Ubuntu ----------
$installSh = Join-Path $PSScriptRoot "install.sh"
if (-not (Test-Path $installSh)) {
  Die "install.sh not found beside bootstrap.ps1. Both files must be in the same folder."
}
Log "Copying install.sh into ~$Username/install.sh"
# Avoid PowerShell-to-bash quoting and stdin entirely. Copy through the WSL
# filesystem share as UTF-8/LF, then run it via `bash ~/install.sh` below so
# executable bits do not matter.
$startUser = Invoke-NativeCaptured { wsl -d $Distro -u $Username -- true }
if ($startUser.Output) { Write-Host $startUser.Output }
if ($startUser.ExitCode -ne 0) { Die "Failed to start $Distro before copying install.sh (wsl exit $($startUser.ExitCode))" }

Log "Verifying passwordless sudo for '$Username'"
$sudoCheck = Invoke-NativeCaptured { wsl -d $Distro -u $Username -- sudo -n true }
if ($sudoCheck.Output) { Write-Host $sudoCheck.Output }
if ($sudoCheck.ExitCode -ne 0) { Die "Passwordless sudo is not working for '$Username' inside $Distro (wsl/sudo exit $($sudoCheck.ExitCode))." }

$installText = ConvertTo-LfText ([IO.File]::ReadAllText($installSh))
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
$copyError = $null
$installDest = $null
$linuxHome = "/home/$Username"
$wslRoots = @(('\\wsl$\' + $Distro), ('\\wsl.localhost\' + $Distro))
for ($copyTry = 1; $copyTry -le 10 -and -not $installDest; $copyTry++) {
  foreach ($root in $wslRoots) {
    $wslHomePath = Join-Path (Join-Path $root "home") $Username
    if (-not (Test-Path $wslHomePath)) {
      $copyError = "WSL home path not found yet: $wslHomePath"
      continue
    }
    $candidate = Join-Path $wslHomePath "install.sh"
    try {
      [IO.File]::WriteAllText($candidate, $installText, $utf8NoBom)
      if ((Test-Path $candidate) -and ((Get-Item $candidate).Length -gt 0)) {
        $installDest = $candidate
        break
      }
    } catch {
      $copyError = $_
    }
  }
  if (-not $installDest) { Start-Sleep -Seconds 1 }
}
if (-not $installDest) {
  Die ("Failed to copy install.sh into WSL via \\wsl`$ or \\wsl.localhost. Last error: {0}" -f $copyError)
}
$copyCheck = Invoke-NativeCaptured { wsl -d $Distro -u $Username -- test -s "$linuxHome/install.sh" }
if ($copyCheck.Output) { Write-Host $copyCheck.Output }
if ($copyCheck.ExitCode -ne 0) { Die "Copied install.sh is not readable inside WSL (wsl exit $($copyCheck.ExitCode))" }

# ---------- 8. Run install.sh inside Ubuntu as the user ----------
Log "Running install.sh inside $Distro (packages, zsh, Claude, skills - takes several minutes)"
$installResult = Invoke-NativeCaptured { wsl -d $Distro -u $Username --cd $linuxHome -- bash -lc "bash ~/install.sh" }
if ($installResult.Output) { Write-Host $installResult.Output }
$installRc = $installResult.ExitCode
# install.sh exit convention: 0=ok, 1-99=N skill failures (warn, continue),
# 100+=fatal (die, abort the rest of bootstrap including the Claude auto-launch).
if ($installRc -ge 100) {
  Die "install.sh reported a FATAL error (exit $installRc). See output above. Aborting before launching Claude."
}
if ($installRc -gt 0) {
  Warn "install.sh reported $installRc skill failure(s). Bootstrap will continue, but re-run install.sh inside WSL to retry."
}

# ---------- 9. FiraCode Nerd Font (ligatures!) ----------
Log "Installing FiraCode Nerd Font (ligatures included)"
try {
  $fontDir = Join-Path $env:TEMP "FiraCodeNF"
  $fontZip = "$fontDir.zip"
  if (-not (Test-Path $fontDir)) {
    Invoke-WebRequest -Uri "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip" `
                      -OutFile $fontZip -UseBasicParsing
    Expand-Archive -Force $fontZip $fontDir
    Remove-Item $fontZip -ErrorAction SilentlyContinue
  }
  $shellApp = New-Object -ComObject Shell.Application
  $fontsFolder = $shellApp.Namespace(0x14)
  if (-not $fontsFolder) { throw "Could not open Windows Fonts shell namespace" }
  $installedCount = 0
  Get-ChildItem $fontDir -Filter "*.ttf" -File | ForEach-Object {
    $already = Test-Path (Join-Path "$env:WINDIR\Fonts" $_.Name)
    if (-not $already) {
      $fontsFolder.CopyHere($_.FullName, 0x10)  # 0x10 = no-confirm
      $installedCount++
    }
  }
  Write-Host "    Installed $installedCount new font file(s)"
  # Give the COM font installer a moment to actually register the fonts before WT reads them
  if ($installedCount -gt 0) { Start-Sleep -Seconds 3 }
} catch {
  Warn "FiraCode Nerd Font install failed/skipped: $_"
}

# ---------- 10. Windows Terminal: font + start-in-home (safe parse, backup-restore on failure) ----------
# Probe all three known WT package names. Same class of "trust the truth, not
# the flag" fix as the WSL feature detection above. Stable wins if multiple
# are installed (most users' default).
$wtCandidates = @(
  "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
  "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
  "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalCanary_8wekyb3d8bbwe\LocalState\settings.json"
)
$wtSettings = $wtCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$wtPatched = $false
if ($wtSettings) {
  $wtFlavor = if ($wtSettings -match 'WindowsTerminalPreview') { 'Preview' }
              elseif ($wtSettings -match 'WindowsTerminalCanary') { 'Canary' }
              else { 'Stable' }
  Log "Detected Windows Terminal: $wtFlavor"
  Log "Patching Windows Terminal settings.json"
  $bak = "$wtSettings.bak.$(Get-Date -f yyyyMMddHHmmss)"
  Copy-Item $wtSettings $bak
  try {
    $raw = Get-Content $wtSettings -Raw
    # Conservative JSONC stripper: block comments + whole-line // comments + trailing commas.
    # We deliberately do NOT touch inline `//` because URLs in strings ("https://...") would
    # be corrupted. If the user has inline comments, parse will fail and we restore the backup.
    $clean = $raw -replace '/\*[\s\S]*?\*/', ''
    $clean = ($clean -split "`n" | ForEach-Object { $_ -replace '^\s*//.*$','' }) -join "`n"
    $clean = $clean -replace ',(\s*[}\]])', '$1'
    $json  = $clean | ConvertFrom-Json

    if (-not $json.PSObject.Properties['profiles']) {
      $json | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{ list = @() }) -Force
    }
    if (-not $json.profiles.PSObject.Properties['defaults']) {
      $json.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    function Set-WtProfileAppearance($profile) {
      $profile | Add-Member -NotePropertyName colorScheme -NotePropertyValue "Campbell" -Force
      $profile | Add-Member -NotePropertyName background  -NotePropertyValue "#0C0C0C" -Force
      $profile | Add-Member -NotePropertyName foreground  -NotePropertyValue "#CCCCCC" -Force
      $profile | Add-Member -NotePropertyName cursorColor -NotePropertyValue "#FFFFFF" -Force
      $profile | Add-Member -NotePropertyName useAcrylic  -NotePropertyValue $false -Force
      $profile | Add-Member -NotePropertyName opacity     -NotePropertyValue 100 -Force
    }
    # "FiraCode Nerd Font Mono" - single-cell glyphs, the variant terminals want.
    # The plain "FiraCode Nerd Font" family renders icons 2 cells wide and can
    # nudge column alignment in Powerline-style prompts.
    $font = [pscustomobject]@{ face = "FiraCode Nerd Font Mono"; size = 11 }
    $json.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue $font -Force
    Set-WtProfileAppearance $json.profiles.defaults

    $profileList = $null
    if ($json.profiles.PSObject.Properties['list']) { $profileList = $json.profiles.list }
    if ($profileList) {
      $ubuntu = $profileList | Where-Object { $_ -and $_.PSObject.Properties['name'] -and ($_.name -like "*$Distro*") } | Select-Object -First 1
      if ($ubuntu) {
        $ubuntu | Add-Member -NotePropertyName commandline       -NotePropertyValue "wsl.exe -d `"$Distro`" --cd $linuxHome -- zsh -l" -Force
        $ubuntu | Add-Member -NotePropertyName startingDirectory -NotePropertyValue "\\wsl$\$Distro\home\$Username"          -Force
        Set-WtProfileAppearance $ubuntu
        if ($ubuntu.PSObject.Properties['guid']) { $json.defaultProfile = $ubuntu.guid }
      } else {
        Warn "No '$Distro' profile found in Windows Terminal - open WT once to let it auto-detect."
      }
    } else {
      Warn "Windows Terminal has no profile list yet. Font default applied; profile-detection skipped."
    }

    ($json | ConvertTo-Json -Depth 64) | Set-Content $wtSettings -Encoding utf8
    $wtPatched = $true
  } catch {
    Warn "Windows Terminal settings.json couldn't be safely parsed (likely has inline // comments or trailing JSONC). Restored backup: $bak"
    Copy-Item $bak $wtSettings -Force
    Write-Host "    Manual steps to apply the same changes:" -ForegroundColor Yellow
    Write-Host "      1. Open WT -> Settings -> Profiles -> Defaults -> Appearance -> Font face: 'FiraCode Nerd Font Mono'" -ForegroundColor Yellow
    Write-Host "      2. In Appearance, set Color scheme: Campbell, Background: #0C0C0C, Acrylic: off" -ForegroundColor Yellow
    Write-Host "      3. Set default profile to '$Distro'" -ForegroundColor Yellow
    Write-Host "      4. In the '$Distro' profile, set Command line: wsl.exe -d $Distro --cd $linuxHome -- zsh -l" -ForegroundColor Yellow
    Write-Host "      5. Starting directory: \\wsl`$\$Distro\home\$Username" -ForegroundColor Yellow
  }
} else {
  Warn "Windows Terminal not installed - skipping settings patch."
  Warn "Install it from the Microsoft Store for the best experience (font ligatures, tabs)."
}

# ---------- 11. Desktop shortcut ----------
Log "Creating desktop shortcut"
$desktop = [Environment]::GetFolderPath("Desktop")
$shortcut = Join-Path $desktop "$Distro (zsh).lnk"
$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($shortcut)
$wt = Get-Command wt.exe -ErrorAction SilentlyContinue
if ($wt) {
  $sc.TargetPath = $wt.Source
  $sc.Arguments  = "new-tab wsl.exe -d `"$Distro`" --cd $linuxHome -- zsh -l"
} else {
  $sc.TargetPath = "wsl.exe"
  $sc.Arguments  = "-d `"$Distro`" --cd $linuxHome -- zsh -l"
}
$sc.WorkingDirectory = $env:USERPROFILE
$sc.IconLocation     = "wsl.exe,0"
$sc.Description      = "Open $Distro in zsh, in home dir"
$sc.Save()

$claudeShortcut = Join-Path $desktop "Claude Code (auto).lnk"
$claudeSc = $wsh.CreateShortcut($claudeShortcut)
$claudeCommand = "claude --permission-mode bypassPermissions"
if ($wt) {
  $claudeSc.TargetPath = $wt.Source
  $claudeSc.Arguments  = "new-tab --title `"Claude Code Auto`" wsl.exe -d `"$Distro`" --cd $linuxHome -- zsh -ic `"$claudeCommand`""
} else {
  $claudeSc.TargetPath = "wsl.exe"
  $claudeSc.Arguments  = "-d `"$Distro`" --cd $linuxHome -- zsh -ic `"$claudeCommand`""
}
$claudeSc.WorkingDirectory = $env:USERPROFILE
$claudeSc.IconLocation     = "wsl.exe,0"
$claudeSc.Description      = "Open Claude Code in $Distro with bypass permissions"
$claudeSc.Save()

# ---------- 12. Launch first session -> lands in claude OAuth ----------
Log "Opening a fresh terminal - zsh will launch Claude Code for OAuth automatically" "Green"
Start-Sleep -Seconds 1
if ($wt) {
  Start-Process $wt.Source -ArgumentList @("new-tab","wsl.exe","-d",$Distro,"--cd",$linuxHome,"--","zsh","-l")
} else {
  Start-Process "wsl.exe" -ArgumentList @("-d",$Distro,"--cd",$linuxHome,"--","zsh","-l")
}

Log "DONE." "Green"
Write-Host ""
Write-Host "  Desktop shortcut: $shortcut" -ForegroundColor Green
Write-Host "  Claude auto:      $claudeShortcut" -ForegroundColor Green
Write-Host "  Linux user:       $Username  (passwordless sudo, empty password)" -ForegroundColor Green
Write-Host "  Default distro:   $Distro" -ForegroundColor Green
if (-not $wtPatched -and $wtSettings -and (Test-Path $wtSettings)) {
  Write-Host "  WT settings:      NOT patched - see manual steps printed above." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  If Claude Code doesn't auto-launch, open the shortcut and run: claude" -ForegroundColor Yellow
Write-Host "  To launch Claude in bypass mode later, open: $claudeShortcut" -ForegroundColor Yellow
Write-Host ""
