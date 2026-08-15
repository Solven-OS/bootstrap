#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KERNEL="$ROOT_DIR/out/bzImage"
INITRAMFS="$ROOT_DIR/out/initramfs.cpio.gz"
ROOTFS_IMAGE="$ROOT_DIR/out/solven-root.ext4"

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    printf 'error: qemu-system-x86_64 is required to run Solven\n' >&2
    exit 1
fi

if [[ ! -f "$KERNEL" || ! -f "$INITRAMFS" || ! -f "$ROOTFS_IMAGE" ]]; then
    printf 'error: Solven has not been built; run ./build.sh first\n' >&2
    exit 1
fi

exec qemu-system-x86_64 \
    -machine q35 \
    -m 256M \
    -kernel "$KERNEL" \
    -initrd "$INITRAMFS" \
    -append 'console=ttyS0 rdinit=/init panic=-1' \
    -drive "if=none,id=solven-root,file=$ROOTFS_IMAGE,format=raw" \
    -device virtio-blk-pci,drive=solven-root \
    -nic user,model=virtio-net-pci \
    -no-reboot \
    -nographic
