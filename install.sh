#!/bin/sh
# openwrt-usb-extroot-swap
# Safely prepare a USB drive as swap + extroot for OpenWrt.
# SPDX-License-Identifier: MIT

set -eu

PROJECT="openwrt-usb-extroot-swap"
STATE_DIR="/etc/${PROJECT}"
TMP_DIR="/tmp/${PROJECT}.$$"
MOUNT_DIR="${TMP_DIR}/extroot"
BACKUP_DIR="${STATE_DIR}/backups/$(date +%Y%m%d-%H%M%S)"

log()  { printf '%s\n' "[+] $*"; }
warn() { printf '%s\n' "[!] $*" >&2; }
die()  { printf '%s\n' "[x] $*" >&2; exit 1; }

cleanup() {
    umount "$MOUNT_DIR" 2>/dev/null || true
    rm -rf "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

[ "$(id -u)" = "0" ] || die "Run this installer as root."
[ -r /etc/openwrt_release ] || die "This installer is for OpenWrt only."
# shellcheck source=/dev/null
. /etc/openwrt_release

mkdir -p "$TMP_DIR" "$MOUNT_DIR" "$STATE_DIR" "$BACKUP_DIR"

if command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    pkg_update() { apk update; }
    pkg_install() { apk add "$@"; }
elif command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
    pkg_update() { opkg update; }
    pkg_install() { opkg install "$@"; }
else
    die "Neither apk nor opkg was found."
fi

log "OpenWrt: ${DISTRIB_RELEASE:-unknown}"
log "Architecture: ${DISTRIB_ARCH:-unknown}"
log "Package manager: $PKG_MGR"

log "Updating package indexes..."
pkg_update || warn "Package index update returned an error; continuing with available indexes."

log "Installing required storage tools..."
pkg_install block-mount e2fsprogs parted swap-utils kmod-usb-storage kmod-fs-ext4 \
    || die "Could not install required storage packages."

# UAS is optional. Some USB 3 storage devices use it; classic flash drives do not require it.
pkg_install kmod-usb-storage-uas >/dev/null 2>&1 || true

for cmd in parted mkswap mkfs.ext4 block uci tar mount umount swapon swapoff; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' is missing."
done

if [ ! -f /etc/config/fstab ]; then
    log "Creating initial /etc/config/fstab..."
    block detect | uci import fstab
    uci commit fstab
fi

# Refuse to stack a second extroot on top of an existing one.
if uci -q show fstab 2>/dev/null | grep -q "target='/overlay'"; then
    die "An extroot entry already exists in /etc/config/fstab. Disable the existing extroot before running this installer."
fi

human_mib() {
    kib="$1"
    printf '%s MiB' "$((kib / 1024))"
}

block_size_mib() {
    name="$1"
    sectors="$(cat "/sys/class/block/$name/size" 2>/dev/null || echo 0)"
    printf '%s' "$((sectors / 2048))"
}

block_model() {
    name="$1"
    vendor="$(cat "/sys/class/block/$name/device/vendor" 2>/dev/null | sed 's/[[:space:]]*$//' || true)"
    model="$(cat "/sys/class/block/$name/device/model" 2>/dev/null | sed 's/[[:space:]]*$//' || true)"
    printf '%s %s' "$vendor" "$model" | sed 's/^ *//; s/ *$//'
}

is_usb_disk() {
    name="$1"
    [ -e "/sys/class/block/$name" ] || return 1
    [ -e "/sys/class/block/$name/partition" ] && return 1
    case "$name" in
        sd[a-z]|sd[a-z][a-z]) ;;
        *) return 1 ;;
    esac
    path="$(readlink -f "/sys/class/block/$name/device" 2>/dev/null || true)"
    removable="$(cat "/sys/class/block/$name/removable" 2>/dev/null || echo 0)"
    [ "$removable" = "1" ] && return 0
    printf '%s' "$path" | grep -q '/usb' && return 0
    return 1
}

is_system_disk() {
    name="$1"
    dev="/dev/$name"

    # If the kernel command line explicitly boots from this disk, never touch it.
    grep -qE "root=${dev}([0-9]|p[0-9])?([[:space:]]|$)" /proc/cmdline 2>/dev/null && return 0

    # Never offer a disk that currently backs critical mount points.
    awk -v d="$dev" '
        index($1,d)==1 && ($2=="/" || $2=="/rom" || $2=="/overlay" || $2=="/rwm" || $2=="/boot" || $2=="/boot/efi") {found=1}
        END {exit !found}
    ' /proc/mounts && return 0

    # Never offer a disk with active swap. It may already be part of a working setup.
    awk -v d="$dev" 'NR>1 && index($1,d)==1 {found=1} END {exit !found}' /proc/swaps 2>/dev/null && return 0

    return 1
}

CANDIDATES=""
for sysdev in /sys/class/block/sd*; do
    [ -e "$sysdev" ] || continue
    name="$(basename "$sysdev")"
    is_usb_disk "$name" || continue
    if is_system_disk "$name"; then
        warn "Skipping /dev/$name because it appears to be in use by the running system."
        continue
    fi
    CANDIDATES="$CANDIDATES $name"
done

# Device names come only from /sys/class/block and cannot contain whitespace or globs.
# shellcheck disable=SC2086
set -- $CANDIDATES
[ "$#" -gt 0 ] || die "No safe USB storage device was detected. Connect a USB flash drive and run the installer again."

printf '\nDetected USB storage devices:\n\n'
i=1
for name in "$@"; do
    size="$(block_size_mib "$name")"
    model="$(block_model "$name")"
    [ -n "$model" ] || model="Unknown model"
    printf '  %d) /dev/%s  -  %s MiB  -  %s\n' "$i" "$name" "$size" "$model"
    i=$((i + 1))
done

if [ "$#" -eq 1 ]; then
    SELECTED="$1"
    log "One safe USB disk detected; selecting /dev/$SELECTED."
else
    printf '\nSelect the USB disk number: ' >/dev/tty
    IFS= read -r choice </dev/tty
    case "$choice" in *[!0-9]*|'') die "Invalid selection." ;; esac
    [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$#" ] 2>/dev/null || die "Selection out of range."
    eval "SELECTED=\${$choice}"
fi

DISK="/dev/$SELECTED"
DISK_MIB="$(block_size_mib "$SELECTED")"
MODEL="$(block_model "$SELECTED")"

printf '\nSwap size:\n\n'
printf '  1) 256 MiB\n'
printf '  2) 512 MiB\n'
printf '  3) 1 GiB\n'
printf '  4) 2 GiB\n'
printf '  5) Custom size\n'
printf '\nChoose 1-5: ' >/dev/tty
IFS= read -r swap_choice </dev/tty
case "$swap_choice" in
    1) SWAP_MIB=256 ;;
    2) SWAP_MIB=512 ;;
    3) SWAP_MIB=1024 ;;
    4) SWAP_MIB=2048 ;;
    5)
        printf '\nEnter custom swap size. Examples: 768, 768M, 1.5G, 3G\n' >/dev/tty
        printf 'A number without a suffix is treated as MiB.\n> ' >/dev/tty
        IFS= read -r custom_swap </dev/tty
        custom_swap="$(printf '%s' "$custom_swap" | tr '[:lower:]' '[:upper:]' | tr -d ' ')"
        case "$custom_swap" in
            *GIB) custom_num="${custom_swap%GIB}"; custom_unit=G ;;
            *GB)  custom_num="${custom_swap%GB}";  custom_unit=G ;;
            *G)   custom_num="${custom_swap%G}";   custom_unit=G ;;
            *MIB) custom_num="${custom_swap%MIB}"; custom_unit=M ;;
            *MB)  custom_num="${custom_swap%MB}";  custom_unit=M ;;
            *M)   custom_num="${custom_swap%M}";   custom_unit=M ;;
            *)    custom_num="$custom_swap"; custom_unit=M ;;
        esac
        case "$custom_num" in
            ''|*[!0-9.]*) die "Invalid custom swap size." ;;
        esac
        case "$custom_num" in
            *.*.*) die "Invalid custom swap size." ;;
        esac
        if [ "$custom_unit" = "G" ]; then
            SWAP_MIB="$(awk -v n="$custom_num" 'BEGIN { v=n*1024; if (v < 1) exit 1; printf "%.0f", v }')" \
                || die "Invalid custom swap size."
        else
            SWAP_MIB="$(awk -v n="$custom_num" 'BEGIN { if (n < 1) exit 1; printf "%.0f", n }')" \
                || die "Invalid custom swap size."
        fi
        ;;
    *) die "Invalid swap size selection." ;;
esac

case "$SWAP_MIB" in
    ''|*[!0-9]*) die "Invalid calculated swap size." ;;
esac
[ "$SWAP_MIB" -ge 16 ] 2>/dev/null || die "Swap size must be at least 16 MiB."

# Leave at least 128 MiB for extroot. In practice users should use much more.
MIN_EXTROOT_MIB=128
[ "$DISK_MIB" -gt $((SWAP_MIB + MIN_EXTROOT_MIB + 2)) ] \
    || die "The selected USB drive is too small for ${SWAP_MIB} MiB swap plus extroot."

printf '\n============================================================\n'
printf 'DESTRUCTIVE OPERATION\n'
printf '============================================================\n'
printf 'Selected disk : %s\n' "$DISK"
printf 'Model         : %s\n' "${MODEL:-Unknown}"
printf 'Disk size     : %s MiB\n' "$DISK_MIB"
printf 'Swap          : %s MiB\n' "$SWAP_MIB"
printf 'Extroot       : remaining space\n'
printf '\nALL DATA ON %s WILL BE PERMANENTLY ERASED.\n' "$DISK"
printf 'No other disk will be modified.\n\n'
printf 'To continue, type exactly: ERASE %s\n> ' "$DISK" >/dev/tty
IFS= read -r confirm </dev/tty
[ "$confirm" = "ERASE $DISK" ] || die "Confirmation did not match. Nothing was changed."

# Unmount ordinary auto-mounted partitions on the selected disk. Critical disks were filtered earlier.
for p in "/dev/${SELECTED}"[0-9]* "/dev/${SELECTED}"p[0-9]*; do
    [ -e "$p" ] || continue
    umount "$p" 2>/dev/null || true
done

log "Backing up current fstab..."
cp -a /etc/config/fstab "$BACKUP_DIR/fstab.before" 2>/dev/null || true

log "Creating GPT partition table..."
SWAP_END=$((SWAP_MIB + 1))
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary linux-swap 1MiB "${SWAP_END}MiB"
parted -s "$DISK" mkpart primary ext4 "${SWAP_END}MiB" 100%
parted -s "$DISK" set 1 swap on 2>/dev/null || true
sync
sleep 2

part_path() {
    disk="$1"
    n="$2"
    case "$disk" in
        *[0-9]) printf '%sp%s' "$disk" "$n" ;;
        *) printf '%s%s' "$disk" "$n" ;;
    esac
}

SWAP_PART="$(part_path "$DISK" 1)"
EXT_PART="$(part_path "$DISK" 2)"

wait_for_node() {
    node="$1"
    n=0
    while [ ! -b "$node" ] && [ "$n" -lt 15 ]; do
        sleep 1
        n=$((n + 1))
    done
    [ -b "$node" ]
}

wait_for_node "$SWAP_PART" || die "Partition node $SWAP_PART did not appear. Replug the USB drive and inspect the partition table before retrying."
wait_for_node "$EXT_PART" || die "Partition node $EXT_PART did not appear. Replug the USB drive and inspect the partition table before retrying."

log "Formatting swap partition..."
mkswap -L OPENWRT_SWAP "$SWAP_PART" >/dev/null

log "Formatting extroot partition as ext4..."
mkfs.ext4 -F -m 0 -L OPENWRT_EXTROOT "$EXT_PART" >/dev/null
sync
sleep 1

get_uuid() {
    dev="$1"
    block info "$dev" 2>/dev/null | sed -n 's/.*UUID="\([^"]*\)".*/\1/p' | head -n 1
}

SWAP_UUID="$(get_uuid "$SWAP_PART")"
EXT_UUID="$(get_uuid "$EXT_PART")"
[ -n "$SWAP_UUID" ] || die "Could not read swap UUID."
[ -n "$EXT_UUID" ] || die "Could not read extroot UUID."

ORIG_OVERLAY_DEV="$(awk '$2=="/overlay" {print $1; exit}' /proc/mounts 2>/dev/null || true)"
OVERLAY_SRC="/overlay"
[ -d "$OVERLAY_SRC" ] || die "Current /overlay directory was not found."

# Ensure there is a global section and give USB storage enough time during preinit.
if ! uci -q get fstab.@global[0] >/dev/null 2>&1; then
    uci add fstab global >/dev/null
fi
uci set fstab.@global[0].delay_root='15'

uci -q delete fstab.usb_extroot
uci set fstab.usb_extroot='mount'
uci set fstab.usb_extroot.uuid="$EXT_UUID"
uci set fstab.usb_extroot.target='/overlay'
uci set fstab.usb_extroot.enabled='1'
uci set fstab.usb_extroot.fstype='ext4'
uci set fstab.usb_extroot.options='rw,noatime'

uci -q delete fstab.usb_swap
uci set fstab.usb_swap='swap'
uci set fstab.usb_swap.uuid="$SWAP_UUID"
uci set fstab.usb_swap.enabled='1'

# Optional but useful: expose the original internal writable overlay as /rwm after extroot boots.
if [ -n "$ORIG_OVERLAY_DEV" ]; then
    uci -q delete fstab.rwm
    uci set fstab.rwm='mount'
    uci set fstab.rwm.device="$ORIG_OVERLAY_DEV"
    uci set fstab.rwm.target='/rwm'
    uci set fstab.rwm.enabled='1'
fi

uci commit fstab
cp -a /etc/config/fstab "$BACKUP_DIR/fstab.configured"

log "Copying current OpenWrt overlay to the USB extroot partition..."
mount "$EXT_PART" "$MOUNT_DIR"
# Avoid stale extroot identity files if the drive was previously used for extroot.
rm -f "$MOUNT_DIR/.extroot-uuid" "$MOUNT_DIR/etc/.extroot-uuid" 2>/dev/null || true
# BusyBox tar preserves ownership/permissions when run as root.
tar -C "$OVERLAY_SRC" -cf - . | tar -C "$MOUNT_DIR" -xf -
sync
umount "$MOUNT_DIR"

cat > "$STATE_DIR/state" <<EOF_STATE
DISK='$DISK'
SWAP_PART='$SWAP_PART'
EXT_PART='$EXT_PART'
SWAP_UUID='$SWAP_UUID'
EXT_UUID='$EXT_UUID'
ORIG_OVERLAY_DEV='$ORIG_OVERLAY_DEV'
BACKUP_DIR='$BACKUP_DIR'
EOF_STATE
chmod 600 "$STATE_DIR/state"

# Install health checker if the script is being run from a cloned project directory.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/health-check.sh" ]; then
    cp "$SCRIPT_DIR/health-check.sh" /usr/bin/openwrt-usb-extroot-health
    chmod 755 /usr/bin/openwrt-usb-extroot-health
fi

log "Enabling swap now for a quick sanity check..."
swapon "$SWAP_PART" 2>/dev/null || warn "Swap could not be enabled immediately; fstab will try again at boot."

printf '\nInstallation prepared successfully.\n\n'
printf 'USB disk       : %s\n' "$DISK"
printf 'Swap partition : %s (%s MiB)\n' "$SWAP_PART" "$SWAP_MIB"
printf 'Extroot        : %s (remaining space)\n' "$EXT_PART"
printf 'Extroot UUID   : %s\n' "$EXT_UUID"
printf 'Swap UUID      : %s\n' "$SWAP_UUID"
printf '\nA reboot is required for extroot to become the active OpenWrt overlay.\n'
printf 'After reboot, verify with:\n\n'
printf '  df -h / /overlay\n'
printf '  cat /proc/swaps\n'
printf '  block info\n\n'
printf 'Reboot now? [y/N]: ' >/dev/tty
IFS= read -r reboot_now </dev/tty
case "$reboot_now" in
    y|Y|yes|YES) sync; reboot ;;
    *) log "Reboot skipped. Reboot manually when ready." ;;
esac
