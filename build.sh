#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

trap 'printf "error: build failed at line %s\n" "$LINENO" >&2' ERR

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$ROOT_DIR/sources"
WORK_DIR="$ROOT_DIR/work"
OUT_DIR="$ROOT_DIR/out"

LINUX_VERSION="6.12.103"
LINUX_ARCHIVE="linux-${LINUX_VERSION}.tar.xz"
LINUX_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/${LINUX_ARCHIVE}"
LINUX_SHA256="f143aaade8877ba5616e788b4482576db28481bcf557ef537f4fcc3938fc3176"

BUSYBOX_VERSION="1.37.0"
BUSYBOX_ARCHIVE="busybox-${BUSYBOX_VERSION}.tar.bz2"
BUSYBOX_URL="https://busybox.net/downloads/${BUSYBOX_ARCHIVE}"
BUSYBOX_SHA256="3311dff32e746499f4df0d5df04d7eb396382d7e108bb9250e7b519b837043a4"

MBEDTLS_VERSION="3.6.7"
MBEDTLS_ARCHIVE="mbedtls-${MBEDTLS_VERSION}.tar.bz2"
MBEDTLS_URL="https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-${MBEDTLS_VERSION}/${MBEDTLS_ARCHIVE}"
MBEDTLS_SHA256="a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6"

CURL_VERSION="8.21.0"
CURL_ARCHIVE="curl-${CURL_VERSION}.tar.xz"
CURL_URL="https://curl.se/download/${CURL_ARCHIVE}"
CURL_SHA256="aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6"

CA_BUNDLE_VERSION="2026-07-16"
CA_BUNDLE_ARCHIVE="cacert-${CA_BUNDLE_VERSION}.pem"
CA_BUNDLE_URL="https://curl.se/ca/${CA_BUNDLE_ARCHIVE}"
CA_BUNDLE_SHA256="3ff344e30b9b1ed2971044eabb438a08f2e2245ddb5f8ab1a3ad8b63ab4eaf91"

SOURCE_DATE_EPOCH="0"
export SOURCE_DATE_EPOCH
export KBUILD_BUILD_TIMESTAMP="1970-01-01 00:00:00 UTC"
export KBUILD_BUILD_USER="solven"
export KBUILD_BUILD_HOST="builder"
export LC_ALL=C
export TZ=UTC

if [[ "$(uname -m)" != "x86_64" ]]; then
    printf 'error: this milestone requires an x86_64 build host\n' >&2
    exit 1
fi

required_commands=(
    ar awk bash basename bc bison bzip2 chmod cp cpio curl cut dd dirname expr
    file find flex gcc grep gzip install ld ln make mkdir mv nm objdump perl
    ranlib readelf rm sed sha256sum sort strip tar touch tr uname wc xz
)
missing_commands=()

for command_name in "${required_commands[@]}"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        missing_commands+=("$command_name")
    fi
done

if ((${#missing_commands[@]})); then
    printf 'error: missing required build commands:' >&2
    printf ' %s' "${missing_commands[@]}" >&2
    printf '\n' >&2
    exit 1
fi

if [[ -n "${JOBS:-}" ]]; then
    if [[ ! "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
        printf 'error: JOBS must be a positive integer\n' >&2
        exit 1
    fi
else
    JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
fi

mkdir -p "$SOURCES_DIR" "$WORK_DIR" "$OUT_DIR"

download_and_verify() {
    local url="$1"
    local destination="$2"
    local expected_sha256="$3"
    local temporary="${destination}.part"

    if [[ ! -f "$destination" ]]; then
        printf 'Downloading %s\n' "$(basename "$destination")"
        rm -f "$temporary"
        curl --fail --location --proto '=https' --tlsv1.2 \
            --output "$temporary" "$url"
        mv "$temporary" "$destination"
    fi

    if ! printf '%s  %s\n' "$expected_sha256" "$destination" | sha256sum --check --status; then
        printf 'error: checksum verification failed for %s\n' "$destination" >&2
        printf 'Remove the file and run the build again.\n' >&2
        exit 1
    fi

    printf 'Verified %s\n' "$(basename "$destination")"
}

download_and_verify "$LINUX_URL" "$SOURCES_DIR/$LINUX_ARCHIVE" "$LINUX_SHA256"
download_and_verify "$BUSYBOX_URL" "$SOURCES_DIR/$BUSYBOX_ARCHIVE" "$BUSYBOX_SHA256"
download_and_verify "$MBEDTLS_URL" "$SOURCES_DIR/$MBEDTLS_ARCHIVE" "$MBEDTLS_SHA256"
download_and_verify "$CURL_URL" "$SOURCES_DIR/$CURL_ARCHIVE" "$CURL_SHA256"
download_and_verify "$CA_BUNDLE_URL" "$SOURCES_DIR/$CA_BUNDLE_ARCHIVE" "$CA_BUNDLE_SHA256"

LINUX_SOURCE="$WORK_DIR/linux-$LINUX_VERSION"
LINUX_BUILD="$WORK_DIR/linux-build"
BUSYBOX_SOURCE="$WORK_DIR/busybox-$BUSYBOX_VERSION"
BUSYBOX_BUILD="$WORK_DIR/busybox-build"
MBEDTLS_SOURCE="$WORK_DIR/mbedtls-$MBEDTLS_VERSION"
MBEDTLS_PREFIX="$WORK_DIR/mbedtls-install"
CURL_SOURCE="$WORK_DIR/curl-$CURL_VERSION"
ROOTFS_STAGE="$WORK_DIR/rootfs"

rm -rf \
    "$LINUX_SOURCE" "$LINUX_BUILD" \
    "$BUSYBOX_SOURCE" "$BUSYBOX_BUILD" \
    "$MBEDTLS_SOURCE" "$MBEDTLS_PREFIX" "$CURL_SOURCE" \
    "$ROOTFS_STAGE"
rm -f "$OUT_DIR/bzImage" "$OUT_DIR/initramfs.cpio.gz"

printf 'Extracting Linux %s\n' "$LINUX_VERSION"
tar --extract --file "$SOURCES_DIR/$LINUX_ARCHIVE" --directory "$WORK_DIR"
mkdir -p "$LINUX_BUILD"
cp "$ROOT_DIR/config/linux-x86_64.config" "$LINUX_BUILD/.config"

printf 'Building Linux %s\n' "$LINUX_VERSION"
make -C "$LINUX_SOURCE" O="$LINUX_BUILD" ARCH=x86 olddefconfig
make -C "$LINUX_SOURCE" O="$LINUX_BUILD" ARCH=x86 --jobs="$JOBS" bzImage
cp "$LINUX_BUILD/arch/x86/boot/bzImage" "$OUT_DIR/bzImage"

printf 'Extracting BusyBox %s\n' "$BUSYBOX_VERSION"
tar --extract --file "$SOURCES_DIR/$BUSYBOX_ARCHIVE" --directory "$WORK_DIR"
mkdir -p "$BUSYBOX_BUILD"
cp "$ROOT_DIR/config/busybox.config" "$BUSYBOX_BUILD/.config"

printf 'Building BusyBox %s\n' "$BUSYBOX_VERSION"
make -C "$BUSYBOX_SOURCE" O="$BUSYBOX_BUILD" oldconfig </dev/null >/dev/null
make -C "$BUSYBOX_SOURCE" O="$BUSYBOX_BUILD" --jobs="$JOBS"
mkdir -p "$ROOTFS_STAGE"
make -C "$BUSYBOX_SOURCE" O="$BUSYBOX_BUILD" CONFIG_PREFIX="$ROOTFS_STAGE" install

printf 'Extracting Mbed TLS %s\n' "$MBEDTLS_VERSION"
tar --extract --file "$SOURCES_DIR/$MBEDTLS_ARCHIVE" --directory "$WORK_DIR"

printf 'Building Mbed TLS %s\n' "$MBEDTLS_VERSION"
make -C "$MBEDTLS_SOURCE" --jobs="$JOBS" lib \
    CFLAGS='-Os -ffunction-sections -fdata-sections'
mkdir -p "$MBEDTLS_PREFIX/include" "$MBEDTLS_PREFIX/lib"
cp -a "$MBEDTLS_SOURCE/include/mbedtls" "$MBEDTLS_SOURCE/include/psa" \
    "$MBEDTLS_PREFIX/include/"
cp "$MBEDTLS_SOURCE/library/libmbedcrypto.a" \
    "$MBEDTLS_SOURCE/library/libmbedtls.a" \
    "$MBEDTLS_SOURCE/library/libmbedx509.a" \
    "$MBEDTLS_PREFIX/lib/"

printf 'Extracting curl %s\n' "$CURL_VERSION"
tar --extract --file "$SOURCES_DIR/$CURL_ARCHIVE" --directory "$WORK_DIR"

printf 'Building curl %s\n' "$CURL_VERSION"
(
    cd "$CURL_SOURCE"
    CPPFLAGS="-I$MBEDTLS_PREFIX/include" \
    LDFLAGS="-L$MBEDTLS_PREFIX/lib" \
    CFLAGS='-Os -ffunction-sections -fdata-sections' \
    ./configure \
        --prefix=/usr \
        --disable-shared \
        --enable-static \
        --with-mbedtls="$MBEDTLS_PREFIX" \
        --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
        --without-ca-path \
        --disable-ftp \
        --disable-file \
        --disable-ipfs \
        --disable-ldap \
        --disable-ldaps \
        --disable-rtsp \
        --disable-proxy \
        --disable-dict \
        --disable-telnet \
        --disable-tftp \
        --disable-pop3 \
        --disable-imap \
        --disable-smb \
        --disable-smtp \
        --disable-gopher \
        --disable-mqtt \
        --disable-manual \
        --disable-docs \
        --disable-ipv6 \
        --disable-threaded-resolver \
        --disable-basic-auth \
        --disable-bearer-auth \
        --disable-digest-auth \
        --disable-kerberos-auth \
        --disable-negotiate-auth \
        --disable-aws \
        --disable-unix-sockets \
        --disable-cookies \
        --disable-doh \
        --disable-mime \
        --disable-form-api \
        --disable-dateparse \
        --disable-netrc \
        --disable-alt-svc \
        --disable-hsts \
        --disable-websockets \
        --without-zlib \
        --without-brotli \
        --without-zstd \
        --without-libpsl \
        --without-libidn2 \
        --without-nghttp2 \
        --without-ngtcp2 \
        --without-nghttp3 \
        --without-libssh2
    make --jobs="$JOBS" \
        LDFLAGS="-all-static -Wl,--gc-sections -L$MBEDTLS_PREFIX/lib"
)
strip --strip-all "$CURL_SOURCE/src/curl"

if readelf --program-headers "$CURL_SOURCE/src/curl" | grep --quiet INTERP; then
    printf 'error: curl is dynamically linked\n' >&2
    exit 1
fi
if ! "$CURL_SOURCE/src/curl" --version \
    | grep --fixed-strings --quiet "mbedTLS/$MBEDTLS_VERSION"; then
    printf 'error: curl was not linked with Mbed TLS %s\n' "$MBEDTLS_VERSION" >&2
    exit 1
fi
if ! "$CURL_SOURCE/src/curl" --version \
    | grep --fixed-strings --line-regexp --quiet 'Protocols: http https'; then
    printf 'error: curl protocol selection does not match the bootstrap scope\n' >&2
    exit 1
fi

cp -a "$ROOT_DIR/rootfs/." "$ROOTFS_STAGE/"
mkdir -p \
    "$ROOTFS_STAGE/dev" "$ROOTFS_STAGE/etc/ssl/certs" \
    "$ROOTFS_STAGE/proc" "$ROOTFS_STAGE/root" "$ROOTFS_STAGE/sys" \
    "$ROOTFS_STAGE/tmp" "$ROOTFS_STAGE/usr/bin"
cp "$CURL_SOURCE/src/curl" "$ROOTFS_STAGE/usr/bin/curl"
cp "$SOURCES_DIR/$CA_BUNDLE_ARCHIVE" \
    "$ROOTFS_STAGE/etc/ssl/certs/ca-certificates.crt"
chmod 0755 "$ROOTFS_STAGE/init"
chmod 0755 "$ROOTFS_STAGE/usr/share/udhcpc/default.script"
chmod 1777 "$ROOTFS_STAGE/tmp"

printf 'Creating initramfs\n'
"$ROOT_DIR/scripts/make-initramfs.sh" \
    "$ROOTFS_STAGE" "$OUT_DIR/initramfs.cpio.gz"

printf '\nSolven build complete:\n'
printf '  Kernel:    %s\n' "$OUT_DIR/bzImage"
printf '  Initramfs: %s\n' "$OUT_DIR/initramfs.cpio.gz"
