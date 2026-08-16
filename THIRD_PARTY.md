# Third-Party Software

Solven's generated kernel, initramfs, and persistent root filesystem include
independently licensed upstream software. The repository's `LICENSE` applies
only to files identified as `GPL-2.0-or-later`; it does not replace the terms
listed below.

| Component | Version/data date | License | Upstream |
| --- | --- | --- | --- |
| Linux | 6.12.103 | GPL-2.0-only WITH Linux-syscall-note | <https://kernel.org/> |
| BusyBox | 1.37.0 | GPL-2.0-only | <https://busybox.net/> |
| curl | 8.21.0 | curl license | <https://curl.se/> |
| Mbed TLS | 3.6.7 | Apache-2.0 OR GPL-2.0-or-later | <https://github.com/Mbed-TLS/mbedtls> |
| Mozilla CA certificate data | 2026-07-16 extract | MPL-2.0 | <https://curl.se/docs/caextract.html> |
| ncurses | 6.6 | MIT-style ncurses license | <https://invisible-island.net/ncurses/> |
| GNU nano | 9.2 | GPL-3.0-or-later | <https://www.nano-editor.org/> |
| Steward | `ecb20b2415f47aed7c204cb375aa8c962db26e2d` | GPL-2.0-or-later | <https://github.com/Solven-OS/steward> |

The complete license notices and source files for Linux, BusyBox, curl, Mbed
TLS, ncurses, GNU nano, and Steward are included in their upstream archives, which
`build.sh` downloads from pinned URLs and verifies before use. The generated CA
bundle contains its Mozilla source and licensing notice. See each upstream
distribution for the complete applicable terms and notices.

The Mbed TLS project offers its files under a choice of Apache-2.0 or
GPL-2.0-or-later. This build uses Mbed TLS as curl's TLS implementation without
altering Mbed TLS source files.

The static userspace binaries also incorporate the build host's C runtime and
compiler support library. Their exact versions and licenses depend on the host
toolchain and are not pinned by this bootstrap repository; builders and
distributors must account for those components separately.

The Solven logo is not covered by the software license merely by being present
in this repository.
