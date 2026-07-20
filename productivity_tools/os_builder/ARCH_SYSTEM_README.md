# Arch Linux System Reference — `alt` workstation

Migrated from NixOS to Arch on **2026-05-27**. This document is the source of
truth for *what is on this box, why, and how to recover it*. Pair it with
`complete_arch_run.sh` (next to this file) for a reproducible rebuild.

> **Last verified: 2026-07-20 (full sweep against live system state).**
>
> **Canonical location:** `/home/alt/scripts/productivity_tools/os_builder/`
> (inside the `~/scripts` git repo). This is the **only** copy — older notes
> referenced `/mnt/data/alt_backup/ARCH_SYSTEM_README.md`, but that directory
> no longer exists on `/mnt/data` (see §8 Backups + provenance).

---

## 1. Hardware

| | |
|---|---|
| **CPU** | 11th-gen Intel Core i7-11700KF @ 3.6 GHz |
| **RAM** | 46 GiB |
| **GPU** | NVIDIA GeForce RTX 3080 (driver: `nvidia-open-dkms`, modules: `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm`) |
| **Storage** | `nvme1n1` 466 GB (root + swap on LVM-on-LUKS), `nvme0n1` 477 GB (**/home** on its own LVM-on-LUKS volume — migrated off vg0 after initial install, see `/mnt/data/home-migration-handoff.md`), `sda` 1.8 TB (data on LVM-on-LUKS), `sdb` and `sdc` external/removable |
| **YubiKey** | Two keys: **primary** Yubico OTP+FIDO+CCID (product 0x0407) and **backup** YubiKey FIDO-only (product 0x0402, no client PIN), both enrolled on all three LUKS volumes and in pam-u2f (2026-07-20). The hidraw path changes between plugs — find it with `fido2-token -L`, inspect with `fido2-token -I <path>`. |
| **Monitors** | Configured in `~/.config/hypr/hyprland.conf` — DP-1, DP-2, DP-3, HDMI-A-1. Currently only 3 are connected; reconcile with `hyprctl monitors` if needed. |

---

## 2. Storage layout (LVM-on-LUKS)

```
nvme1n1 (466 GB)
├── nvme1n1p1   1 GB    vfat            /boot          ← EFI / systemd-boot
└── nvme1n1p2   465 GB  crypto_LUKS     CryptLVM_Main  ← UUID 3d90dce3-…
    └── vg0
        ├── vg0-swap   48 GB    [SWAP]
        └── vg0-root  416.7 GB  /          (ext4, UUID 9ba6df3e-…)
                                ← grown to fill vg0 after vg0-home was removed

nvme0n1 (477 GB)                          ← formerly "Windows NTFS"; now /home
└── nvme0n1p1   477 GB  crypto_LUKS     CryptLVM_Home  ← UUID 7f31e28f-…
    └── vg2 (≈23.9 GB free)
        └── vg2-lv_home 453.1 GB /home    (ext4, UUID 05b5c934-…)

sda (1.8 TB)
└── sda1       1.8 TB  crypto_LUKS     CryptLVM_Data  ← UUID e37ade15-…
    └── vg1
        └── vg1-lv_data 1.8 TB /mnt/data (ext4, UUID efc74ce2-…, nofail)
```

> **/home migration (2026):** `/home` was moved from an LV inside `vg0`
> (`CryptLVM_Main`) to its own disk `nvme0n1` / `CryptLVM_Home` / `vg2`.
> The old `vg0-home` LV no longer exists.

### LUKS slots / tokens

> **How to read a slot's role from `luksDump`:** FIDO2/token-backed slots use
> `pbkdf2` (the token secret is already high-entropy); human passphrases and
> raw keyfiles use `argon2id`. The authoritative FIDO2 map is the token JSON
> (`cryptsetup luksDump --dump-json-metadata <dev>` → `tokens[].keyslots`),
> not slot order. Slot numbers below were verified against that JSON on
> 2026-07-20.

**`/dev/nvme1n1p2` (CryptLVM_Main)**
- Slot 0: passphrase (argon2id) — **emergency fallback, do not remove**
- Slot 1: FIDO2 (systemd-fido2 token 0) — primary YubiKey
- Slot 2: FIDO2 (systemd-fido2 token 1) — **backup YubiKey (enrolled 2026-07-20,
  verified in header token JSON)**

**`/dev/nvme0n1p1` (CryptLVM_Home)**
- Slot 0: passphrase (argon2id) — emergency fallback, do not remove
- Slot 1: FIDO2 (systemd-fido2 token 0) — primary YubiKey
- Slot 2: raw keyfile (argon2id) @ `/etc/cryptsetup-keys.d/CryptLVM_Home.key`
  (added 2026-07-19) — this is what crypttab uses for **touchless** auto-unlock
- Slot 3: FIDO2 (systemd-fido2 token 1) — **backup YubiKey (enrolled 2026-07-20)**

**`/dev/sda1` (CryptLVM_Data)**
- Slot 0: raw keyfile (argon2id) @ `/etc/cryptsetup-keys.d/CryptLVM_Data.key` (added 2026-05-27)
- Slot 1: FIDO2 (token 0) — primary YubiKey
- Slot 2: FIDO2 (token 1) — YubiKey
- Slot 3: FIDO2 (token 2) — YubiKey
- Slot 4: FIDO2 (token 3) — **backup YubiKey (enrolled 2026-07-20)**

There is intentionally **no** passphrase slot on the data drive. Recovery
requires either the keyfile (on the unlocked root fs) or any enrolled YubiKey.

> **Correction (2026-07-20):** earlier revisions of this file listed the Main
> and Home FIDO2/passphrase slot numbers reversed. The FIDO2 slots are the
> `pbkdf2` ones (Main slot 1, Home slot 1); the `argon2id` slot 0 on each is
> the passphrase. Slot *content* is unchanged — only the documentation was wrong.

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
        ▼ plymouth 'alter' splash on (custom script theme; 'glow' kept as rollback)
        ▼ systemd-cryptsetup unlocks CryptLVM_Main via FIDO2
        │   • YubiKey LED blinks → user touches → boot continues
        │   • ← THIS IS THE ONLY FIDO2 TOUCH REQUIRED AT BOOT
        │   • Either enrolled YubiKey works (slots 1/2)
        │   • If absent → falls back to passphrase prompt (slot 0)
        ▼
   vg0 activated → root mounted → systemd starts
        │
        ▼ systemd-cryptsetup@CryptLVM_Home.service reads /etc/crypttab,
        ▼ unlocks /dev/nvme0n1p1 with /etc/cryptsetup-keys.d/CryptLVM_Home.key
        ▼ vg2 activated → /home mounted                    (no touch — keyfile)
        │
        ▼ systemd-cryptsetup@CryptLVM_Data.service reads /etc/crypttab,
        ▼ unlocks /dev/sda1 with /etc/cryptsetup-keys.d/CryptLVM_Data.key
        ▼ vg1 activated → /mnt/data mounted (nofail)        (no touch — keyfile)
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
1. **Boot** — unlocks root LUKS (`fido2-device=auto` in kernel cmdline). This
   is the **single** FIDO2 touch at boot; /home and /mnt/data then unlock
   touchlessly via keyfiles on the (now-decrypted) root fs.
2. **PAM auth** — `pam-u2f` registered via `~/.config/Yubico/u2f_keys`
   (single `alt:…` line holding **two** credentials — primary + backup key,
   backup registered 2026-07-20).
3. **Home & Data drives** — both auto-unlock via keyfiles referenced in
   `/etc/crypttab` (`CryptLVM_Home.key`, `CryptLVM_Data.key`). Their FIDO2
   slots remain enrolled for manual/recovery unlock but are not used at boot.

The PAM stack uses `auth sufficient pam_u2f.so cue`:
- **Sufficient** = YubiKey-OR-password (not 2FA). Tap to authenticate; if no
  key is plugged in, falls through to your normal password.
- Files touched:
  - `/etc/pam.d/sudo` — `auth sufficient pam_u2f.so authfile=/home/alt/.config/Yubico/u2f_keys cue`,
    inserted before `auth include system-auth`
  - `/etc/pam.d/system-local-login` — `auth sufficient pam_u2f.so cue`,
    inserted before `auth include system-login`
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
# Root drive — needs existing FIDO2 OR the slot-0 passphrase to authorize
sudo systemd-cryptenroll --fido2-device=auto /dev/nvme1n1p2

# Home / Data drives — authorize non-interactively with their keyfiles
sudo systemd-cryptenroll --unlock-key-file=/etc/cryptsetup-keys.d/CryptLVM_Home.key \
     --fido2-device=auto /dev/nvme0n1p1
sudo systemd-cryptenroll --unlock-key-file=/etc/cryptsetup-keys.d/CryptLVM_Data.key \
     --fido2-device=auto /dev/sda1

# Match the existing enrollments' options if enrolling a PIN-less key:
#   --fido2-with-client-pin=no --fido2-with-user-presence=yes --fido2-with-user-verification=no
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
| `ollama` | Local LLM server (added post-install; enabled + active as of 2026-07-20) |
| `proton.VPN` | Proton VPN daemon (packaged unit `me.proton.vpn.split_tunneling`; enabled + active as of 2026-07-20) |

---

## 6. Filesystem layout (what lives where)

```
/etc/cryptsetup-keys.d/
  CryptLVM_Data.key       Keyfile for data drive. Mode 0400, root-only.
  CryptLVM_Home.key       Keyfile for /home drive. Mode 0400, root-only. (2026-07-19)

/etc/crypttab             Two entries: CryptLVM_Data + CryptLVM_Home → keyfiles.
/etc/fstab                Mounts for /, /home, /boot, /mnt/data (nofail), swap.

/etc/mkinitcpio.conf      HOOKS=(base systemd plymouth …) ← plymouth added.
/etc/plymouth/plymouthd.conf   Theme=alter (was glow). Backups in /root/backups/.
/usr/share/plymouth/themes/alter/   Custom Alter (Apex) script theme:
  alter.plymouth          ModuleName=script theme descriptor
  alter.script            Draws bg + breathing cyan accent + password/msg dialog
  background.png          who_are_you.png, 2560x1440, dark, cyan/teal subject
  accent.png, bullet.png  Cyan accent bar + password bullet dot
  (rollback: sudo plymouth-set-default-theme -R glow — 'glow' is left intact)
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
`~/.config/Yubico/u2f_keys` is missing or malformed. Re-register — note the
file holds **both** keys on one line, so re-register both:
`pamu2fcfg -u alt > ~/.config/Yubico/u2f_keys` with the primary plugged in
(touch required), then swap to the backup key and
`pamu2fcfg -u alt -n >> ~/.config/Yubico/u2f_keys`, and merge the second
output onto the single `alt:…` line (credentials are `:`-separated).

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
`cp ~/scripts/productivity_tools/os_builder/fedora-postinstall/configs/hyprland.conf \
    ~/.config/hypr/hyprland.conf` and patch the polkit-gnome path from
`/usr/libexec/…` (Fedora) to `/usr/lib/polkit-gnome/…` (Arch).
(The live config is also tracked in the `~/.dots/hypr` repo.)

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

- **Pre-change config snapshots:** `/root/backups/` — timestamped copies of
  `crypttab` (x2), `mkinitcpio.conf`, `arch.conf`, `pacman.conf`,
  `plymouthd.conf`, a full `pam.d.<stamp>/` directory, and a **LUKS header
  backup of CryptLVM_Home** (`CryptLVM_Home.header.20260719-234054`, taken
  before the keyfile slot was added).
- **Ready-to-paste dotfiles:** `fedora-postinstall/configs/` (next to this file).
- **Replay script:** `complete_arch_run.sh` (next to this file).
- **Original (Fedora) install script:** `fedora-postinstall/arch-install.sh` —
  historical reference; do **not** run on Arch (uses `dnf`).

> **Missing as of 2026-07-20:** `/mnt/data/alt_backup/` (the NixOS home
> snapshot captured 2026-05-26 and the original copy of these files) **no
> longer exists** on `/mnt/data`. If that snapshot was moved elsewhere, update
> this note; if it was deleted, the NixOS-era home backup is gone.

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
