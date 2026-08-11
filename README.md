# Solven

![Solven logo](solven-logo-smooth.svg)

Solven is an independent desktop operating system built around the Linux
kernel. This repository currently implements a small x86_64 Linux kernel, a
static BusyBox userspace, an initramfs that opens a root shell, VirtIO
networking for QEMU, and certificate-validated HTTPS with a static curl client.

The prototype boots directly in QEMU without a bootloader, disk image,
installer, package manager, network manager, systemd, or desktop environment.

## Pinned upstream sources

| Component | Version | Authoritative source |
| --- | --- | --- |
| Linux | 6.12.103 LTS | `https://cdn.kernel.org/pub/linux/kernel/v6.x/` |
| BusyBox | 1.37.0 | `https://busybox.net/downloads/` |
| Mbed TLS | 3.6.7 LTS | `https://github.com/Mbed-TLS/mbedtls/releases/` |
| curl | 8.21.0 | `https://curl.se/download/` |
| Mozilla CA extract | 2026-07-16 | `https://curl.se/docs/caextract.html` |

`build.sh` verifies every downloaded artifact against a pinned SHA-256 checksum
before extracting, building, or staging it.

- Linux: `f143aaade8877ba5616e788b4482576db28481bcf557ef537f4fcc3938fc3176`
  from `https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc`
- BusyBox: `3311dff32e746499f4df0d5df04d7eb396382d7e108bb9250e7b519b837043a4`
  from `https://busybox.net/downloads/busybox-1.37.0.tar.bz2.sha256`
- Mbed TLS: `a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6`
- curl: `aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6`
- CA bundle: `3ff344e30b9b1ed2971044eabb438a08f2e2245ddb5f8ab1a3ad8b63ab4eaf91`

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
network. During boot, Solven enables loopback and BusyBox `udhcpc` requests an
IPv4 lease for `eth0`. Its lease hook configures the address, default route,
and `/etc/resolv.conf`. Networking failure is non-fatal and the root shell
always starts.

QEMU normally assigns `10.0.2.15`, with gateway `10.0.2.2` and DNS server
`10.0.2.3`. Check the live configuration with:

```sh
ip addr
ip route
cat /etc/resolv.conf
ping -c 1 127.0.0.1
ping -c 1 10.0.2.2
ping -c 1 example.com
curl --fail http://example.com/
curl --fail https://example.com/
```

The curl binary is statically linked with Mbed TLS and supports only HTTP and
HTTPS over IPv4. Its default trust store is the pinned Mozilla-derived bundle
at `/etc/ssl/certs/ca-certificates.crt`; the HTTPS command above performs normal
hostname and certificate-chain validation without `-k`.

BusyBox `wget` remains available for simple HTTP bootstrap diagnostics. Its
internal HTTPS implementation does not authenticate certificates and must not
be used where peer identity matters.

## Project layout

- `config/`: pinned Linux and BusyBox build configurations
- `rootfs/`: Solven-owned files overlaid onto the BusyBox installation
- `scripts/`: small build helpers
- `sources/`: downloaded, checksum-verified source archives
- `work/`: extracted sources, build trees, and rootfs staging
- `out/`: final boot artifacts

The contents of `sources/`, `work/`, and `out/` are generated and excluded from
version control.

## Licensing

Solven-authored scripts carrying an SPDX notice are licensed under
GPL-2.0-or-later; the full text is in `LICENSE`. Generated boot artifacts also
contain independently licensed upstream components and are not wholly covered
by that license. See `THIRD_PARTY.md` for component licenses and source details.

## Reproducibility scope

Versions, source checksums, configurations, build identity, archive ordering,
and archive timestamps are fixed. Exact binary identity can still vary with the
host compiler and toolchain. Pinning an entire toolchain can be added later if
bit-for-bit builds across different hosts become a project requirement.
