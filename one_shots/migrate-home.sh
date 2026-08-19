#!/usr/bin/env bash
#
# migrate-home.sh — run from an Arch ISO live environment (or rescue target)
#
# What it does, in stages:
#   prep     : unlock existing LUKS containers, activate VGs, sanity checks
#   format   : wipe nvme0n1, create GPT + LUKS2 + LVM (vg2/lv_home) + ext4
#   copy     : rsync old /home -> new /home
#   swap     : rename vg0/home -> vg0/home_old (rollback point),
#              update fstab + crypttab on the installed system
#   reclaim  : lvremove vg0/home_old, lvextend vg0/root +100%FREE (online resize)
#   enroll   : systemd-cryptenroll FIDO2 token on the new LUKS container
#
# Run stages one at a time:  ./migrate-home.sh format
# Or everything up to reclaim: ./migrate-home.sh all   (reclaim/enroll stay manual)
#
# VERIFY EVERY DEVICE PATH BELOW BEFORE RUNNING. Device names can change
# between boots; the LUKS UUIDs below are from your lsblk and are stable.

set -euo pipefail

### ------------------------- configuration -------------------------------
NEW_DISK="/dev/nvme0n1"                 # the old Windows drive — WILL BE WIPED
NEW_PART="${NEW_DISK}p1"

MAIN_LUKS_UUID="3d90dce3-b4cf-4c12-9422-94b6ca882103"   # nvme1n1p2 (vg0: root/home/swap)
DATA_LUKS_UUID="e37ade15-d8e7-429a-be6e-2168fb3f5a6d"   # sda1 (vg1: data) — optional here

NEW_MAPPER="CryptLVM_Home"              # dm name for the new container
NEW_VG="vg2"
NEW_LV="lv_home"

MNT_OLD="/mnt/oldhome"
MNT_NEW="/mnt/newhome"
MNT_ROOT="/mnt/sysroot"                 # installed system's / (for fstab/crypttab edits)
### ------------------------------------------------------------------------

die()     { echo "ERROR: $*" >&2; exit 1; }
confirm() { read -rp "$1 [type YES to continue] " a; [[ "$a" == "YES" ]] || die "aborted"; }

stage_prep() {
    echo "== prep: unlocking existing containers and activating LVM =="

    # Show existing LUKS2 params so you can confirm the new format matches.
    echo "--- luksDump of existing main container (cipher/pbkdf reference) ---"
    cryptsetup luksDump "/dev/disk/by-uuid/${MAIN_LUKS_UUID}" | grep -E 'Cipher|PBKDF|Hash|sector' || true
    echo "---------------------------------------------------------------------"

    [[ -e /dev/mapper/CryptLVM_Main ]] || \
        cryptsetup open "/dev/disk/by-uuid/${MAIN_LUKS_UUID}" CryptLVM_Main

    #vgchange -ay vg0
    #lvs vg0 || die "vg0 not visible"
    echo "prep done."
}

stage_format() {
    echo "== format: THIS DESTROYS ALL DATA ON ${NEW_DISK} =="
    lsblk -f "$NEW_DISK"
    confirm "Wipe ${NEW_DISK} (the old Windows disk) completely?"

    # Make sure nothing on it is mounted/open
    umount -R "${NEW_DISK}"* 2>/dev/null || true

    wipefs -a "$NEW_DISK"
    sgdisk -Z "$NEW_DISK"
    sgdisk -n 1:0:0 -t 1:8309 -c 1:cryptlvm-home "$NEW_DISK"   # 8309 = Linux LUKS
    partprobe "$NEW_DISK"; sleep 2

    # LUKS2 defaults = aes-xts-plain64 + argon2id, same as your existing drives.
    # You'll set a passphrase here; the FIDO2 token gets enrolled in a later stage.
    cryptsetup luksFormat --type luks2 --label CryptLVM_Home "$NEW_PART"
    cryptsetup open "$NEW_PART" "$NEW_MAPPER"

    pvcreate "/dev/mapper/${NEW_MAPPER}"
    vgcreate "$NEW_VG" "/dev/mapper/${NEW_MAPPER}"
    # 100%FREE is fine; use e.g. -l 95%FREE instead if you want snapshot headroom.
    lvcreate -l 95%FREE -n "$NEW_LV" "$NEW_VG"
    mkfs.ext4 -L home "/dev/${NEW_VG}/${NEW_LV}"
    echo "format done. New LUKS UUID: $(cryptsetup luksUUID "$NEW_PART")"
}

stage_copy() {
    echo "== copy: rsync vg0/home -> ${NEW_VG}/${NEW_LV} =="
    mkdir -p "$MNT_OLD" "$MNT_NEW"
    mountpoint -q "$MNT_OLD" || mount -o ro /dev/vg0/home "$MNT_OLD"
    mountpoint -q "$MNT_NEW" || mount "/dev/${NEW_VG}/${NEW_LV}" "$MNT_NEW"

    rsync -aHAXS --numeric-ids --info=progress2 "${MNT_OLD}/" "${MNT_NEW}/"

    echo "--- quick verification ---"
    df -h "$MNT_OLD" "$MNT_NEW"
    diff <(cd "$MNT_OLD" && find . | sort) <(cd "$MNT_NEW" && find . | sort) \
        && echo "file lists match" || echo "WARNING: file lists differ — investigate before proceeding"
}

stage_swap() {
    echo "== swap: rename old home LV (rollback point) and update system config =="
    confirm "Rename vg0/home -> vg0/home_old and edit fstab/crypttab?"

    umount "$MNT_OLD" 2>/dev/null || true
    lvrename vg0 home home_old

    mkdir -p "$MNT_ROOT"
    mountpoint -q "$MNT_ROOT" || mount /dev/vg0/root "$MNT_ROOT"

    local new_luks_uuid new_fs_uuid
    new_luks_uuid=$(cryptsetup luksUUID "$NEW_PART")
    new_fs_uuid=$(blkid -s UUID -o value "/dev/${NEW_VG}/${NEW_LV}")

    cp -a "$MNT_ROOT/etc/fstab"    "$MNT_ROOT/etc/fstab.bak"
    cp -a "$MNT_ROOT/etc/crypttab" "$MNT_ROOT/etc/crypttab.bak" 2>/dev/null || true

    # fstab: point /home at the new filesystem UUID
    sed -i -E "s|^UUID=2d248371-fd46-44d3-acb7-a55887c68b5f|UUID=${new_fs_uuid}|" \
        "$MNT_ROOT/etc/fstab"
    grep -q "$new_fs_uuid" "$MNT_ROOT/etc/fstab" || \
        echo "UUID=${new_fs_uuid}  /home  ext4  defaults  0 2" >> "$MNT_ROOT/etc/fstab"

    # crypttab: unlock the new container at boot with the FIDO2 token.
    # >>> Compare with your existing sda line and mirror its options exactly. <<<
    echo "${NEW_MAPPER}  UUID=${new_luks_uuid}  none  fido2-device=auto" \
        >> "$MNT_ROOT/etc/crypttab"

    echo "--- review these before rebooting ---"
    grep -v '^#' "$MNT_ROOT/etc/fstab"
    echo "-----"
    cat "$MNT_ROOT/etc/crypttab"
}

stage_reclaim() {
    echo "== reclaim: DELETE vg0/home_old and grow root =="
    echo "Only do this after you've booted the system and confirmed /home is intact."
    confirm "Permanently destroy vg0/home_old and extend vg0/root?"
    lvremove -y vg0/home_old
    lvextend -l +100%FREE -r vg0/root      # -r grows ext4 too; works online
    df -h /
}

stage_enroll() {
    echo "== enroll: add FIDO2 token to the new LUKS container =="
    # Needs the passphrase you set during format. Touch the key when it blinks.
    systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=no "$NEW_PART"
    cryptsetup luksDump "$NEW_PART" | grep -A2 'Tokens'
}

case "${1:-}" in
    prep)    stage_prep ;;
    format)  stage_format ;;
    copy)    stage_copy ;;
    swap)    stage_swap ;;
    reclaim) stage_reclaim ;;
    enroll)  stage_enroll ;;
    all)     stage_prep; stage_format; stage_copy; stage_swap
             echo; echo "Now reboot into the installed system, verify /home,"
             echo "then run the 'reclaim' stage (works online, no USB needed)." ;;
    *) echo "usage: $0 {prep|format|copy|swap|reclaim|enroll|all}"; exit 1 ;;
esac
