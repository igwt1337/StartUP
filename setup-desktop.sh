#!/usr/bin/env bash
#
# setup-desktop.sh
# ---------------------------------------------------------------------------
# Recreates the Xfce desktop look shown in the screenshot on Kali Linux,
# based on: https://github.com/ahmadhabibi14/dotfile
#
#   - Xfce4 + Xfwm4 with the "Habiboow" window border theme
#   - "Tokyonight-Dark-BL" GTK theme
#   - Plank dock with the matching Tokyo Night theme
#   - Alacritty terminal
#   - Neofetch + Cava configs shown in the terminals
#   - xfce4-genmon-plugin scripts (cpu/mem/disk/net/battery/datetime) for the
#     top panel, matching the little colored indicators in the screenshot
#
# IMPORTANT / HONESTY NOTE:
# The upstream repo ships the THEME FILES and the little panel/monitor
# SCRIPTS, but it does NOT ship an exported xfce4-panel layout (panel
# position, which genmon plugin goes where, whisker-menu style, etc.) or an
# icon theme. This script installs and wires up everything that CAN be
# scripted/automated. At the very end it prints the few manual steps
# (~2 minutes) needed in the Panel/Appearance GUI to finish matching the
# screenshot pixel-for-pixel (adding the genmon plugins to the panel and
# picking an icon theme you like).
#
# Usage:
#   chmod +x setup-desktop.sh
#   ./setup-desktop.sh
#
# Safe to re-run. Existing configs are backed up with a timestamp suffix.
# ---------------------------------------------------------------------------

set -euo pipefail

REPO_URL="https://github.com/ahmadhabibi14/dotfile.git"
WORK_DIR="$(mktemp -d)"
SRC="$WORK_DIR/dotfile"
BACKUP_DIR="$HOME/.dotfile-backup-$(date +%Y%m%d-%H%M%S)"
GTK_THEME="Tokyonight-Dark-BL"
WM_THEME="Habiboow"
PLANK_THEME="Habiboow"

log()  { printf '\033[1;36m[*]\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$1"; }

require_linux() {
    if [[ ! -f /etc/os-release ]] || ! grep -qiE 'kali|debian' /etc/os-release; then
        warn "This script targets Kali/Debian (apt-based). Continuing anyway, but package install may fail."
    fi
}

backup() {
    # backup <path-relative-to-home>
    local target="$HOME/$1"
    if [[ -e "$target" ]]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$1")"
        mv "$target" "$BACKUP_DIR/$1"
    fi
}

install_packages() {
    log "Updating apt (sudo password may be requested)..."
    sudo apt update

    # Install what we can from the normal repos. Don't abort the whole
    # script if one package is missing on this particular Kali mirror —
    # plank and neofetch are handled with fallbacks below regardless.
    local pkgs=(
        xfce4 xfce4-goodies xfconf
        alacritty
        thunar
        cava
        git curl wget
        lm-sensors
        fonts-jetbrains-mono fonts-noto-color-emoji
    )
    log "Installing base packages..."
    sudo apt install -y "${pkgs[@]}" || warn "Some base packages failed — continuing."

    install_plank
    install_neofetch
    ok "Package step finished."
}

install_plank() {
    if command -v plank >/dev/null 2>&1; then
        ok "plank already installed."
        return
    fi
    log "Trying to install plank from apt..."
    if sudo apt install -y plank 2>/dev/null; then
        ok "plank installed via apt."
        return
    fi
    warn "plank not found in your current apt sources. Enabling contrib/non-free and retrying..."
    if [[ -f /etc/apt/sources.list ]]; then
        sudo sed -i -E 's/^(deb .*kali-rolling )main(.*)$/\1main contrib non-free non-free-firmware\2/' /etc/apt/sources.list 2>/dev/null || true
    fi
    sudo apt update || true
    if sudo apt install -y plank 2>/dev/null; then
        ok "plank installed via apt (after enabling contrib/non-free)."
        return
    fi
    warn "plank still unavailable via apt — building it from source instead (takes a couple of minutes)."
    local build_deps=(build-essential meson ninja-build valac gnome-common intltool
        libgtk-3-dev libgee-0.8-dev libwnck-3-dev libbamf3-dev
        libcairo2-dev libpango1.0-dev libglib2.0-dev libgnome-menu-3-dev)
    sudo apt install -y "${build_deps[@]}" || { warn "Could not install plank build deps — skipping plank entirely."; return; }
    local pdir="$WORK_DIR/plank-src"
    if git clone --depth=1 https://github.com/ricotz/plank.git "$pdir" 2>/dev/null || \
       git clone --depth=1 https://gitlab.gnome.org/vala-panel-project/plank.git "$pdir" 2>/dev/null; then
        (cd "$pdir" && meson setup build --prefix=/usr && ninja -C build && sudo ninja -C build install) \
            && ok "plank built and installed from source." \
            || warn "Building plank from source failed — you can add a dock later with 'xfce4-docklike-plugin' instead."
    else
        warn "Could not fetch plank source — you can add a dock later with 'xfce4-docklike-plugin' instead."
    fi
}

install_neofetch() {
    if command -v neofetch >/dev/null 2>&1; then
        ok "neofetch already installed."
        return
    fi
    log "Trying to install neofetch from apt..."
    if sudo apt install -y neofetch 2>/dev/null; then
        ok "neofetch installed via apt."
        return
    fi
    warn "neofetch has been archived upstream and removed from Kali's repos. Installing the original script directly instead."
    if sudo curl -fsSL -o /usr/local/bin/neofetch \
        https://raw.githubusercontent.com/dylanaraps/neofetch/master/neofetch; then
        sudo chmod +x /usr/local/bin/neofetch
        ok "neofetch installed to /usr/local/bin/neofetch."
    else
        warn "Could not fetch neofetch script — falling back to fastfetch."
        sudo apt install -y fastfetch 2>/dev/null && ok "fastfetch installed as a substitute (note: it uses a different config format than the repo's neofetch config)." \
            || warn "fastfetch also unavailable — skipping the system-info tool."
    fi
}

clone_repo() {
    log "Cloning dotfiles repo..."
    git clone --depth=1 "$REPO_URL" "$SRC"
    ok "Cloned to $SRC"
}

deploy_configs() {
    log "Backing up your current configs to $BACKUP_DIR ..."
    mkdir -p "$BACKUP_DIR"
    backup ".config/alacritty"
    backup ".config/cava"
    backup ".config/neofetch"
    backup ".config/gtk-3.0/gtk.css"
    backup ".genmon-plugin"
    backup ".local/share/plank/themes/$PLANK_THEME"
    ok "Backup done (nothing lost)."

    log "Installing Alacritty config..."
    mkdir -p "$HOME/.config/alacritty"
    cp -r "$SRC/.config/alacritty/." "$HOME/.config/alacritty/"

    log "Installing Cava config..."
    mkdir -p "$HOME/.config/cava"
    cp -r "$SRC/.config/cava/." "$HOME/.config/cava/"

    log "Installing Neofetch config..."
    mkdir -p "$HOME/.config/neofetch"
    cp -r "$SRC/.config/neofetch/." "$HOME/.config/neofetch/"

    log "Installing gtk.css tweaks..."
    mkdir -p "$HOME/.config/gtk-3.0"
    cp "$SRC/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-3.0/gtk.css"

    log "Installing GTK / Xfwm4 themes ($GTK_THEME, $WM_THEME)..."
    mkdir -p "$HOME/.themes"
    cp -r "$SRC/.themes/." "$HOME/.themes/"

    log "Installing Plank theme..."
    mkdir -p "$HOME/.local/share/plank/themes"
    cp -r "$SRC/.local/share/plank/themes/." "$HOME/.local/share/plank/themes/"

    log "Installing panel monitor scripts (genmon)..."
    mkdir -p "$HOME/.genmon-plugin"
    cp -r "$SRC/.genmon-plugin/." "$HOME/.genmon-plugin/"
    chmod +x "$HOME"/.genmon-plugin/*.sh

    log "Copying wallpapers to ~/Pictures/Wallpapers ..."
    mkdir -p "$HOME/Pictures/Wallpapers"
    cp -r "$SRC/images/wallpaper/." "$HOME/Pictures/Wallpapers/" 2>/dev/null || true

    ok "All files deployed."
}

apply_xfconf_settings() {
    log "Applying Xfce theme settings via xfconf..."

    xfconf-query -c xsettings -p /Net/ThemeName -s "$GTK_THEME" --create -t string 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/theme -s "$WM_THEME" --create -t string 2>/dev/null || true

    # Pick the first wallpaper found and set it on every monitor/workspace property
    local wallpaper
    wallpaper="$(find "$HOME/Pictures/Wallpapers" -maxdepth 1 -type f | head -n1 || true)"
    if [[ -n "${wallpaper:-}" ]]; then
        for prop in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep last-image); do
            xfconf-query -c xfce4-desktop -p "$prop" -s "$wallpaper" 2>/dev/null || true
        done
        ok "Wallpaper set to $(basename "$wallpaper")."
    else
        warn "No wallpaper found to set automatically — pick one from ~/Pictures/Wallpapers manually."
    fi

    ok "GTK theme -> $GTK_THEME, Window border theme -> $WM_THEME."
}

setup_plank() {
    log "Configuring Plank..."
    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/plank.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Plank
Exec=plank
Icon=plank
Comment=Dock launcher
X-GNOME-Autostart-enabled=true
EOF
    # Set Plank's theme via dconf if available
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set net.launchpad.plank.dock:/net/launchpad/plank/docks/dock1/ theme "$PLANK_THEME" 2>/dev/null || true
    fi
    ok "Plank set to autostart with theme '$PLANK_THEME'."
    warn "Right-click the Plank dock -> Preferences to pin your favorite apps (Firefox, Files, terminal, etc.) like in the screenshot."
}

set_default_terminal() {
    log "Setting Alacritty as the default terminal..."
    if command -v alacritty >/dev/null 2>&1; then
        sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/alacritty 50 2>/dev/null || true
        xfconf-query -c xfce4-session -p /general/TerminalEmulator -s "alacritty" --create -t string 2>/dev/null || true
        ok "Alacritty set as default terminal."
    else
        warn "alacritty binary not found on PATH — check the apt install step."
    fi
}

print_manual_steps() {
    cat <<EOF

=================================================================
  DONE with the automatable part. Log out and back in (or run
  'xfce4-panel -r' / 'plank &') to see the changes take effect.
=================================================================

The upstream repo doesn't ship an exported panel layout or an icon
theme, so finish the look with these quick manual steps:

  1. Icon theme (the colored folder icons in the screenshot aren't
     in the repo). Settings > Appearance > Icons — try installing
     one you like, e.g.:
         sudo apt install papirus-icon-theme
     then select it there.

  2. Panel indicators (CPU/RAM/disk/net/battery like the top bar):
     Right-click the top panel > Panel > Add New Items > "Generic
     Monitor". Add one per stat, then in each one's Properties set:
         Command: ~/.genmon-plugin/cpu-panel.sh   (or memory-, disk-,
                  network-, battery-, datetime-panel.sh)
         Period:  1-2 seconds
     Repeat for each script in ~/.genmon-plugin/.

  3. Confirm in Settings > Window Manager that the "$WM_THEME" theme
     is selected (it should already be, from this script).

  4. Confirm in Settings > Appearance that "$GTK_THEME" is selected.

  5. Terminal system-info screens are neofetch and cava — just run
     'neofetch' and 'cava' in Alacritty to see them.

Your old configs (if any existed) were backed up to:
  $BACKUP_DIR
EOF
}

main() {
    require_linux
    install_packages
    clone_repo
    deploy_configs
    apply_xfconf_settings
    setup_plank
    set_default_terminal
    print_manual_steps
    rm -rf "$WORK_DIR"
}

main "$@"
