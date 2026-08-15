# Solven

![Solven logo](solven-logo-smooth.svg)

Solven is an independent desktop operating system built around the Linux
kernel. This repository currently boots Linux 6.12.103-solven in QEMU, finds a
persistent ext4 system volume by UUID, switches from a minimal initramfs into a
Solven-native root filesystem, configures VirtIO networking, and opens an
interactive root shell.

The bootstrap includes static BusyBox, curl with certificate-validated HTTPS,
GNU nano, command history, shell line editing, and the initial Solven volume
and path model. It intentionally does not include a bootloader, installer,
package manager, service manager, SSH server, Wi-Fi stack, or desktop.

## Pinned upstream sources

| Component | Version | Authoritative source |
| --- | --- | --- |
| Linux | 6.12.103 LTS | `https://cdn.kernel.org/pub/linux/kernel/v6.x/` |
| BusyBox | 1.37.0 | `https://busybox.net/downloads/` |
| Mbed TLS | 3.6.7 LTS | `https://github.com/Mbed-TLS/mbedtls/releases/` |
| curl | 8.21.0 | `https://curl.se/download/` |
| Mozilla CA extract | 2026-07-16 | `https://curl.se/docs/caextract.html` |
| ncurses | 6.6 | `https://ftp.gnu.org/gnu/ncurses/` |
| GNU nano | 9.2 | `https://ftp.gnu.org/gnu/nano/` |

`build.sh` verifies every downloaded artifact against a pinned SHA-256 checksum
before extracting, building, or staging it.

| Component | SHA-256 |
| --- | --- |
| Linux | `f143aaade8877ba5616e788b4482576db28481bcf557ef537f4fcc3938fc3176` |
| BusyBox | `3311dff32e746499f4df0d5df04d7eb396382d7e108bb9250e7b519b837043a4` |
| Mbed TLS | `a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6` |
| curl | `aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6` |
| CA bundle | `3ff344e30b9b1ed2971044eabb438a08f2e2245ddb5f8ab1a3ad8b63ab4eaf91` |
| ncurses | `355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11` |
| GNU nano | `05ecb99247b782e8a5b3a25ed4101dd034b0236902f7449bc9795b717642f7e9` |

## Host requirements

The bootstrap supports an x86_64 Linux build host and target. It requires:

- Bash
- GNU make and a native C toolchain with static libc support
- `bc`, `bison`, `flex`, and Perl for the Linux build
- GNU coreutils, `tar`, `xz`, and `bzip2`
- `cpio`, `gzip`, `find`, and `sort` for the initramfs
- `curl` and `sha256sum` for verified downloads
- e2fsprogs with `mke2fs` archive population support, `debugfs`, and `e2fsck`
- `qemu-system-x86_64` to run Solven

The build exits with a list of missing commands before downloading anything.
It constructs the ext4 image without loop devices, root privileges, or a host
mount. A deterministic tar stream supplies numeric root ownership to
`mke2fs -d`; the filesystem UUID and directory hash seed are fixed.

## Build and run

```sh
./build.sh
./run.sh
```

Set `JOBS` to control parallel compilation, for example `JOBS=4 ./build.sh`.
The build products are:

```text
out/bzImage
out/initramfs.cpio.gz
out/solven-root.ext4
```

`solven-root.ext4` is a 128 MiB persistent VirtIO block image. `build.sh`
atomically replaces it after a successful rebuild; repeated `run.sh`
invocations do not. QEMU uses the current terminal as the serial console. Run
`sync` before pressing `Ctrl-a`, then `x`, because that QEMU shortcut is an
abrupt exit rather than a guest shutdown.

The boot sequence is:

```text
Linux kernel
  -> minimal initramfs
  -> locate the A: volume by ext4 UUID
  -> mount the real root
  -> switch_root
  -> /System/Core/Init/init
  -> interactive shell
```

The initramfs contains only a dedicated minimal BusyBox, the volume registry,
mount points, and `/init`. Normal BusyBox, networking, trust data, curl, nano,
and shell configuration live only on the persistent root.

## Native filesystem

Solven's native filesystem organization is not the Unix filesystem hierarchy.
The initial real root is:

```text
/
|-- System/
|   |-- Core/
|   |-- Store/
|   |-- Commands/
|   |-- Trust/
|   `-- Boot/
|-- Programs/
|   |-- CLI/
|   `-- GUI/
|-- Users/
|   `-- root/
|       |-- Desktop/
|       |-- Documents/
|       |-- Downloads/
|       |-- Pictures/
|       |-- Music/
|       |-- Videos/
|       |-- Programs/{CLI,GUI}/
|       |-- Commands/
|       `-- State/Programs/
|-- State/
|   |-- System/
|   |-- Programs/
|   |-- Keep/
|   |-- Logs/
|   `-- Cache/
|-- Runtime/{System,Programs,Users,Temp}/
|-- Volumes/
|-- Compatibility/Linux/Runtimes/
|-- dev/
|-- proc/
`-- sys/
```

| Path | Purpose |
| --- | --- |
| `/System` | Solven-owned core, command namespace, trust, store reservation, and boot metadata |
| `/Programs` | Installed, self-contained CLI and GUI program bundles |
| `/Users` | Human-owned files, user commands, and per-user program state |
| `/State` | Persistent mutable machine and system-wide program state |
| `/Runtime` | Ephemeral state; mounted as tmpfs on each boot |
| `/Volumes` | Internal mount plumbing for non-root volumes |
| `/Compatibility` | Foreign and legacy runtime environments |
| `/dev`, `/proc`, `/sys` | Linux kernel interfaces retained unchanged |

BusyBox is stored at `/System/Core/BusyBox/busybox`. Its enabled applets are
exposed through links in `/System/Commands`, which is the active system command
namespace. The default path is:

```text
/Users/root/Commands:/System/Commands
```

`/System/Store` is only a reservation for a future immutable, content-addressed
Keep store. No package format, package installation, or Keep implementation is
present. Persistent application state belongs under
`/State/Programs/<publisher>/<program>/` or
`/Users/<user>/State/Programs/<publisher>/<program>/`, never in `/Programs`.

curl and nano are program-owned bundles:

```text
/Programs/CLI/Curl/{Executable,Libraries,Resources,Metadata,Manifest}
/Programs/CLI/Nano/{Executable,Libraries,Resources,Metadata,Manifest}
```

Both executables are static. Their linked libraries are therefore incorporated
into their executable rather than installed into a global library directory.
`/System/Commands/curl` and `/System/Commands/nano` expose them to the shell.

The shipped CA foundation is
`/System/Trust/CA/ca-certificates.crt`. curl is compiled to use that native path
directly. Mutable trust state is reserved under `/State/System/Trust`.

## Volumes and drive paths

Solven separates four layers:

```text
kernel/VFS path
        -> stable volume identity
        -> Solven-native path
        -> human drive alias and path
```

The same root path can be represented as:

```text
Human:          A:/Users/root
Stable identity: volume://9d4cc83f-2f8b-4ab0-a6ef-9b9987746b6a/Users/root
Kernel plumbing: /Users/root
```

The `volume://` form documents the intended stable software identity; this
bootstrap does not implement the URI scheme yet. **Drive letters are aliases,
not volume identity.** The ext4 UUID is authoritative.

The bootstrap registry is installed at `/State/System/Volumes/registry` from
`config/volumes.conf`. It is a pipe-delimited format:

```text
# letter|volume-uuid|name|kernel-mountpoint
A|9d4cc83f-2f8b-4ab0-a6ef-9b9987746b6a|Solven|/
```

Future non-root records will use an internal mount point such as
`/Volumes/<volume-uuid>`. The root volume remains mounted at `/` and is not
duplicated beneath `/Volumes`.

Solven starts with `A:` because it has no floppy-drive compatibility history to
preserve. Additional persistent volumes can use `B:`, `C:`, `D:`, and later
letters while retaining assignments by UUID rather than probe order.

`/System/Core/Path/solpath` is the single bootstrap path translator. It resolves
drive paths from the registry and performs the inverse translation used by the
prompt. Drive-qualified paths reject `..` segments so a future non-root alias
cannot escape its registered mount point:

```sh
solpath --resolve A:/Users/root
solpath --display /Users/root
```

BusyBox ash defines a small `cd` function that delegates drive syntax to
`solpath` and then invokes the shell's real `cd` builtin. These work now:

```sh
cd A:/
cd A:/System
cd A:/Users/root
```

The prompt reevaluates the inverse translation before every command:

```text
solven A:/ # cd A:/System
solven A:/System #
```

Ordinary Linux utilities are not globally wrapped in this milestone. Use an
internal path, or explicitly translate one, when passing a filename to an
external program:

```sh
cat "$(solpath --resolve A:/Users/root/test.txt)"
nano /Users/root/test.txt
```

Direct `A:/...` handling in Solven-native APIs and external programs is a later
milestone.

## Shell and nano

BusyBox command editing, persistent history, tab completion, fancy prompt
support, window-size tracking, and prompt expansion are enabled. The shell uses
`TERM=xterm-256color` for QEMU's serial terminal and stores history at
`/Users/root/State/Shell/history`.

GNU nano 9.2 is statically linked with wide-character ncurses 6.6. The build
does not copy host binaries or the host terminfo database. It compiles only
these definitions from the pinned ncurses source:

```text
ansi, dumb, linux, screen, screen-256color, vt100, xterm, xterm-256color
```

They live in `/Programs/CLI/Nano/Resources/terminfo`, and ncurses is compiled to
use that native location. Nano is built without NLS, libmagic, or its external
spell-checker integration; editing, help, search, browser, and normal save/exit
behavior remain available.

## Persistence

Create files on the real root, exit QEMU, and run `./run.sh` again without
running `./build.sh`:

```sh
cd A:/Users/root
echo "Solven lives" > persistence-test
nano /Users/root/test.txt
sync
```

After restarting QEMU:

```sh
cat /Users/root/persistence-test
cat /Users/root/test.txt
```

Running `./build.sh` intentionally creates a fresh root volume.

## Networking

QEMU provides a VirtIO network device connected to its unprivileged user-mode
network. The real-root init enables loopback and BusyBox `udhcpc` requests an
IPv4 lease for `eth0`. Its native hook at
`/System/Core/Network/udhcpc.script` configures the address, default route, and
ephemeral resolver state. Networking failure is non-fatal and the shell always
starts.

QEMU normally assigns `10.0.2.15`, with gateway `10.0.2.2` and DNS server
`10.0.2.3`. Check the live configuration with:

```sh
ip addr
ip route
ping -c 1 127.0.0.1
ping -c 1 10.0.2.2
ping -c 1 example.com
curl --version
curl -I http://example.com
curl -I https://example.com
```

curl is statically linked with Mbed TLS and supports only HTTP and HTTPS over
IPv4. HTTPS performs normal hostname and certificate-chain validation without
`-k`.

BusyBox `wget` remains available for simple HTTP bootstrap diagnostics. Its
internal HTTPS implementation does not authenticate certificates and must not
be used where peer identity matters.

## Linux compatibility anchors

The persistent root does not globally recreate `/bin`, `/sbin`, `/usr`, `/lib`,
`/var`, `/home`, `/run`, or `/tmp`. The only current global compatibility path
is:

```text
/etc/resolv.conf -> /Runtime/System/Network/resolv.conf
```

This anchor is required because the static glibc resolver used by curl has a
fixed `/etc/resolv.conf` lookup path. The authoritative mutable file remains in
Solven's ephemeral `/Runtime` hierarchy. The bootstrap initramfs has its own
private `/bootstrap` command directory and does not impose an FHS layout on the
real root.

A future Linux Compatibility Runtime can use mount namespaces and bind mounts
under `/Compatibility/Linux/Runtimes` to present an FHS to foreign software.
That runtime is not implemented here.

## Project layout

- `config/`: pinned Linux and BusyBox configurations plus volume metadata
- `initramfs/`: minimal bootstrap init that finds and mounts the real root
- `rootfs/`: Solven-native files overlaid onto the persistent root staging tree
- `scripts/`: small deterministic image-building helpers
- `sources/`: downloaded, checksum-verified source archives
- `work/`: extracted sources, build trees, archives, and filesystem staging
- `out/`: final kernel, initramfs, and persistent ext4 image

The generated contents of `sources/`, `work/`, and `out/` are excluded from
version control.

## Licensing

Solven-authored scripts carrying an SPDX notice are licensed under
GPL-2.0-or-later; the full text is in `LICENSE`. Generated boot artifacts also
contain independently licensed upstream components and are not wholly covered
by that license. See `THIRD_PARTY.md` for component licenses and source details.

## Reproducibility scope

Versions, source checksums, configurations, build identity, archive ordering,
archive ownership, archive timestamps, volume identity, and filesystem size are
fixed. Exact binary identity can still vary with the host compiler, toolchain,
and e2fsprogs implementation. Pinning an entire toolchain can be added later if
bit-for-bit builds across different hosts become a project requirement.
