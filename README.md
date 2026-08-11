# Solven

![Solven logo](solven-logo-smooth.svg)

Solven is an independent desktop operating system built around the Linux
kernel. This repository currently implements a small x86_64 Linux kernel, a
static BusyBox userspace, an initramfs that opens a root shell, and minimal
VirtIO networking for QEMU.

The prototype boots directly in QEMU without a bootloader, disk image,
installer, package manager, network manager, systemd, or desktop environment.

## Pinned upstream sources

| Component | Version | Authoritative source |
| --- | --- | --- |
| Linux | 6.12.103 LTS | `https://cdn.kernel.org/pub/linux/kernel/v6.x/` |
| BusyBox | 1.37.0 | `https://busybox.net/downloads/` |

`build.sh` verifies both archives against pinned SHA-256 checksums published by
their upstream projects before extracting or building them.

- Linux: `f143aaade8877ba5616e788b4482576db28481bcf557ef537f4fcc3938fc3176`
  from `https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc`
- BusyBox: `3311dff32e746499f4df0d5df04d7eb396382d7e108bb9250e7b519b837043a4`
  from `https://busybox.net/downloads/busybox-1.37.0.tar.bz2.sha256`

## Host requirements

The prototype supports an x86_64 Linux build host and target. It requires:

- Bash
- GNU make and a native C toolchain with static libc support
- `bc`, `bison`, `flex`, and Perl for the Linux build
- GNU coreutils, `tar`, `xz`, and `bzip2`
- `cpio`, `gzip`, `find`, and `sort` for the initramfs
- `curl` and `sha256sum` for verified downloads
- `qemu-system-x86_64` to run Solven

The build exits with a list of missing commands before downloading anything.

## Build and run

```sh
./build.sh
./run.sh
```

The build products are:

```text
out/bzImage
out/initramfs.cpio.gz
```

QEMU uses the current terminal as the serial console. After booting, Solven
prints:

```text
Welcome to Solven
/ #
```

Press `Ctrl-a`, then `x`, to exit QEMU.

Set `JOBS` to control parallel compilation, for example `JOBS=4 ./build.sh`.

## Networking

QEMU provides a VirtIO network device connected to its unprivileged user-mode
network. During boot, BusyBox `udhcpc` requests an IPv4 lease for `eth0`. Its
lease hook configures the address, default route, and `/etc/resolv.conf`.
Networking failure is non-fatal and the root shell always starts.

QEMU normally assigns `10.0.2.15`, with gateway `10.0.2.2` and DNS server
`10.0.2.3`. Check the live configuration with:

```sh
ip addr
ip route
cat /etc/resolv.conf
ping -c 1 10.0.2.2
wget http://example.com
```

BusyBox internal TLS support is enabled, so this bootstrap test is also
available:

```sh
wget https://example.com
```

BusyBox 1.37.0's internal TLS implementation encrypts traffic but does not
authenticate certificates or fully validate incoming signatures. It is useful
only for this isolated bootstrap milestone and must not be treated as a secure
HTTPS client. A future trusted downloader will require certificate validation;
curl and its dependency chain are intentionally not added yet.

## Project layout

- `config/`: pinned Linux and BusyBox build configurations
- `rootfs/`: Solven-owned files overlaid onto the BusyBox installation
- `scripts/`: small build helpers
- `sources/`: downloaded, checksum-verified source archives
- `work/`: extracted sources, build trees, and rootfs staging
- `out/`: final boot artifacts

The contents of `sources/`, `work/`, and `out/` are generated and excluded from
version control.

## Reproducibility scope

Versions, source checksums, configurations, build identity, archive ordering,
and archive timestamps are fixed. Exact binary identity can still vary with the
host compiler and toolchain. Pinning an entire toolchain can be added later if
bit-for-bit builds across different hosts become a project requirement.
