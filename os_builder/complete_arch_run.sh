#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# complete_arch_run.sh — Replay script for alt's Arch + Hyprland + LUKS setup
# Captures every meaningful command run during the 2026-05-27 NixOS→Arch
# migration. Idempotent where possible; manual steps are flagged with [HUMAN].
#
# Assumptions for a fresh re-run:
#   - Arch already installed with: systemd-boot, LVM-on-LUKS root
#     (CryptLVM_Main), and an existing LUKS data drive (CryptLVM_Data) on
#     /dev/sda1. Both LUKS volumes already have FIDO2 enrolled via
#     systemd-cryptenroll (slot 0 or higher).
#   - User `alt` exists, is in the `wheel` group, and is the one running this
#     script (NOT root). The script will use sudo where needed.
#   - A Hyprland or other graphical session is up (zenity needs $WAYLAND_DISPLAY
#     or $DISPLAY for the sudo askpass popup).
#   - The companion files at /mnt/data/alt_backup/fedora-postinstall/configs/
#     and /mnt/data/alt_backup/alt/ are mounted and readable.
#
# Run with:   bash /mnt/data/alt_backup/complete_arch_run.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

USER_NAME="alt"
HOME_DIR="/home/${USER_NAME}"
CONFIG_DIR="${HOME_DIR}/.config"
BACKUP_ROOT="/mnt/data/alt_backup"
CFG_SRC="${BACKUP_ROOT}/fedora-postinstall/configs"
HOME_SRC="${BACKUP_ROOT}/alt"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()   { echo -e "${GREEN}[+]${NC} $*"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*"; }
err()    { echo -e "${RED}[x]${NC} $*" >&2; }
human()  { echo -e "${CYAN}[HUMAN]${NC} $*"; }
section(){ echo; echo -e "${CYAN}━━━━━━━ $* ━━━━━━━${NC}"; }

[[ $EUID -eq 0 ]] && { err "Run as ${USER_NAME}, not root. sudo is used internally."; exit 1; }
[[ $(whoami) == "${USER_NAME}" ]] || warn "Expected user '${USER_NAME}', got '$(whoami)'. Continuing anyway."

# ═════════════════════════════════════════════════════════════════════════════
section "Phase 0 — sudo askpass (zenity wrapper + /etc/sudo.conf)"
# ═════════════════════════════════════════════════════════════════════════════
# Lets `sudo -A` pop up a graphical password prompt when there is no TTY,
# which is how scripts invoked from agents or batched tooling acquire sudo.
if ! command -v zenity >/dev/null; then
  human "Run this first (interactive sudo): sudo pacman -S --noconfirm zenity"
  exit 1
fi

mkdir -p "${HOME_DIR}/.local/bin"
cat > "${HOME_DIR}/.local/bin/zenity-askpass" <<'ASKPASS'
#!/bin/sh
# SUDO_ASKPASS helper using zenity. sudo passes the prompt text as $1.
zenity --password --title="sudo" --timeout=120 2>/dev/null
ASKPASS
chmod +x "${HOME_DIR}/.local/bin/zenity-askpass"

# Wire askpass into sudo system-wide via /etc/sudo.conf
if ! sudo grep -q "^Path askpass " /etc/sudo.conf 2>/dev/null; then
  human "About to add the askpass path to /etc/sudo.conf — sudo will prompt."
  sudo bash -c "echo 'Path askpass ${HOME_DIR}/.local/bin/zenity-askpass' >> /etc/sudo.conf"
fi

export SUDO_ASKPASS="${HOME_DIR}/.local/bin/zenity-askpass"
SUDO="sudo -A"

# ═════════════════════════════════════════════════════════════════════════════
section "Phase 1 — AUR helper (paru) bootstrap"
# ═════════════════════════════════════════════════════════════════════════════
if ! command -v paru >/dev/null; then
  ${SUDO} pacman -S --noconfirm --needed base-devel git rust
  TMPDIR_PARU=$(mktemp -d)
  git clone https://aur.archlinux.org/paru.git "${TMPDIR_PARU}/paru"
  ( cd "${TMPDIR_PARU}/paru" && makepkg -si --noconfirm )
  rm -rf "${TMPDIR_PARU}"
else
  info "paru already installed: $(paru --version | head -1)"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "Phase 2 — Big pacman install (CLI, Hyprland, audio, BT, fonts, apps, virt)"
# ═════════════════════════════════════════════════════════════════════════════
${SUDO} pacman -S --noconfirm --needed \
  zsh tmux ripgrep bat tree unzip btop \
  waybar wofi swaync polkit-gnome hypridle hyprland hyprlock hyprpaper \
  xdg-desktop-portal-hyprland uwsm \
  pavucontrol bluez bluez-utils blueman \
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
  ttf-jetbrains-mono noto-fonts-emoji \
  firefox keepassxc dolphin syncthing blender \
  kitty neovim git \
  tailscale openssh plymouth \
  qemu-desktop libvirt virt-manager dnsmasq edk2-ovmf swtpm virt-viewer \
  greetd greetd-tuigreet \
  wl-clipboard grim slurp playerctl gdb file \
  nvidia-open-dkms nvidia-utils nvidia-settings libva-nvidia-driver linux-firmware-nvidia \
  pam-u2f libfido2

# Nerd Font from AUR
paru -S --noconfirm --needed --sudoflags "-A" ttf-jetbrains-mono-nerd

# ═════════════════════════════════════════════════════════════════════════════
section "Phase 3 — System services + configs (greetd, bluetooth, sshd, virt, etc.)"
# ═════════════════════════════════════════════════════════════════════════════
${SUDO} bash <<'SETUP'
set -euo pipefail
USER_NAME="alt"

# greetd → tuigreet → uwsm Hyprland
cat > /etc/greetd/config.toml <<GREETD
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --time-format '%I:%M %p | %a - %h | %F' --cmd 'uwsm start hyprland-uwsm.desktop'"
user = "greeter"

[initial_session]
command = "uwsm start hyprland-uwsm.desktop"
user = "${USER_NAME}"
GREETD

# Bluetooth: Experimental + FastConnectable for better device support
python3 - <<'PY'
import re
p = "/etc/bluetooth/main.conf"
s = open(p).read()
def set_kv(text, key, val):
    pat = re.compile(rf"^[#\s]*{key}\s*=.*$", re.MULTILINE)
    if pat.search(text):
        return pat.sub(f"{key} = {val}", text, count=1)
    return re.sub(r"(\[General\]\s*\n)", rf"\1{key} = {val}\n", text, count=1)
s = set_kv(s, "Experimental", "true")
s = set_kv(s, "FastConnectable", "true")
open(p, "w").write(s)
PY

# Hardened SSH: no passwords, no root, no X11
cat > /etc/ssh/sshd_config.d/99-hardened.conf <<SSHCONF
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
X11Forwarding no
SSHCONF

# Group membership for virtualization
usermod -aG libvirt,kvm "${USER_NAME}"

# Enable + start services (greetd starts on next boot)
systemctl enable bluetooth.service libvirtd.service sshd.service tailscaled.service fstrim.timer
systemctl enable "syncthing@${USER_NAME}.service" greetd.service
systemctl start bluetooth.service libvirtd.service sshd.service tailscaled.service fstrim.timer || true
systemctl start "syncthing@${USER_NAME}.service" || true

# libvirt default network
virsh net-autostart default 2>/dev/null || true
virsh net-start default 2>/dev/null || true
SETUP

# ═════════════════════════════════════════════════════════════════════════════
section "Phase 4 — Dotfiles into ~/.config (from backup configs/)"
# ═════════════════════════════════════════════════════════════════════════════
mkdir -p "${CONFIG_DIR}"/{hypr,kitty,waybar,swaync,tmux}

# Hyprland: patch Fedora polkit-gnome path (/usr/libexec) → Arch (/usr/lib/polkit-gnome)
sed 's|/usr/libexec/polkit-gnome-authentication-agent-1|/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1|' \
  "${CFG_SRC}/hyprland.conf" > "${CONFIG_DIR}/hypr/hyprland.conf"

cp "${CFG_SRC}/hyprlock.conf"        "${CONFIG_DIR}/hypr/hyprlock.conf"
cp "${CFG_SRC}/hyprpaper.conf"       "${CONFIG_DIR}/hypr/hyprpaper.conf"
cp "${CFG_SRC}/kitty.conf"           "${CONFIG_DIR}/kitty/kitty.conf"
cp "${CFG_SRC}/waybar-config.jsonc"  "${CONFIG_DIR}/waybar/config.jsonc"
cp "${CFG_SRC}/waybar-style.css"     "${CONFIG_DIR}/waybar/style.css"
cp "${CFG_SRC}/swaync-config.json"   "${CONFIG_DIR}/swaync/config.json"
cp "${CFG_SRC}/swaync-style.css"     "${CONFIG_DIR}/swaync/style.css"
cp "${CFG_SRC}/gitconfig"            "${HOME_DIR}/.gitconfig"
cp "${CFG_SRC}/zshrc"                "${HOME_DIR}/.zshrc"

# Strip the direnv hook (we are not installing direnv on this box)
sed -i '/^# Direnv$/,/^eval "\$(direnv hook zsh)"$/d' "${HOME_DIR}/.zshrc" || true

# ═════════════════════════════════════════════════════════════════════════════
section "Phase 5 — Shells: Oh My Zsh + plugins, Oh My Tmux, chsh to zsh"
# ═════════════════════════════════════════════════════════════════════════════
export RUNZSH=no CHSH=no KEEP_ZSHRC=yes
[[ -d "${HOME_DIR}/.oh-my-zsh" ]] || \
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

ZSH_CUSTOM="${HOME_DIR}/.oh-my-zsh/custom"
[[ -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]]     || git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions     "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
[[ -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]] || git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"

if [[ ! -d "${HOME_DIR}/.tmux" ]]; then
  git clone --depth=1 https://github.com/gpakosz/.tmux.git "${HOME_DIR}/.tmux"
  ln -sf "${HOME_DIR}/.tmux/.tmux.conf" "${HOME_DIR}/.tmux.conf"
fi
cp "${CFG_SRC}/tmux.conf.local" "${HOME_DIR}/.tmux.conf.local"

[[ $(getent passwd "${USER_NAME}" | cut -d: -f7) == "/usr/bin/zsh" ]] || \
  ${SUDO} chsh -s /usr/bin/zsh "${USER_NAME}"

# ═════════════════════════════════════════════════════════════════════════════
section "Phase 6 — Restore from backup home (~/.ssh, wallpapers, picks)"
# ═════════════════════════════════════════════════════════════════════════════
# SSH keys + known_hosts
mkdir -p "${HOME_DIR}/.ssh"
cp -a "${HOME_SRC}/.ssh/." "${HOME_DIR}/.ssh/"
chmod 700 "${HOME_DIR}/.ssh"
chmod 600 "${HOME_DIR}"/.ssh/* 2>/dev/null || true
chmod 644 "${HOME_DIR}"/.ssh/*.pub      2>/dev/null || true
chmod 644 "${HOME_DIR}"/.ssh/known_hosts* 2>/dev/null || true
chmod 700 "${HOME_DIR}/.ssh/agent"      2>/dev/null || true

# Wallpapers — referenced by hyprpaper.conf
mkdir -p "${HOME_DIR}/wallpapers"
cp -an "${HOME_SRC}/NixOS/nixos/wallpapers/." "${HOME_DIR}/wallpapers/"
chmod 644 "${HOME_DIR}"/wallpapers/* 2>/dev/null || true

# Selected .config dirs
for d in nvim keepassxc btop fontconfig Yubico gtk-3.0; do
  [[ -d "${HOME_SRC}/.config/$d" ]] && cp -an "${HOME_SRC}/.config/$d" "${CONFIG_DIR}/"
done

# 3D-print library
[[ -d "${HOME_SRC}/3d_prints" ]] && cp -an "${HOME_SRC}/3d_prints" "${HOME_DIR}/"

# IMPORTANT: nuke the restored u2f_keys file — on the source NixOS box it was a
# symlink into /nix/store, which is dead here. We regenerate it in Phase 11.
rm -f "${CONFIG_DIR}/Yubico/u2f_keys"

# ═════════════════════════════════════════════════════════════════════════════
section "Phase 7 — Rose-Pine hyprcursor theme"
# ═════════════════════════════════════════════════════════════════════════════
CURSOR_DIR="${HOME_DIR}/.local/share/icons/rose-pine-hyprcursor"
if [[ ! -d "${CURSOR_DIR}" ]]; then
  mkdir -p "${HOME_DIR}/.local/share/icons"
  git clone --depth=1 https://github.com/ndom91/rose-pine-hyprcursor.git "${CURSOR_DIR}"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "Phase 8 — Backup current state of files we are about to touch"
# ═════════════════════════════════════════════════════════════════════════════
${SUDO} bash <<'BAK'
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p /root/backups
cp -a /etc/crypttab            /root/backups/crypttab.$STAMP            2>/dev/null || true
cp -a /etc/mkinitcpio.conf     /root/backups/mkinitcpio.conf.$STAMP
cp -a /boot/loader/entries/arch.conf /root/backups/arch.conf.$STAMP
cp -a /etc/pam.d               /root/backups/pam.d.$STAMP
echo "Backups in /root/backups (stamp $STAMP)"
BAK

# ═════════════════════════════════════════════════════════════════════════════
section "Phase 9 — Data drive (CryptLVM_Data) auto-mount via keyfile"
# ═════════════════════════════════════════════════════════════════════════════
# Generates a 2KB random keyfile on the (already-unlocked) root filesystem and
# adds it as a new LUKS slot on /dev/sda1. Then crypttab points at the keyfile
# so the data drive unlocks silently after root is mounted.
DATA_UUID=$(sudo blkid -s UUID -o value /dev/sda1)
${SUDO} install -d -m 0700 /etc/cryptsetup-keys.d
if ! ${SUDO} test -f /etc/cryptsetup-keys.d/CryptLVM_Data.key; then
  ${SUDO} bash -c '
    dd if=/dev/urandom of=/etc/cryptsetup-keys.d/CryptLVM_Data.key bs=512 count=4 status=none
    chmod 0400 /etc/cryptsetup-keys.d/CryptLVM_Data.key
  '
fi

human "Adding the keyfile to /dev/sda1 — YubiKey touch required (authorizes via existing FIDO2 slot)."
${SUDO} cryptsetup luksAddKey --token-only /dev/sda1 /etc/cryptsetup-keys.d/CryptLVM_Data.key

${SUDO} bash -c "cat > /etc/crypttab <<CRYPTTAB
CryptLVM_Data UUID=${DATA_UUID} /etc/cryptsetup-keys.d/CryptLVM_Data.key luks,nofail
CRYPTTAB"

# ═════════════════════════════════════════════════════════════════════════════
section "Phase 10 — Plymouth + FIDO2 boot for root (CryptLVM_Main)"
# ═════════════════════════════════════════════════════════════════════════════
ROOT_UUID=$(sudo blkid -s UUID -o value /dev/nvme1n1p2)

${SUDO} bash <<EOF
set -euo pipefail

# arch.conf — FIDO2 unlock for root + Plymouth-quiet kernel cmdline
cat > /boot/loader/entries/arch.conf <<ARCHCONF
title	Arch Linux
linux	/vmlinuz-linux
initrd	/intel-ucode.img
initrd	/initramfs-linux.img
options	rd.luks.name=${ROOT_UUID}=CryptLVM_Main rd.luks.options=${ROOT_UUID}=fido2-device=auto root=/dev/vg0/root rw quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0
# Recovery (passphrase fallback): at the systemd-boot menu press 'e' on Arch Linux and replace options with:
# options rd.luks.name=${ROOT_UUID}=CryptLVM_Main root=/dev/vg0/root rw
ARCHCONF

# Inject plymouth hook right after systemd in mkinitcpio HOOKS
if ! grep -q "plymouth" /etc/mkinitcpio.conf; then
  sed -i 's/^HOOKS=(base systemd /HOOKS=(base systemd plymouth /' /etc/mkinitcpio.conf
fi

plymouth-set-default-theme glow
mkinitcpio -P
EOF

# ═════════════════════════════════════════════════════════════════════════════
section "Phase 11 — PAM U2F (sudo / login / hyprlock)"
# ═════════════════════════════════════════════════════════════════════════════
# pam-u2f was already installed in Phase 2. Generate the registration file
# (requires a YubiKey touch) and wire pam_u2f into the auth stacks.
mkdir -p "${CONFIG_DIR}/Yubico"
if [[ ! -s "${CONFIG_DIR}/Yubico/u2f_keys" ]]; then
  human "Touch your YubiKey when it blinks — registering it for PAM."
  pamu2fcfg -u "${USER_NAME}" > "${CONFIG_DIR}/Yubico/u2f_keys"
fi

${SUDO} bash <<'PAM'
set -euo pipefail

# sudo: yubikey-OR-password
if ! grep -q "pam_u2f.so" /etc/pam.d/sudo; then
  sed -i '/^auth\s\+include\s\+system-auth/i auth\t\tsufficient\tpam_u2f.so cue' /etc/pam.d/sudo
fi

# system-local-login: covers greetd, login (TTY), and hyprlock via include chain
if ! grep -q "pam_u2f.so" /etc/pam.d/system-local-login; then
  sed -i '/^auth\s\+include\s\+system-login/i auth\t  sufficient pam_u2f.so cue' /etc/pam.d/system-local-login
fi
PAM

# ═════════════════════════════════════════════════════════════════════════════
section "Done"
# ═════════════════════════════════════════════════════════════════════════════
cat <<'NEXT'
Manual next steps:

  1. Reboot. Watch for:
       - glow Plymouth splash
       - YubiKey touch prompt to unlock root LUKS
       - greetd login screen (touch YubiKey OR type password)

  2. If the FIDO2 unlock fails, at the systemd-boot menu press 'e' on Arch
     Linux and use the recovery 'options' line shown in the comment at the
     bottom of /boot/loader/entries/arch.conf.

  3. After login, authenticate Tailscale:    sudo tailscale up

  4. If you have multiple YubiKeys, register the others with:
       pamu2fcfg -u alt -n >> ~/.config/Yubico/u2f_keys
     then merge the new lines into the single 'alt:' line, comma-separated.

  5. Verify monitors:                         hyprctl monitors
     Update DP-* lines in ~/.config/hypr/hyprland.conf to match.

Backups of pre-change configs live in /root/backups/.
NEXT
