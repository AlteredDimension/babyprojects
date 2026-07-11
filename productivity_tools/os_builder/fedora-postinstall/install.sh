#!/usr/bin/env bash
# Fedora Minimal Post-Install — replicating alt's NixOS (breachd) setup
# Run as your normal user (script uses sudo where needed)
set -euo pipefail

USER_NAME="alt"
HOME_DIR="/home/$USER_NAME"
CONFIG_DIR="$HOME_DIR/.config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Colors for output ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*"; }

# ─── Preflight ───────────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
    error "Don't run as root. Run as $USER_NAME — script uses sudo internally."
    exit 1
fi

info "Starting Fedora post-install setup..."

# ─── 1. RPM Fusion (needed for NVIDIA, codecs) ──────────────────────
info "Enabling RPM Fusion..."
sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
sudo dnf makecache

# ─── 2. NVIDIA Drivers ──────────────────────────────────────────────
info "Installing NVIDIA drivers..."
sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
# Wait for kmod to build (important on first install)
warn "NVIDIA kmod may take a few minutes to build after reboot."

# ─── 3. Hyprland + Wayland Core ─────────────────────────────────────
info "Installing Hyprland and Wayland core..."
sudo dnf install -y \
    hyprland \
    hyprlock \
    hyprpaper \
    xdg-desktop-portal-hyprland \
    xdg-desktop-portal-gtk \
    uwsm

# ─── 4. Display Manager (greetd + tuigreet) ─────────────────────────
info "Installing greetd..."
sudo dnf install -y greetd greetd-tuigreet

sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml > /dev/null <<'GREETD'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --time-format '%I:%M %p | %a - %h | %F' --cmd 'uwsm start hyprland-uwsm-ready.desktop'"
user = "greeter"

[initial_session]
command = "uwsm start hyprland-uwsm-ready.desktop"
user = "alt"
GREETD

sudo systemctl enable greetd

# ─── 5. Audio (PipeWire) ────────────────────────────────────────────
info "Installing PipeWire audio stack..."
sudo dnf install -y \
    pipewire \
    pipewire-alsa \
    pipewire-pulseaudio \
    pipewire-jack-audio-connection-kit \
    wireplumber \
    pavucontrol

# ─── 6. Bluetooth ───────────────────────────────────────────────────
info "Installing Bluetooth..."
sudo dnf install -y bluez blueman
sudo systemctl enable bluetooth

# Bluetooth config for FastConnectable + Experimental
sudo mkdir -p /etc/bluetooth
sudo tee /etc/bluetooth/main.conf > /dev/null <<'BTCONF'
[General]
Experimental = true
FastConnectable = true
BTCONF

# ─── 7. Virtualization ──────────────────────────────────────────────
info "Installing virtualization..."
sudo dnf install -y @virtualization
sudo dnf install -y \
    swtpm \
    swtpm-tools \
    bridge-utils \
    virt-viewer

sudo systemctl enable libvirtd

# Add user to groups
sudo usermod -aG libvirt,kvm "$USER_NAME"

# Trust virbr0
sudo firewall-cmd --permanent --zone=trusted --add-interface=virbr0 2>/dev/null || true
sudo firewall-cmd --reload 2>/dev/null || true

# ─── 8. Terminal + Shell ─────────────────────────────────────────────
info "Installing Kitty + Zsh..."
sudo dnf install -y kitty zsh
sudo chsh -s /usr/bin/zsh "$USER_NAME"

# Oh My Zsh
if [[ ! -d "$HOME_DIR/.oh-my-zsh" ]]; then
    info "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Zsh plugins
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME_DIR/.oh-my-zsh/custom}"
[[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] || \
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
[[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] || \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# ─── 9. Bar + Launcher + Notifications ──────────────────────────────
info "Installing Waybar, Wofi, SwayNC..."
sudo dnf install -y \
    waybar \
    wofi \
    SwayNotificationCenter

# ─── 10. Fonts ───────────────────────────────────────────────────────
info "Installing fonts..."
sudo dnf install -y \
    jetbrains-mono-fonts-all \
    google-noto-color-emoji-fonts

# Nerd Font (not in Fedora repos)
NERD_FONT_DIR="$HOME_DIR/.local/share/fonts/NerdFonts"
if [[ ! -d "$NERD_FONT_DIR" ]]; then
    info "Installing JetBrainsMono Nerd Font..."
    mkdir -p "$NERD_FONT_DIR"
    curl -fLo /tmp/JetBrainsMono.zip \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    unzip -o /tmp/JetBrainsMono.zip -d "$NERD_FONT_DIR"
    rm /tmp/JetBrainsMono.zip
    fc-cache -fv
fi

# ─── 11. CLI Tools ──────────────────────────────────────────────────
info "Installing CLI tools..."
sudo dnf install -y \
    neovim \
    git \
    tmux \
    ripgrep \
    bat \
    tree \
    unzip \
    wl-clipboard \
    grim \
    slurp \
    playerctl \
    gdb \
    file \
    gdisk

# ─── 12. Applications ───────────────────────────────────────────────
info "Installing applications..."
sudo dnf install -y \
    firefox \
    keepassxc \
    nextcloud-client \
    thunar \
    syncthing \
    blender

# ─── 13. Tailscale ──────────────────────────────────────────────────
info "Installing Tailscale..."
sudo dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
sudo dnf install -y tailscale
sudo systemctl enable --now tailscaled

# ─── 14. SSH (Tailscale-only) ───────────────────────────────────────
info "Configuring SSH..."
sudo systemctl enable sshd

sudo tee /etc/ssh/sshd_config.d/99-hardened.conf > /dev/null <<'SSHCONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
X11Forwarding no
SSHCONF

# Restrict SSH to Tailscale interface
sudo firewall-cmd --permanent --remove-service=ssh --zone=public 2>/dev/null || true
sudo firewall-cmd --permanent --zone=trusted --add-interface=tailscale0 2>/dev/null || true
sudo firewall-cmd --permanent --zone=trusted --add-service=ssh 2>/dev/null || true
sudo firewall-cmd --reload 2>/dev/null || true

# ─── 15. Polkit (for GUI privilege escalation) ──────────────────────
info "Installing Polkit agent..."
sudo dnf install -y polkit-gnome

# ─── 16. Codecs (RPM Fusion) ────────────────────────────────────────
info "Installing multimedia codecs..."
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf install -y gstreamer1-plugins-{bad-\*,good-\*,base} gstreamer1-plugin-openh264 \
    gstreamer1-libav lame\* 2>/dev/null || true

# ─── 17. Cursor Theme ───────────────────────────────────────────────
info "Installing rose-pine cursor..."
CURSOR_DIR="$HOME_DIR/.local/share/icons/rose-pine-hyprcursor"
if [[ ! -d "$CURSOR_DIR" ]]; then
    mkdir -p "$HOME_DIR/.local/share/icons"
    git clone https://github.com/ndom91/rose-pine-hyprcursor.git "$CURSOR_DIR" 2>/dev/null || \
        warn "Could not clone rose-pine-hyprcursor — install manually"
fi

# ─── 18. Plymouth (boot splash) ─────────────────────────────────────
info "Installing Plymouth..."
sudo dnf install -y plymouth plymouth-theme-spinner
# Note: custom circle_hud theme would need manual install from adi1090x-plymouth-themes

# ─── 19. System Tweaks ──────────────────────────────────────────────
info "Enabling system services..."
sudo systemctl enable fstrim.timer
sudo systemctl enable NetworkManager
sudo systemctl enable syncthing@"$USER_NAME"

# ─── 20. Config Files ───────────────────────────────────────────────
info "Writing config files..."

# Create directories
mkdir -p "$CONFIG_DIR"/{hypr,kitty,waybar,swaync,tmux}

# --- Hyprland ---
cp "$SCRIPT_DIR/configs/hyprland.conf" "$CONFIG_DIR/hypr/hyprland.conf"

# --- Hyprlock ---
cp "$SCRIPT_DIR/configs/hyprlock.conf" "$CONFIG_DIR/hypr/hyprlock.conf"

# --- Hyprpaper ---
cp "$SCRIPT_DIR/configs/hyprpaper.conf" "$CONFIG_DIR/hypr/hyprpaper.conf"

# --- Kitty ---
cp "$SCRIPT_DIR/configs/kitty.conf" "$CONFIG_DIR/kitty/kitty.conf"

# --- Waybar ---
cp "$SCRIPT_DIR/configs/waybar-config.jsonc" "$CONFIG_DIR/waybar/config.jsonc"
cp "$SCRIPT_DIR/configs/waybar-style.css" "$CONFIG_DIR/waybar/style.css"

# --- SwayNC ---
cp "$SCRIPT_DIR/configs/swaync-config.json" "$CONFIG_DIR/swaync/config.json"
cp "$SCRIPT_DIR/configs/swaync-style.css" "$CONFIG_DIR/swaync/style.css"

# --- Tmux (Oh My Tmux) ---
if [[ ! -d "$HOME_DIR/.tmux" ]]; then
    info "Installing Oh My Tmux..."
    git clone https://github.com/gpakosz/.tmux.git "$HOME_DIR/.tmux"
    ln -sf "$HOME_DIR/.tmux/.tmux.conf" "$HOME_DIR/.tmux.conf"
fi
cp "$SCRIPT_DIR/configs/tmux.conf.local" "$HOME_DIR/.tmux.conf.local"

# --- Git ---
cp "$SCRIPT_DIR/configs/gitconfig" "$HOME_DIR/.gitconfig"

# --- Zsh ---
cp "$SCRIPT_DIR/configs/zshrc" "$HOME_DIR/.zshrc"

# ─────────────────────────────────────────────────────────────────────
echo ""
info "=========================================="
info "  Install complete!"
info "=========================================="
echo ""
warn "Next steps:"
echo "  1. Reboot (NVIDIA kmod needs it)"
echo "  2. Run 'sudo tailscale up' to connect Tailscale"
echo "  3. Copy your SSH authorized_keys to ~/.ssh/authorized_keys"
echo "  4. Copy your YubiKey U2F config if using PAM U2F"
echo "  5. Copy your wallpapers to ~/wallpapers/ and update hyprpaper.conf"
echo "  6. Update monitor config in ~/.config/hypr/hyprland.conf"
echo "  7. virt-manager: may need to run 'virsh net-start default && virsh net-autostart default'"
echo ""
