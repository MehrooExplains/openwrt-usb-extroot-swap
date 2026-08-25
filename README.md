Failed to create stream fd: Operation not permitted
Failed to create stream fd: Operation not permitted
Failed to create stream fd: Operation not permitted
# openwrt-usb-extroot-swap

<p align="center">
  <strong><img src="https://commons.wikimedia.org/wiki/Special:Redirect/file/Flag_of_the_United_Kingdom.svg?width=48" width="28" alt="United Kingdom flag"> English</strong>
  &nbsp;|&nbsp;
  <a href="README.fa.md"><img src="https://commons.wikimedia.org/wiki/Special:Redirect/file/State_flag_of_the_Imperial_State_of_Iran_(with_standardized_lion_and_sun).svg?width=48" width="28" alt="Iranian Lion and Sun flag"> فارسی</a>
</p>

[![Shell checks](https://github.com/MehrooExplains/openwrt-usb-extroot-swap/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/MehrooExplains/openwrt-usb-extroot-swap/actions/workflows/shellcheck.yml)

Automatically prepares a **USB flash drive for OpenWrt** as:

- a dedicated **swap partition**, with an interactive size menu;
- an **ext4 extroot partition** using all remaining USB space, so OpenWrt can use it as the writable overlay for packages, applications, and configuration.

> **Destructive operation:** the selected USB disk is repartitioned and all data on that disk is erased. The installer requires the exact confirmation text `ERASE /dev/sdX` before touching the partition table.

## Swap choices

The installer offers:

```text
1) 256 MiB
2) 512 MiB
3) 1 GiB
4) 2 GiB
5) Custom size
```

With option 5, you can enter any swap size you want. Examples:

```text
768       -> 768 MiB
768M      -> 768 MiB
1.5G      -> 1536 MiB
3G        -> 3072 MiB
```

A value without a suffix is treated as MiB. The installer validates the requested size and refuses it if the USB drive would not have enough space left for extroot.

The remaining capacity becomes an ext4 extroot partition.

## What it does

```text
USB flash drive
      |
      +-- Partition 1 -> Linux Swap
      |
      +-- Partition 2 -> ext4 -> /overlay (extroot)
```

After reboot, OpenWrt continues to boot from its normal firmware, but the writable overlay is moved to the USB drive. This greatly increases the space available for packages and applications.

The project follows OpenWrt's standard extroot approach: `block-mount`, an ext4 external partition, copying the current overlay, and configuring `/etc/config/fstab` by filesystem UUID.

## Safety design

The installer:

- detects USB block devices automatically;
- skips disks that appear to back `/`, `/rom`, `/overlay`, `/rwm`, `/boot`, or active swap;
- shows disk model and capacity before formatting;
- requires an exact destructive confirmation containing the selected device path;
- backs up `/etc/config/fstab` before changes;
- never formats any disk other than the explicitly confirmed USB disk;
- does not silently select from multiple USB disks.

## Supported OpenWrt environments

The script auto-detects:

- `apk` on newer OpenWrt releases;
- `opkg` on older supported OpenWrt releases.

It installs the required runtime tools:

```text
block-mount
e2fsprogs
parted
swap-utils
kmod-usb-storage
kmod-fs-ext4
```

`kmod-usb-storage-uas` is attempted as an optional package for compatible USB storage.

### Prerequisite preflight order

Before detecting or modifying any USB disk, the installer completes this sequence:

1. Detects `apk` or `opkg`.
2. Checks every required storage package individually.
3. Updates package indexes only when at least one required package is missing.
4. Installs only the missing required packages.
5. Tries the optional UAS driver when it is not already installed.
6. Verifies that every required command is actually available.
7. Continues to fstab and USB detection only after verification succeeds.

If a required package cannot be installed or its command remains unavailable,
the installer stops before partitioning or formatting a disk.

## Requirements before installation

- A recoverable OpenWrt router with `firewall4`-era storage support
- Root SSH access
- One dedicated USB storage device that may be completely erased
- Working internet access for package installation
- Enough USB capacity for the selected swap size plus at least 128 MiB extroot
- A current backup of important router configuration

Disconnect any unrelated USB disks before running the installer. Although the
script applies several safety checks, the final device choice and destructive
confirmation remain the operator's responsibility.

## Files and settings changed

The installer creates two GPT partitions, formats swap and ext4, copies the
current `/overlay`, and adds these named UCI sections:

```text
fstab.usb_extroot
fstab.usb_swap
fstab.rwm       (when the original overlay device can be detected)
```

State and backups are stored under:

```text
/etc/openwrt-usb-extroot-swap/
```

## Quick installation

The installer is available in the repository root as `install.sh`. To run it directly on OpenWrt:

```sh
wget -O /tmp/openwrt-usb-extroot-swap-install.sh \
  https://raw.githubusercontent.com/MehrooExplains/openwrt-usb-extroot-swap/main/install.sh && \
sh /tmp/openwrt-usb-extroot-swap-install.sh
```

If your firmware does not provide `wget` but has `curl`:

```sh
curl -fL \
  https://raw.githubusercontent.com/MehrooExplains/openwrt-usb-extroot-swap/main/install.sh \
  -o /tmp/openwrt-usb-extroot-swap-install.sh && \
sh /tmp/openwrt-usb-extroot-swap-install.sh
```

### Run from a local clone

If you already downloaded or cloned the repository:

```sh
chmod +x install.sh
./install.sh
```

The installer detects safe USB storage candidates, asks for a swap size, displays the final layout, and requires a destructive confirmation.

After the installer finishes, reboot the router.

## Verify after reboot

```sh
df -h / /overlay
cat /proc/swaps
block info
```

If `health-check.sh` was available beside `install.sh` during installation, it is installed as:

```sh
openwrt-usb-extroot-health
```

## Expected result

`/overlay` and `/` should report the capacity of the USB extroot partition, and `/proc/swaps` should list the USB swap partition.

## Disable without erasing the USB drive

```sh
chmod +x disable.sh
./disable.sh
```

This disables the project-created fstab entries. It does **not** repartition or erase the USB drive.

If the original internal overlay cannot be accessed through `/rwm`, boot once without the USB drive and remove the project extroot entry from `/etc/config/fstab`.

## Important notes

- Extroot depends on the USB drive being available early during boot. The installer sets `delay_root=15` to improve reliability on slower USB devices.
- A cheap or failing flash drive can make package storage unreliable. Use a decent-quality drive for a permanent setup.
- Swap on flash is much slower than RAM and causes writes to the USB device. It is useful as protection against out-of-memory situations, not as a replacement for real RAM.
- Sysupgrade behavior and extroot restoration should be tested before relying on the device remotely.

## Troubleshooting and recovery

### USB device is not detected

Check kernel and block-device output:

```sh
dmesg | tail -n 80
block info
ls -l /sys/class/block/
```

Try another USB port, power supply, enclosure, or flash drive. Some storage
devices require `kmod-usb-storage-uas`; the installer attempts it when available.

### Router boots but extroot is not active

```sh
block info
uci show fstab
logread | grep -Ei 'block|mount|extroot|overlay'
df -h / /overlay
```

Confirm that the ext4 UUID matches `fstab.usb_extroot.uuid`. Slow storage may
need a larger `fstab.@global[0].delay_root` value.

### Router fails to boot with the USB drive

Power off the router, remove the USB drive, and boot from internal storage.
Then inspect or remove the project-created fstab sections. Keep a known recovery
method—failsafe mode, serial console, or firmware recovery—available before
deploying extroot on a remote router.

### Swap is missing

```sh
cat /proc/swaps
uci show fstab.usb_swap
block info
```

The configured swap UUID must match the USB swap partition.

## Development checks

All scripts use POSIX `sh` for OpenWrt compatibility. Before submitting a
change, run:

```sh
shellcheck -s sh install.sh health-check.sh disable.sh
sh -n install.sh health-check.sh disable.sh
```

GitHub Actions performs the same ShellCheck validation on pushes and pull
requests that change shell scripts or the workflow.

## License

MIT License.
