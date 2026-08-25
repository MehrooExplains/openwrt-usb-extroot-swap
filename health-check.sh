#!/bin/sh
# SPDX-License-Identifier: MIT

set -u

ok()   { printf '[OK]   %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; FAILS=$((FAILS + 1)); }

FAILS=0
STATE=/etc/openwrt-usb-extroot-swap/state

if [ -r "$STATE" ]; then
    # shellcheck disable=SC1090
    . "$STATE"
    ok "Project state file found"
else
    warn "Project state file not found; running generic checks"
    EXT_UUID=""
fi

if grep -qE '[[:space:]]/overlay[[:space:]]' /proc/mounts; then
    OVERLAY_DEV="$(awk '$2=="/overlay" {print $1; exit}' /proc/mounts)"
    ok "/overlay is mounted from $OVERLAY_DEV"
else
    fail "/overlay is not mounted as a separate filesystem"
fi

if [ -n "${EXT_UUID:-}" ]; then
    if block info 2>/dev/null | grep -q "UUID=\"$EXT_UUID\""; then
        ok "Extroot UUID is visible"
    else
        fail "Extroot UUID is not visible"
    fi
fi

if awk 'NR>1 {found=1} END {exit !found}' /proc/swaps 2>/dev/null; then
    ok "Swap is active"
    cat /proc/swaps
else
    fail "No active swap found"
fi

if uci -q get fstab.usb_extroot >/dev/null 2>&1; then
    ok "fstab extroot entry exists"
else
    fail "fstab extroot entry is missing"
fi

if uci -q get fstab.usb_swap >/dev/null 2>&1; then
    ok "fstab swap entry exists"
else
    fail "fstab swap entry is missing"
fi

printf '\nFilesystem usage:\n'
df -h / /overlay 2>/dev/null || true

printf '\nMemory and swap:\n'
free -m 2>/dev/null || cat /proc/meminfo | head

if [ "$FAILS" -eq 0 ]; then
    printf '\nAll essential checks passed.\n'
    exit 0
fi

printf '\n%d check(s) failed.\n' "$FAILS"
exit 1
