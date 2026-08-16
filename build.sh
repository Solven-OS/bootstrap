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

NCURSES_VERSION="6.6"
NCURSES_ARCHIVE="ncurses-${NCURSES_VERSION}.tar.gz"
NCURSES_URL="https://ftp.gnu.org/gnu/ncurses/${NCURSES_ARCHIVE}"
NCURSES_SHA256="355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11"

NANO_VERSION="9.2"
NANO_ARCHIVE="nano-${NANO_VERSION}.tar.xz"
NANO_URL="https://ftp.gnu.org/gnu/nano/${NANO_ARCHIVE}"
NANO_SHA256="05ecb99247b782e8a5b3a25ed4101dd034b0236902f7449bc9795b717642f7e9"

STEWARD_COMMIT="ecb20b2415f47aed7c204cb375aa8c962db26e2d"
STEWARD_ARCHIVE="steward-${STEWARD_COMMIT}.tar.gz"
STEWARD_URL="https://github.com/Solven-OS/steward/releases/download/v0.1.0/${STEWARD_ARCHIVE}"
STEWARD_SHA256="32085f86813dc4fc3564c92a1681e8fcec89d3a48211d45651136cb44ffc9567"

ROOTFS_SIZE_MIB=128
SOURCE_DATE_EPOCH=1
export SOURCE_DATE_EPOCH
export KBUILD_BUILD_TIMESTAMP="1970-01-01 00:00:01 UTC"
export KBUILD_BUILD_USER="solven"
export KBUILD_BUILD_HOST="builder"
export LC_ALL=C
export TZ=UTC
umask 022

if [[ "$(uname -m)" != "x86_64" ]]; then
    printf 'error: this milestone requires an x86_64 build host\n' >&2
    exit 1
fi

required_commands=(
    ar awk bash basename bc bison bzip2 chmod cp cpio curl cut debugfs dirname
    e2fsck expr file find flex g++ gcc grep gzip install ld ln make mkdir mke2fs mv nm
    objdump perl ranlib readelf rm sed sha256sum sort stat strip tar touch tr
    truncate uname wc xz
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

root_volume_record="$(awk -F '|' '$1 == "A" { print; exit }' "$ROOT_DIR/config/volumes.conf")"
IFS='|' read -r ROOT_VOLUME_LETTER ROOT_VOLUME_UUID ROOT_VOLUME_NAME ROOT_VOLUME_MOUNT \
    <<< "$root_volume_record"

if [[ "$ROOT_VOLUME_LETTER" != A \
    || ! "$ROOT_VOLUME_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ \
    || "$ROOT_VOLUME_MOUNT" != / ]]; then
    printf 'error: config/volumes.conf must map A to a valid root volume UUID\n' >&2
    exit 1
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
download_and_verify "$NCURSES_URL" "$SOURCES_DIR/$NCURSES_ARCHIVE" "$NCURSES_SHA256"
download_and_verify "$NANO_URL" "$SOURCES_DIR/$NANO_ARCHIVE" "$NANO_SHA256"
download_and_verify "$STEWARD_URL" "$SOURCES_DIR/$STEWARD_ARCHIVE" "$STEWARD_SHA256"

LINUX_SOURCE="$WORK_DIR/linux-$LINUX_VERSION"
LINUX_BUILD="$WORK_DIR/linux-build"
BUSYBOX_SOURCE="$WORK_DIR/busybox-$BUSYBOX_VERSION"
BUSYBOX_BUILD="$WORK_DIR/busybox-build"
INIT_BUSYBOX_BUILD="$WORK_DIR/initramfs-busybox-build"
MBEDTLS_SOURCE="$WORK_DIR/mbedtls-$MBEDTLS_VERSION"
MBEDTLS_PREFIX="$WORK_DIR/mbedtls-install"
CURL_SOURCE="$WORK_DIR/curl-$CURL_VERSION"
NCURSES_SOURCE="$WORK_DIR/ncurses-$NCURSES_VERSION"
NCURSES_BUILD="$WORK_DIR/ncurses-build"
NCURSES_PREFIX="$WORK_DIR/ncurses-install"
NANO_SOURCE="$WORK_DIR/nano-$NANO_VERSION"
NANO_BUILD="$WORK_DIR/nano-build"
STEWARD_SOURCE="$WORK_DIR/steward-$STEWARD_COMMIT"
STEWARD_BUILD="$WORK_DIR/steward-build"
EMPTY_PKGCONFIG="$WORK_DIR/empty-pkgconfig"
ROOTFS_STAGE="$WORK_DIR/rootfs"
ROOTFS_TAR="$WORK_DIR/rootfs.tar"
INITRAMFS_STAGE="$WORK_DIR/initramfs"
ROOTFS_IMAGE="$OUT_DIR/solven-root.ext4"

rm -rf \
    "$LINUX_SOURCE" "$LINUX_BUILD" \
    "$BUSYBOX_SOURCE" "$BUSYBOX_BUILD" "$INIT_BUSYBOX_BUILD" \
    "$MBEDTLS_SOURCE" "$MBEDTLS_PREFIX" "$CURL_SOURCE" \
    "$NCURSES_SOURCE" "$NCURSES_BUILD" "$NCURSES_PREFIX" \
    "$NANO_SOURCE" "$NANO_BUILD" "$STEWARD_SOURCE" "$STEWARD_BUILD" \
    "$EMPTY_PKGCONFIG" \
    "$ROOTFS_STAGE" "$INITRAMFS_STAGE"
rm -f "$ROOTFS_TAR" "${ROOTFS_IMAGE}.part" \
    "$OUT_DIR/bzImage" "$OUT_DIR/initramfs.cpio.gz"

printf 'Extracting Linux %s\n' "$LINUX_VERSION"
tar --extract --file "$SOURCES_DIR/$LINUX_ARCHIVE" --directory "$WORK_DIR"
mkdir -p "$LINUX_BUILD"
cp "$ROOT_DIR/config/linux-x86_64.config" "$LINUX_BUILD/.config"

printf 'Building Linux %s\n' "$LINUX_VERSION"
make -C "$LINUX_SOURCE" O="$LINUX_BUILD" ARCH=x86 olddefconfig
for expected_setting in CONFIG_SIGNALFD=y CONFIG_ACPI=y; do
    if ! grep --fixed-strings --line-regexp --quiet "$expected_setting" \
        "$LINUX_BUILD/.config"; then
        printf 'error: required Steward kernel setting is missing: %s\n' \
            "$expected_setting" >&2
        exit 1
    fi
done
make -C "$LINUX_SOURCE" O="$LINUX_BUILD" ARCH=x86 --jobs="$JOBS" bzImage
cp "$LINUX_BUILD/arch/x86/boot/bzImage" "$OUT_DIR/bzImage"

printf 'Extracting BusyBox %s\n' "$BUSYBOX_VERSION"
tar --extract --file "$SOURCES_DIR/$BUSYBOX_ARCHIVE" --directory "$WORK_DIR"
mkdir -p "$BUSYBOX_BUILD" "$INIT_BUSYBOX_BUILD"
cp "$ROOT_DIR/config/busybox.config" "$BUSYBOX_BUILD/.config"

printf 'Building Solven BusyBox %s\n' "$BUSYBOX_VERSION"
make -C "$BUSYBOX_SOURCE" O="$BUSYBOX_BUILD" oldconfig </dev/null >/dev/null
make -C "$BUSYBOX_SOURCE" O="$BUSYBOX_BUILD" --jobs="$JOBS"

for expected_setting in \
    CONFIG_FEATURE_EDITING=y \
    CONFIG_FEATURE_EDITING_HISTORY=256 \
    CONFIG_FEATURE_EDITING_SAVEHISTORY=y \
    CONFIG_FEATURE_TAB_COMPLETION=y \
    CONFIG_FEATURE_EDITING_FANCY_PROMPT=y \
    CONFIG_ASH_EXPAND_PRMT=y; do
    if ! grep --fixed-strings --line-regexp --quiet "$expected_setting" "$BUSYBOX_BUILD/.config"; then
        printf 'error: BusyBox shell setting is missing: %s\n' "$expected_setting" >&2
        exit 1
    fi
done

printf 'Building minimal initramfs BusyBox %s\n' "$BUSYBOX_VERSION"
make -C "$BUSYBOX_SOURCE" O="$INIT_BUSYBOX_BUILD" allnoconfig >/dev/null
while IFS= read -r setting; do
    [[ "$setting" == CONFIG_*=* ]] || continue
    symbol="${setting%%=*}"

    if grep --fixed-strings --line-regexp --quiet "# $symbol is not set" \
        "$INIT_BUSYBOX_BUILD/.config"; then
        sed -i "s/^# $symbol is not set$/$setting/" "$INIT_BUSYBOX_BUILD/.config"
    elif grep --extended-regexp --quiet "^${symbol}=" "$INIT_BUSYBOX_BUILD/.config"; then
        sed -i "s/^${symbol}=.*$/$setting/" "$INIT_BUSYBOX_BUILD/.config"
    else
        printf '%s\n' "$setting" >> "$INIT_BUSYBOX_BUILD/.config"
    fi
done < "$ROOT_DIR/config/initramfs-busybox.config"
make -C "$BUSYBOX_SOURCE" O="$INIT_BUSYBOX_BUILD" oldconfig </dev/null >/dev/null
make -C "$BUSYBOX_SOURCE" O="$INIT_BUSYBOX_BUILD" --jobs="$JOBS"

for applet in blkid mount sh sleep switch_root; do
    if ! "$INIT_BUSYBOX_BUILD/busybox" --list \
        | grep --fixed-strings --line-regexp --quiet "$applet"; then
        printf 'error: initramfs BusyBox is missing %s\n' "$applet" >&2
        exit 1
    fi
done

strip --strip-all "$BUSYBOX_BUILD/busybox" "$INIT_BUSYBOX_BUILD/busybox"

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
        --prefix=/Programs/CLI/Curl \
        --disable-shared \
        --enable-static \
        --with-mbedtls="$MBEDTLS_PREFIX" \
        --with-ca-bundle=/System/Trust/CA/ca-certificates.crt \
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

printf 'Extracting ncurses %s\n' "$NCURSES_VERSION"
tar --extract --file "$SOURCES_DIR/$NCURSES_ARCHIVE" --directory "$WORK_DIR"
mkdir -p "$NCURSES_BUILD" "$NCURSES_PREFIX"

printf 'Building ncursesw %s\n' "$NCURSES_VERSION"
(
    cd "$NCURSES_BUILD"
    "$NCURSES_SOURCE/configure" \
        --prefix="$NCURSES_PREFIX" \
        --enable-widec \
        --with-normal \
        --without-shared \
        --without-cxx \
        --without-cxx-binding \
        --without-ada \
        --without-manpages \
        --without-tests \
        --without-debug \
        --without-gpm \
        --without-pthread \
        --disable-home-terminfo \
        --disable-db-install \
        --with-default-terminfo-dir=/Programs/CLI/Nano/Resources/terminfo \
        --with-terminfo-dirs=/Programs/CLI/Nano/Resources/terminfo \
        CFLAGS='-Os -ffunction-sections -fdata-sections'
    make --jobs="$JOBS"
    make install.libs install.includes
)

printf 'Extracting GNU nano %s\n' "$NANO_VERSION"
tar --extract --file "$SOURCES_DIR/$NANO_ARCHIVE" --directory "$WORK_DIR"
mkdir -p "$NANO_BUILD" "$EMPTY_PKGCONFIG"

printf 'Building GNU nano %s\n' "$NANO_VERSION"
(
    cd "$NANO_BUILD"
    PKG_CONFIG_LIBDIR="$EMPTY_PKGCONFIG" \
    PKG_CONFIG_PATH= \
    NCURSESW_CONFIG="$NCURSES_PREFIX/bin/ncursesw6-config" \
    CFLAGS='-Os -ffunction-sections -fdata-sections' \
    LDFLAGS='-static -Wl,--gc-sections' \
    "$NANO_SOURCE/configure" \
        --prefix=/Programs/CLI/Nano \
        --bindir=/Programs/CLI/Nano/Executable \
        --datadir=/Programs/CLI/Nano/Resources \
        --sysconfdir=/Programs/CLI/Nano/Resources/Configuration \
        --disable-nls \
        --disable-libmagic \
        --disable-speller \
        --enable-utf8
    make --jobs="$JOBS"
)
strip --strip-all "$NANO_BUILD/src/nano"

if readelf --program-headers "$NANO_BUILD/src/nano" | grep --quiet INTERP; then
    printf 'error: nano is dynamically linked\n' >&2
    exit 1
fi
if ! "$NANO_BUILD/src/nano" --version \
    | grep --fixed-strings --quiet "GNU nano, version $NANO_VERSION"; then
    printf 'error: built nano version does not match %s\n' "$NANO_VERSION" >&2
    exit 1
fi

printf 'Extracting Steward %s\n' "$STEWARD_COMMIT"
tar --extract --file "$SOURCES_DIR/$STEWARD_ARCHIVE" --directory "$WORK_DIR"

printf 'Building Steward %s\n' "$STEWARD_COMMIT"
make -C "$STEWARD_SOURCE" --jobs="$JOBS" \
    BUILD_DIR="$STEWARD_BUILD" CXX=g++ static
strip --strip-all "$STEWARD_BUILD/steward-static"

if readelf --program-headers "$STEWARD_BUILD/steward-static" \
    | grep --quiet INTERP; then
    printf 'error: Steward is dynamically linked\n' >&2
    exit 1
fi

printf 'Staging native Solven root filesystem\n'
mkdir -p "$ROOTFS_STAGE"
cp -a "$ROOT_DIR/rootfs/." "$ROOTFS_STAGE/"
mkdir -p \
    "$ROOTFS_STAGE/System/Core/BusyBox" \
    "$ROOTFS_STAGE/System/Core/Steward" \
    "$ROOTFS_STAGE/System/Services" \
    "$ROOTFS_STAGE/System/Store" \
    "$ROOTFS_STAGE/System/Commands" \
    "$ROOTFS_STAGE/System/Trust/CA" \
    "$ROOTFS_STAGE/System/Trust/Guilds" \
    "$ROOTFS_STAGE/System/Trust/Publishers" \
    "$ROOTFS_STAGE/System/Trust/Authorities" \
    "$ROOTFS_STAGE/System/Trust/Policies" \
    "$ROOTFS_STAGE/System/Boot" \
    "$ROOTFS_STAGE/Programs/CLI/Curl/Executable" \
    "$ROOTFS_STAGE/Programs/CLI/Curl/Libraries" \
    "$ROOTFS_STAGE/Programs/CLI/Curl/Resources" \
    "$ROOTFS_STAGE/Programs/CLI/Curl/Metadata" \
    "$ROOTFS_STAGE/Programs/CLI/Nano/Executable" \
    "$ROOTFS_STAGE/Programs/CLI/Nano/Libraries" \
    "$ROOTFS_STAGE/Programs/CLI/Nano/Resources/Configuration" \
    "$ROOTFS_STAGE/Programs/CLI/Nano/Resources/terminfo" \
    "$ROOTFS_STAGE/Programs/CLI/Nano/Metadata" \
    "$ROOTFS_STAGE/Programs/GUI" \
    "$ROOTFS_STAGE/Users/root/Desktop" \
    "$ROOTFS_STAGE/Users/root/Documents" \
    "$ROOTFS_STAGE/Users/root/Downloads" \
    "$ROOTFS_STAGE/Users/root/Pictures" \
    "$ROOTFS_STAGE/Users/root/Music" \
    "$ROOTFS_STAGE/Users/root/Videos" \
    "$ROOTFS_STAGE/Users/root/Programs/CLI" \
    "$ROOTFS_STAGE/Users/root/Programs/GUI" \
    "$ROOTFS_STAGE/Users/root/Commands" \
    "$ROOTFS_STAGE/Users/root/State/Programs" \
    "$ROOTFS_STAGE/State/System/Volumes" \
    "$ROOTFS_STAGE/State/System/Trust" \
    "$ROOTFS_STAGE/State/Programs" \
    "$ROOTFS_STAGE/State/Keep" \
    "$ROOTFS_STAGE/State/Logs" \
    "$ROOTFS_STAGE/State/Cache" \
    "$ROOTFS_STAGE/Runtime/System" \
    "$ROOTFS_STAGE/Runtime/Programs" \
    "$ROOTFS_STAGE/Runtime/Users" \
    "$ROOTFS_STAGE/Runtime/Temp" \
    "$ROOTFS_STAGE/Volumes" \
    "$ROOTFS_STAGE/Compatibility/Linux/Runtimes" \
    "$ROOTFS_STAGE/dev" \
    "$ROOTFS_STAGE/proc" \
    "$ROOTFS_STAGE/sys" \
    "$ROOTFS_STAGE/etc"

cp "$BUSYBOX_BUILD/busybox" "$ROOTFS_STAGE/System/Core/BusyBox/busybox"
cp "$STEWARD_BUILD/steward-static" \
    "$ROOTFS_STAGE/System/Core/Steward/steward"
while IFS= read -r applet; do
    ln -s ../Core/BusyBox/busybox "$ROOTFS_STAGE/System/Commands/$applet"
done < <("$BUSYBOX_BUILD/busybox" --list)

cp "$CURL_SOURCE/src/curl" "$ROOTFS_STAGE/Programs/CLI/Curl/Executable/curl"
cp "$NANO_BUILD/src/nano" "$ROOTFS_STAGE/Programs/CLI/Nano/Executable/nano"
cp "$SOURCES_DIR/$CA_BUNDLE_ARCHIVE" \
    "$ROOTFS_STAGE/System/Trust/CA/ca-certificates.crt"
cp "$ROOT_DIR/config/volumes.conf" "$ROOTFS_STAGE/State/System/Volumes/registry"

"$NCURSES_BUILD/progs/tic" -x \
    -o "$ROOTFS_STAGE/Programs/CLI/Nano/Resources/terminfo" \
    -e 'ansi,dumb,linux,screen,screen-256color,vt100,xterm,xterm-256color' \
    "$NCURSES_SOURCE/misc/terminfo.src"

ln -s ../../Programs/CLI/Curl/Executable/curl "$ROOTFS_STAGE/System/Commands/curl"
ln -s ../../Programs/CLI/Nano/Executable/nano "$ROOTFS_STAGE/System/Commands/nano"
ln -s ../Core/Path/solpath "$ROOTFS_STAGE/System/Commands/solpath"
ln -s ../Core/Steward/steward "$ROOTFS_STAGE/System/Commands/steward"
ln -s ../Runtime/System/Network/resolv.conf "$ROOTFS_STAGE/etc/resolv.conf"

chmod 0755 \
    "$ROOTFS_STAGE/System/Core/BusyBox/busybox" \
    "$ROOTFS_STAGE/System/Core/Console/start" \
    "$ROOTFS_STAGE/System/Core/Network/start" \
    "$ROOTFS_STAGE/System/Core/Network/udhcpc.script" \
    "$ROOTFS_STAGE/System/Core/Path/solpath" \
    "$ROOTFS_STAGE/System/Core/Steward/steward" \
    "$ROOTFS_STAGE/Programs/CLI/Curl/Executable/curl" \
    "$ROOTFS_STAGE/Programs/CLI/Nano/Executable/nano"
chmod 0644 "$ROOTFS_STAGE/System/Core/Shell/interactive.sh"
chmod 0644 "$ROOTFS_STAGE/System/Services/"*.service
chmod 1777 "$ROOTFS_STAGE/Runtime/Temp"

for forbidden_path in bin sbin usr lib var home run tmp; do
    if [[ -e "$ROOTFS_STAGE/$forbidden_path" ]]; then
        printf 'error: unexpected global compatibility path: /%s\n' "$forbidden_path" >&2
        exit 1
    fi
done

find "$ROOTFS_STAGE" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

printf 'Creating root-owned rootfs archive\n'
tar \
    --sort=name \
    --format=posix \
    --pax-option=delete=atime,delete=ctime \
    --mtime="@$SOURCE_DATE_EPOCH" \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --create \
    --file "$ROOTFS_TAR" \
    --directory "$ROOTFS_STAGE" \
    .

printf 'Creating %s MiB ext4 root volume %s\n' "$ROOTFS_SIZE_MIB" "$ROOT_VOLUME_UUID"
truncate --size="${ROOTFS_SIZE_MIB}M" "${ROOTFS_IMAGE}.part"
E2FSPROGS_FAKE_TIME="$SOURCE_DATE_EPOCH" \
    mke2fs \
        -q \
        -F \
        -t ext4 \
        -b 4096 \
        -I 256 \
        -N 8192 \
        -J size=8 \
        -O 'none,has_journal,ext_attr,dir_index,filetype,extent,64bit,flex_bg,sparse_super,large_file,huge_file,dir_nlink,extra_isize,metadata_csum,metadata_csum_seed,orphan_file' \
        -M / \
        -e remount-ro \
        -d "$ROOTFS_TAR" \
        -L "$ROOT_VOLUME_NAME" \
        -U "$ROOT_VOLUME_UUID" \
        -m 0 \
        -E "root_owner=0:0,lazy_itable_init=0,lazy_journal_init=0,hash_seed=$ROOT_VOLUME_UUID" \
        "${ROOTFS_IMAGE}.part"
E2FSPROGS_FAKE_TIME="$SOURCE_DATE_EPOCH" \
    debugfs -w -R 'rmdir /lost+found' "${ROOTFS_IMAGE}.part" >/dev/null 2>&1
e2fsck -fn "${ROOTFS_IMAGE}.part"
mv "${ROOTFS_IMAGE}.part" "$ROOTFS_IMAGE"

printf 'Staging minimal initramfs\n'
mkdir -p \
    "$INITRAMFS_STAGE/bootstrap" \
    "$INITRAMFS_STAGE/dev" \
    "$INITRAMFS_STAGE/proc" \
    "$INITRAMFS_STAGE/sys" \
    "$INITRAMFS_STAGE/newroot"
cp "$INIT_BUSYBOX_BUILD/busybox" "$INITRAMFS_STAGE/bootstrap/busybox"
for applet in blkid mount sh sleep switch_root; do
    ln -s busybox "$INITRAMFS_STAGE/bootstrap/$applet"
done
cp "$ROOT_DIR/initramfs/init" "$INITRAMFS_STAGE/init"
cp "$ROOT_DIR/config/volumes.conf" "$INITRAMFS_STAGE/volumes.conf"
chmod 0755 "$INITRAMFS_STAGE/init" "$INITRAMFS_STAGE/bootstrap/busybox"

printf 'Creating initramfs\n'
"$ROOT_DIR/scripts/make-initramfs.sh" \
    "$INITRAMFS_STAGE" "$OUT_DIR/initramfs.cpio.gz"

printf '\nSolven build complete:\n'
printf '  Kernel:      %s\n' "$OUT_DIR/bzImage"
printf '  Initramfs:   %s\n' "$OUT_DIR/initramfs.cpio.gz"
printf '  Root volume: %s (%s MiB, UUID %s)\n' \
    "$ROOTFS_IMAGE" "$ROOTFS_SIZE_MIB" "$ROOT_VOLUME_UUID"
