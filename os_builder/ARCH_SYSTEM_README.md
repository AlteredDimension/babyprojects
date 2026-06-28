# Arch Linux System Reference — `alt` workstation

Migrated from NixOS to Arch on **2026-05-27**. This document is the source of
truth for *what is on this box, why, and how to recover it*. Pair it with
`complete_arch_run.sh` (next to this file) for a reproducible rebuild.

---

## 1. Hardware

| | |
|---|---|
| **CPU** | 11th-gen Intel Core i7-11700KF @ 3.6 GHz |
| **RAM** | 46 GiB |
| **GPU** | NVIDIA GeForce RTX 3080 (driver: `nvidia-open-dkms`, modules: `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm`) |
| **Storage** | `nvme1n1` 466 GB (root + home + swap on LVM-on-LUKS), `sda` 1.8 TB (data on LVM-on-LUKS), `nvme0n1` 477 GB (Windows NTFS, untouched), `sdb` and `sdc` external/removable |
| **YubiKey** | Yubico OTP+FIDO+CCID, FIDO 2.1-pre, hmac-secret + clientPin supported (`fido2-token -I /dev/hidraw6` to confirm) |
| **Monitors** | Configured in `~/.config/hypr/hyprland.conf` — DP-1, DP-2, DP-3, HDMI-A-1. Currently only 3 are connected; reconcile with `hyprctl monitors` if needed. |

---

## 2. Storage layout (LVM-on-LUKS)

```
nvme1n1 (466 GB)
├── nvme1n1p1   1 GB    vfat            /boot          ← EFI / systemd-boot
└── nvme1n1p2   465 GB  crypto_LUKS     CryptLVM_Main  ← UUID 3d90dce3-…
    └── vg0
        ├── vg0-swap   48 GB    [SWAP]
        ├── vg0-root   50 GB    /          (ext4, UUID 9ba6df3e-…)
        └── vg0-home  367 GB    /home      (ext4, UUID 2d248371-…)

sda (1.8 TB)
└── sda1       1.8 TB  crypto_LUKS     CryptLVM_Data  ← UUID e37ade15-…
    └── vg1
        └── vg1-lv_data 1.8 TB /mnt/data (ext4, UUID efc74ce2-…, nofail)
```

### LUKS slots / tokens

**`/dev/nvme1n1p2` (CryptLVM_Main)**
- Slot 0: FIDO2 (systemd-fido2 token) — primary YubiKey
- Slot 1: passphrase (PBKDF) — **emergency fallback, do not remove**

**`/dev/sda1` (CryptLVM_Data)**
- Slot 0: raw keyfile @ `/etc/cryptsetup-keys.d/CryptLVM_Data.key` (added 2026-05-27)
- Slot 1: FIDO2 (token 0) — primary YubiKey
- Slot 2: FIDO2 (token 1) — backup YubiKey
- Slot 3: FIDO2 (token 2) — backup YubiKey

There is intentionally **no** passphrase slot on the data drive. Recovery
requires either the keyfile (on the unlocked root fs) or any enrolled YubiKey.

---

## 3. Boot flow

```
UEFI firmware
  └── systemd-boot (/boot/loader/entries/arch.conf)
        │   cmdline: rd.luks.name=…=CryptLVM_Main
        │            rd.luks.options=…=fido2-device=auto
        │            root=/dev/vg0/root rw
        │            quiet splash loglevel=3 rd.udev.log_level=3
        ▼
   Linux + initramfs (mkinitcpio, systemd hook)
        HOOKS=(base systemd plymouth autodetect microcode modconf kms
               keyboard sd-vconsole block sd-encrypt lvm2 filesystems fsck)
        │
        ▼ plymouth-glow splash on
        ▼ systemd-cryptsetup unlocks CryptLVM_Main via FIDO2
        │   • YubiKey LED blinks → user touches → boot continues
        │   • If absent → falls back to passphrase prompt (slot 1)
        ▼
   vg0 activated → root mounted → systemd starts
        │
        ▼ systemd-cryptsetup@CryptLVM_Data.service reads /etc/crypttab,
        ▼ unlocks /dev/sda1 with /etc/cryptsetup-keys.d/CryptLVM_Data.key
        ▼ vg1 activated → /mnt/data mounted (nofail)
        │
        ▼
   greetd.service starts on vt1
        │   tuigreet shows clock + prompt
        │   PAM stack: securetty + nologin + system-local-login
        │     where system-local-login has 'pam_u2f.so cue' (sufficient)
        ▼
   uwsm start hyprland-uwsm.desktop  ← graphical session
```

### Recovery cmdline

At the systemd-boot menu, highlight **Arch Linux**, press `e`, and replace
the `options` line with:

```
options rd.luks.name=3d90dce3-b4cf-4c12-9422-94b6ca882103=CryptLVM_Main root=/dev/vg0/root rw
```

This drops back to a passphrase prompt for root. Same line is preserved as a
comment at the bottom of `/boot/loader/entries/arch.conf`.

---

## 4. Authentication

### YubiKey

Three places use the YubiKey:
1. **Boot** — unlocks root LUKS (`fido2-device=auto` in kernel cmdline).
2. **PAM auth** — `pam-u2f` registered via `~/.config/Yubico/u2f_keys`.
3. **Data drive (optional)** — slots 1/2/3 are FIDO2-enrolled, but the
   keyfile slot 0 is what crypttab actually uses for auto-mount.

The PAM stack uses `auth sufficient pam_u2f.so cue`:
- **Sufficient** = YubiKey-OR-password (not 2FA). Tap to authenticate; if no
  key is plugged in, falls through to your normal password.
- Files touched:
  - `/etc/pam.d/sudo` — inserted before `auth include system-auth`
  - `/etc/pam.d/system-local-login` — inserted before `auth include system-login`
- Because of the PAM include chain, this single edit to
  `system-local-login` covers **greetd** (tuigreet login), **login** (TTY),
  and **hyprlock** (screen lock).

### Adding another YubiKey

```bash
pamu2fcfg -u alt -n >> ~/.config/Yubico/u2f_keys
# Then merge into the single 'alt:…' line, comma-separating the entries.
```

To enroll a new YubiKey on a LUKS volume:

```bash
# Root drive — needs existing FIDO2 OR passphrase to authorize
sudo systemd-cryptenroll --fido2-device=auto /dev/nvme1n1p2

# Data drive — needs an existing FIDO2 token plugged in to authorize
sudo systemd-cryptenroll --fido2-device=auto /dev/sda1
```

---

## 5. Services running at boot

| Service | Purpose |
|---|---|
| `NetworkManager` | Networking |
| `bluetooth` | Bluetooth daemon (`/etc/bluetooth/main.conf` has `Experimental=true`, `FastConnectable=true`) |
| `libvirtd` | KVM/QEMU virtualization daemon; user `alt` in `libvirt` + `kvm` groups |
| `sshd` | OpenSSH, hardened (`/etc/ssh/sshd_config.d/99-hardened.conf`: no passwords, no root, no X11) |
| `tailscaled` | Tailscale daemon. Authenticate with `sudo tailscale up` (one-time). |
| `syncthing@alt` | File sync, runs as user `alt` |
| `fstrim.timer` | Weekly TRIM on SSD/NVMe |
| `greetd` | Display manager — tuigreet greeter, launches Hyprland via `uwsm` |

---

## 6. Filesystem layout (what lives where)

```
/etc/cryptsetup-keys.d/
  CryptLVM_Data.key       Keyfile for data drive. Mode 0400, root-only.

/etc/crypttab             One entry: CryptLVM_Data → keyfile.
/etc/fstab                Mounts for /, /home, /boot, /mnt/data (nofail), swap.

/etc/mkinitcpio.conf      HOOKS=(base systemd plymouth …) ← plymouth added.
/boot/loader/entries/
  arch.conf               systemd-boot entry. FIDO2 cmdline + plymouth splash.

/etc/greetd/config.toml   greetd → tuigreet → uwsm Hyprland.
/etc/bluetooth/main.conf  Experimental + FastConnectable patched in.

/etc/ssh/sshd_config.d/
  99-hardened.conf        Password/root/X11 disabled.

/etc/pam.d/
  sudo                    auth sufficient pam_u2f.so cue (+system-auth include)
  system-local-login      same (covers login/greetd/hyprlock via include)

/etc/sudo.conf            Path askpass → /home/alt/.local/bin/zenity-askpass
                          (lets `sudo -A` pop a GUI password prompt)

/root/backups/            Pre-change snapshots of every file we edited,
                          timestamped. Restore from here on rollback.

/home/alt/.local/bin/
  zenity-askpass          1-line script that runs `zenity --password …`.

/home/alt/.config/
  hypr/hyprland.conf      Compositor config (mainMod=SUPER, monitors, binds)
  hypr/hyprlock.conf      Lock screen
  hypr/hyprpaper.conf     Wallpaper daemon — references ~/wallpapers/
  kitty/kitty.conf        Terminal
  waybar/{config.jsonc, style.css}
  swaync/{config.json, style.css}
  Yubico/u2f_keys         pam-u2f registration (regenerated on Arch, NOT the
                          dead Nix-store symlink from the NixOS backup).
  nvim/                   Editor (restored from backup)
  keepassxc/              Password manager settings
  btop/, fontconfig/, gtk-3.0/  Restored from backup

/home/alt/
  .zshrc                  Oh My Zsh, theme=jonathan, plugins=(git sudo docker
                          kubectl zsh-autosuggestions zsh-syntax-highlighting)
  .tmux.conf → .tmux/.tmux.conf  Oh My Tmux symlink
  .tmux.conf.local        User overrides for Oh My Tmux
  .gitconfig
  .ssh/                   Restored from backup (keys + known_hosts)
  wallpapers/             4 images referenced by hyprpaper.conf
  3d_prints/              Restored from backup
  .oh-my-zsh/
  .tmux/
  .local/share/icons/rose-pine-hyprcursor/   HYPRCURSOR_THEME=rose-pine-hyprcursor
```

---

## 7. Troubleshooting

### Boot

**Symptom: stuck on Plymouth splash, no FIDO2 prompt.**
Plug the YubiKey in *before* power-on. The LED should blink immediately after
the splash appears. If not, drop to a console via the recovery cmdline above.

**Symptom: data drive not mounting at boot.**
1. Boot succeeded, so root + keyfile work. Check
   `systemctl status systemd-cryptsetup@CryptLVM_Data.service`.
2. Verify the keyfile still exists: `sudo ls -l /etc/cryptsetup-keys.d/`.
3. Verify the keyslot is still valid on the LUKS header:
   `sudo cryptsetup luksOpen --test-passphrase --disable-external-tokens \
        --key-file /etc/cryptsetup-keys.d/CryptLVM_Data.key /dev/sda1`.
4. If the keyfile is gone (e.g. accidentally deleted), re-add one using
   any existing YubiKey:
   ```bash
   sudo install -d -m 0700 /etc/cryptsetup-keys.d
   sudo dd if=/dev/urandom of=/etc/cryptsetup-keys.d/CryptLVM_Data.key \
           bs=512 count=4
   sudo chmod 0400 /etc/cryptsetup-keys.d/CryptLVM_Data.key
   sudo cryptsetup luksAddKey --token-only /dev/sda1 \
        /etc/cryptsetup-keys.d/CryptLVM_Data.key
   ```

**Symptom: every boot prompts for passphrase, not FIDO2.**
Check `/boot/loader/entries/arch.conf`: the `options` line must contain
`rd.luks.options=…=fido2-device=auto`. If it was reverted by an update,
restore from `/root/backups/arch.conf.*`.

### Login

**Symptom: `sudo` hangs ~15s when no YubiKey plugged in.**
pam_u2f waits a short while for any FIDO device. Either plug in the key or
press Ctrl-C; password prompt follows.

**Symptom: `sudo` accepts password but not YubiKey.**
`~/.config/Yubico/u2f_keys` is missing or malformed. Re-register:
`pamu2fcfg -u alt > ~/.config/Yubico/u2f_keys` (will require a touch).

**Symptom: locked out after editing PAM.**
Drop to a TTY (Ctrl-Alt-F2), log in (`sufficient` always allows the password
fallback), restore PAM from `/root/backups/pam.d.*`:
```bash
sudo cp -a /root/backups/pam.d.<STAMP>/sudo /etc/pam.d/sudo
sudo cp -a /root/backups/pam.d.<STAMP>/system-local-login /etc/pam.d/system-local-login
```

### Graphics / Hyprland

**Symptom: stub `hyprland.conf` after install, no monitors.**
Hyprland generates a stub when no config exists. Re-copy the real one:
`cp /mnt/data/alt_backup/fedora-postinstall/configs/hyprland.conf \
    ~/.config/hypr/hyprland.conf` and patch the polkit-gnome path from
`/usr/libexec/…` (Fedora) to `/usr/lib/polkit-gnome/…` (Arch).

**Symptom: cursor theme is the X cursor, not rose-pine.**
Confirm `HYPRCURSOR_THEME=rose-pine-hyprcursor` is in `hyprland.conf` and
`~/.local/share/icons/rose-pine-hyprcursor/` exists with `manifest.hl`.

### Audio / Bluetooth

**Symptom: no sound.** `wireplumber` may have crashed.
`systemctl --user restart wireplumber pipewire pipewire-pulse`.

**Symptom: Bluetooth device won't reconnect.**
Already mitigated by `Experimental=true` + `FastConnectable=true` in
`/etc/bluetooth/main.conf`. If still flaky: `bluetoothctl power off && power on`.

### sudo askpass

**Symptom: `sudo -A` says "no askpass program specified".**
Re-check `/etc/sudo.conf` has the line `Path askpass /home/alt/.local/bin/zenity-askpass`,
and that the script is `+x`. The graphical session must be running for zenity
to display.

---

## 8. Backups + provenance

- **Pre-change config snapshots:** `/root/backups/{crypttab,mkinitcpio.conf,arch.conf,pam.d}.<timestamp>/`
- **Old home snapshot:** `/mnt/data/alt_backup/alt/` (the NixOS box, captured 2026-05-26)
- **Ready-to-paste dotfiles:** `/mnt/data/alt_backup/fedora-postinstall/configs/`
- **Replay script:** `/mnt/data/alt_backup/complete_arch_run.sh`
- **Original (Fedora) install script:** `/mnt/data/alt_backup/fedora-postinstall/arch-install.sh` —
  historical reference; do **not** run on Arch (uses `dnf`).

---

## 9. Conventions

- **Package manager:** `pacman` for official repos, `paru` for AUR. Don't mix
  AUR helpers (no `yay`).
- **File manager:** Dolphin (not Thunar). `nextcloud-client` is intentionally
  not installed; Syncthing is the sync mechanism.
- **Shell:** `zsh` with Oh My Zsh, theme `jonathan`.
- **Editor:** `nvim`. `EDITOR=nvim` and `VISUAL=nvim` in `~/.zshrc`.
- **Terminal:** `kitty`.
- **`direnv`:** intentionally **not** installed — hook line removed from
  `.zshrc`. Re-add if Nix-direnv workflow ever returns.
- **Firewall:** none by default on Arch. SSH is reachable on all interfaces
  but requires keys (passwords disabled). If you want SSH-over-Tailscale only,
  add an nftables rule restricting port 22 to `tailscale0`.
