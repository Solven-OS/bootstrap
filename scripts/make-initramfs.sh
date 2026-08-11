#!/usr/bin/env bash

set -Eeuo pipefail

if (($# != 2)); then
    printf 'usage: %s ROOTFS OUTPUT\n' "$0" >&2
    exit 2
fi

ROOTFS="$1"
OUTPUT="$2"
OUTPUT_DIR="$(CDPATH= cd -- "$(dirname -- "$OUTPUT")" && pwd)"
OUTPUT="$OUTPUT_DIR/$(basename -- "$OUTPUT")"
TEMPORARY="${OUTPUT}.part"

if [[ ! -d "$ROOTFS" ]]; then
    printf 'error: rootfs directory does not exist: %s\n' "$ROOTFS" >&2
    exit 1
fi

find "$ROOTFS" -exec touch -h -d "@${SOURCE_DATE_EPOCH:-0}" {} +
rm -f "$TEMPORARY"

(
    cd "$ROOTFS"
    find . -print0 \
        | sort --zero-terminated \
        | cpio --null --create --format=newc --owner=0:0 --reproducible 2>/dev/null \
        | gzip --best --no-name >"$TEMPORARY"
)

mv "$TEMPORARY" "$OUTPUT"
