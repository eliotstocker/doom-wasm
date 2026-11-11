#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
DIST_DIR="${ROOT_DIR}/dist"
PATCHES_DIR="${ROOT_DIR}/patches"
SHIM_DIR="${ROOT_DIR}/shim"
DEPS_DIR="${ROOT_DIR}/deps"

DOOM_ASCII_REPO="https://github.com/wojciech-graj/doom-ascii.git"
DOOM_ASCII_COMMIT="940528f138e12431e5a1417351863709f1620078"
DOOM_SRC="${BUILD_DIR}/doom-ascii"

mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

# 1. Detect or provision wasi-sdk
WASI_SDK_MAJOR="25"
WASI_SDK_VERSION="25.0"
RAW_ARCH="$(uname -m)"
RAW_OS="$(uname -s)"
if [ "${RAW_ARCH}" = "x86_64" ]; then
    HOST_ARCH="x86_64"
else
    HOST_ARCH="arm64"
fi
if [ "${RAW_OS}" = "Darwin" ]; then
    HOST_OS="macos"
else
    HOST_OS="linux"
fi

WASI_SDK_DIR="${WASI_SDK_PATH:-${BUILD_DIR}/wasi-sdk-${WASI_SDK_VERSION}-${HOST_ARCH}-${HOST_OS}}"
if [ ! -d "${WASI_SDK_DIR}" ] && [ -d "${ROOT_DIR}/../nano-wasm/build/wasi-sdk-${WASI_SDK_VERSION}-${HOST_ARCH}-${HOST_OS}" ]; then
    WASI_SDK_DIR="${ROOT_DIR}/../nano-wasm/build/wasi-sdk-${WASI_SDK_VERSION}-${HOST_ARCH}-${HOST_OS}"
fi
if [ ! -d "${WASI_SDK_DIR}" ] && [ -d "/opt/wasi-sdk" ]; then
    WASI_SDK_DIR="/opt/wasi-sdk"
fi

if [ ! -d "${WASI_SDK_DIR}" ]; then
    echo "=== Downloading wasi-sdk ${WASI_SDK_VERSION} ==="
    URL="https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_MAJOR}/wasi-sdk-${WASI_SDK_VERSION}-${HOST_ARCH}-${HOST_OS}.tar.gz"
    curl -fsSL "${URL}" | tar -xz -C "${BUILD_DIR}"
fi

CC="${WASI_SDK_DIR}/bin/clang"

# 2. Detect or provision wasm-opt (Binaryen)
BINARYEN_VERSION="119"
BINARYEN_DIR="${BUILD_DIR}/binaryen-version_${BINARYEN_VERSION}"
if [ -d "${ROOT_DIR}/../nano-wasm/build/binaryen-version_${BINARYEN_VERSION}" ]; then
    BINARYEN_DIR="${ROOT_DIR}/../nano-wasm/build/binaryen-version_${BINARYEN_VERSION}"
fi

WASM_OPT="${BINARYEN_DIR}/bin/wasm-opt"
if ! command -v "${WASM_OPT}" >/dev/null 2>&1; then
    if command -v wasm-opt >/dev/null 2>&1; then
        WASM_OPT="wasm-opt"
    else
        echo "=== Downloading Binaryen version_${BINARYEN_VERSION} ==="
        URL="https://github.com/WebAssembly/binaryen/releases/download/version_${BINARYEN_VERSION}/binaryen-version_${BINARYEN_VERSION}-${HOST_ARCH}-${HOST_OS}.tar.gz"
        curl -fsSL "${URL}" | tar -xz -C "${BUILD_DIR}"
    fi
fi

# 3. Ensure wasi-termios-brsh is present
WASI_TERMIOS_DIR="${DEPS_DIR}/wasi-termios-brsh"
if [ ! -d "${WASI_TERMIOS_DIR}/include" ]; then
    echo "=== Initializing wasi-termios-brsh submodule ==="
    git -C "${ROOT_DIR}" submodule update --init --recursive
fi

# 4. Clone and patch doom-ascii
if [ ! -d "${DOOM_SRC}/.git" ]; then
    echo "=== Cloning doom-ascii (${DOOM_ASCII_COMMIT}) ==="
    rm -rf "${DOOM_SRC}"
    git clone "${DOOM_ASCII_REPO}" "${DOOM_SRC}"
    git -C "${DOOM_SRC}" checkout "${DOOM_ASCII_COMMIT}"
fi

echo "=== Applying WASI/brsh patches to doom-ascii ==="
git -C "${DOOM_SRC}" checkout -- .
for patch in "${PATCHES_DIR}"/*.patch; do
    if [ -f "${patch}" ]; then
        echo "Applying $(basename "${patch}")..."
        patch -d "${DOOM_SRC}" -p1 -N < "${patch}" || true
    fi
done

# 5. Compile doom-ascii to WebAssembly
echo "=== Compiling doom-ascii for wasm32-wasip1 ==="
CFLAGS=(
    --target=wasm32-wasip1
    -std=c99
    -O3
    -flto
    -Wall
    -D_GNU_SOURCE
    -D_DEFAULT_SOURCE
    -DNORMALUNIX
    -DLINUX
    -DVERSION=0.3.2
    -I"${DOOM_SRC}/src"
    -I"${WASI_TERMIOS_DIR}/include"
)

LDFLAGS=(
    --target=wasm32-wasip1
    -O3
    -flto
    -Wl,--export=set_terminal_size
    -Wl,--lto-O3
    -lm
)

SOURCES=(
    am_map.c d_event.c d_items.c d_iwad.c d_loop.c d_main.c d_mode.c d_net.c
    doomdef.c doomgeneric.c doomgeneric_ascii.c doomstat.c dstrings.c dummy.c
    f_finale.c f_wipe.c g_game.c hu_lib.c hu_stuff.c i_cdmus.c i_endoom.c
    i_input.c i_joystick.c i_main.c i_scale.c i_sound.c i_system.c i_timer.c
    i_video.c icon.c info.c m_argv.c m_bbox.c m_cheat.c m_config.c m_controls.c
    m_fixed.c m_menu.c m_misc.c m_random.c memio.c p_ceilng.c p_doors.c
    p_enemy.c p_floor.c p_inter.c p_lights.c p_map.c p_maputl.c p_mobj.c
    p_plats.c p_pspr.c p_saveg.c p_setup.c p_sight.c p_spec.c p_switch.c
    p_telept.c p_tick.c p_user.c r_bsp.c r_data.c r_draw.c r_main.c r_plane.c
    r_segs.c r_sky.c r_things.c s_sound.c sha1.c sounds.c statdump.c st_lib.c
    st_stuff.c tables.c v_video.c w_checksum.c w_file.c w_file_stdc.c w_main.c
    w_wad.c wi_stuff.c z_zone.c
)

OBJECTS=()
for src in "${SOURCES[@]}"; do
    obj="${BUILD_DIR}/${src%.c}.o"
    OBJECTS+=("${obj}")
    "${CC}" "${CFLAGS[@]}" -c "${DOOM_SRC}/src/${src}" -o "${obj}"
done

echo "=== Compiling wasi_stubs and wasi-termios-brsh ==="
"${CC}" "${CFLAGS[@]}" -c "${SHIM_DIR}/src/wasi_stubs.c" -o "${BUILD_DIR}/wasi_stubs.o"
OBJECTS+=("${BUILD_DIR}/wasi_stubs.o")

"${CC}" "${CFLAGS[@]}" -c "${WASI_TERMIOS_DIR}/src/termios.c" -o "${BUILD_DIR}/termios.o"
OBJECTS+=("${BUILD_DIR}/termios.o")

echo "=== Linking ${DIST_DIR}/doom.raw.wasm ==="
"${CC}" "${LDFLAGS[@]}" "${OBJECTS[@]}" -o "${DIST_DIR}/doom.raw.wasm"

echo "=== Instrumenting with Binaryen Asyncify ==="
"${WASM_OPT}" \
    --asyncify \
    --pass-arg=asyncify-imports@wasi_snapshot_preview1.clock_nanosleep,wasi_snapshot_preview1.poll_oneoff,wasi_snapshot_preview1.fd_read \
    -O3 \
    "${DIST_DIR}/doom.raw.wasm" \
    -o "${DIST_DIR}/doom.wasm"

cp "${DIST_DIR}/doom.wasm" "${ROOT_DIR}/doom.wasm"

echo "=== Build complete: ${DIST_DIR}/doom.wasm ($(du -h "${DIST_DIR}/doom.wasm" | cut -f1)) ==="
