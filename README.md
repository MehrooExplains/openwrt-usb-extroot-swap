# openwrt-usb-extroot-swap

<p align="center">
  <strong>English</strong> | <a href="README.fa.md">فارسی</a>
</p>

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

After reboot, OpenWrt continues to boot from its normal firmware, but the writable overlay is moved to the USB drive. This is the standard OpenWrt extroot model and greatly increases the space available for packages.

The project follows OpenWrt's documented extroot approach: `block-mount`, an ext4 external partition, copying the current overlay, and configuring `/etc/config/fstab` by filesystem UUID.

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

## Installation

Clone or copy the project to your OpenWrt router, then run:

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

## License

MIT License.
