#!/bin/sh
# Disable the extroot/swap entries created by openwrt-usb-extroot-swap.
# This does NOT repartition or erase the USB drive.
# SPDX-License-Identifier: MIT

set -eu

log() { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }

[ "$(id -u)" = "0" ] || { echo "Run as root." >&2; exit 1; }

uci -q delete fstab.usb_extroot || true
uci -q delete fstab.usb_swap || true
uci commit fstab
log "Disabled project extroot/swap entries in the currently active /etc/config/fstab."

# If /rwm exposes the original internal overlay, disable the same entries there too.
if [ -d /rwm/upper/etc/config ] && [ -f /rwm/upper/etc/config/fstab ]; then
    if uci -c /rwm/upper/etc/config -q delete fstab.usb_extroot 2>/dev/null; then
        uci -c /rwm/upper/etc/config -q delete fstab.usb_swap 2>/dev/null || true
        uci -c /rwm/upper/etc/config commit fstab
        log "Disabled extroot/swap entries in the original internal overlay as well."
    else
        warn "Could not update the internal /rwm fstab automatically."
    fi
else
    warn "/rwm internal overlay is not available. If extroot remains active after reboot, boot once without the USB drive and remove fstab.usb_extroot from /etc/config/fstab."
fi

if [ -r /etc/openwrt-usb-extroot-swap/state ]; then
    # shellcheck source=/dev/null
    . /etc/openwrt-usb-extroot-swap/state
    swapoff "${SWAP_PART:-}" 2>/dev/null || true
fi

printf '\nReboot without the USB drive if you want to return to internal storage immediately.\n'
