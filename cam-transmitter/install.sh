#!/usr/bin/env bash
# One-time setup for a cam-transmitter Pi: system packages, Rust, the NDI
# runtime library, and the gst-plugin-ndi GStreamer plugin. Safe to re-run —
# each step skips itself if already done.
#
# Usage:
#   ./install.sh <ndi-name> [path-to-ndi-sdk-installer-or-extracted-folder]
#
# <ndi-name> is required and has no default on purpose — see ../README.md#naming.
# The NDI SDK itself is never bundled in this repo (proprietary, see
# ../README.md for why) — bring your own already-downloaded installer, e.g.:
#   scp ~/Documents/Install_NDI_SDK_v6_Linux.sh sat@<this-pi>:~/Documents/
#   ./install.sh SAT-CAM-DOMENORTH ~/Documents/Install_NDI_SDK_v6_Linux.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GST_PLUGIN_DIR="$HOME/gst-plugin-ndi"
NDI_SDK_LIB_DIR="$HOME/ndi-sdk/lib"
GST_PLUGIN_NDI_VERSION="0.15.3"
NDI_SDK_ARCH_DIR="aarch64-rpi4-linux-gnueabi"   # confirmed correct for 64-bit Raspberry Pi OS on a Pi 4

NDI_NAME="${1:-}"
SDK_SOURCE="${2:-}"

if [ -z "${NDI_NAME}" ]; then
  echo "usage: $0 <ndi-name> [path-to-ndi-sdk-installer-or-extracted-folder]" >&2
  echo "example: $0 SAT-CAM-DOMENORTH" >&2
  echo "see ../README.md#naming before picking a name" >&2
  exit 1
fi

echo "==> [1/5] system packages (will prompt for your sudo password)"
sudo apt-get update
sudo apt-get install -y \
  gstreamer1.0-libcamera gstreamer1.0-tools \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  build-essential pkg-config curl

echo "==> [2/5] Rust toolchain"
export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v cargo >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
fi
# shellcheck disable=SC1091
source "$HOME/.cargo/env"

echo "==> [3/5] NDI SDK runtime library"
if [ -f "${NDI_SDK_LIB_DIR}/libndi.so.6" ]; then
  echo "    already set up at ${NDI_SDK_LIB_DIR}, skipping"
else
  if [ -z "${SDK_SOURCE}" ]; then
    echo "error: NDI SDK not found at ${NDI_SDK_LIB_DIR} and no source was given." >&2
    echo "  NDI's SDK is proprietary and can't be bundled in this repo (see ../README.md)." >&2
    echo "  Transfer your own downloaded installer from another machine, e.g.:" >&2
    echo "    scp ~/Documents/Install_NDI_SDK_v6_Linux.sh sat@\$(hostname):~/Documents/" >&2
    echo "  then re-run: $0 ${NDI_NAME} ~/Documents/Install_NDI_SDK_v6_Linux.sh" >&2
    exit 1
  fi

  if [ -d "${SDK_SOURCE}" ]; then
    SDK_DIR="${SDK_SOURCE}"
  elif [ -f "${SDK_SOURCE}" ]; then
    echo "    running the installer (accept the EULA when prompted)"
    SDK_EXTRACT_PARENT="$(dirname "${SDK_SOURCE}")"
    (cd "${SDK_EXTRACT_PARENT}" && bash "$(basename "${SDK_SOURCE}")")
    SDK_DIR="${SDK_EXTRACT_PARENT}/NDI SDK for Linux"
  else
    echo "error: '${SDK_SOURCE}' is neither a file nor a directory" >&2
    exit 1
  fi

  LIB_SRC="${SDK_DIR}/lib/${NDI_SDK_ARCH_DIR}"
  if [ ! -d "${LIB_SRC}" ]; then
    echo "error: expected ${LIB_SRC} — available lib folders:" >&2
    ls "${SDK_DIR}/lib" >&2 || true
    exit 1
  fi
  SO_FILE="$(find "${LIB_SRC}" -maxdepth 1 -name 'libndi.so.*' | sort -V | tail -1)"
  if [ -z "${SO_FILE}" ]; then
    echo "error: no libndi.so.* found in ${LIB_SRC}" >&2
    exit 1
  fi

  mkdir -p "${NDI_SDK_LIB_DIR}"
  cp "${SO_FILE}" "${NDI_SDK_LIB_DIR}/"
  ln -sf "$(basename "${SO_FILE}")" "${NDI_SDK_LIB_DIR}/libndi.so.6"
  ln -sf "$(basename "${SO_FILE}")" "${NDI_SDK_LIB_DIR}/libndi.so"
  echo "    installed $(basename "${SO_FILE}") -> ${NDI_SDK_LIB_DIR}"
fi

echo "==> [4/5] gst-plugin-ndi ${GST_PLUGIN_NDI_VERSION} (actively maintained, part of GStreamer's gst-plugins-rs)"
if [ -f "${GST_PLUGIN_DIR}/target/release/libgstndi.so" ]; then
  echo "    already built at ${GST_PLUGIN_DIR}, skipping"
else
  rm -rf "${GST_PLUGIN_DIR}"
  mkdir -p "${GST_PLUGIN_DIR}"
  curl -sSL -A "networked-rpi-cams-install (${USER}@$(hostname))" \
    "https://crates.io/api/v1/crates/gst-plugin-ndi/${GST_PLUGIN_NDI_VERSION}/download" \
    -o "/tmp/gst-plugin-ndi-${GST_PLUGIN_NDI_VERSION}.crate"
  tar xzf "/tmp/gst-plugin-ndi-${GST_PLUGIN_NDI_VERSION}.crate" --strip-components=1 -C "${GST_PLUGIN_DIR}"
  rm -f "/tmp/gst-plugin-ndi-${GST_PLUGIN_NDI_VERSION}.crate"
  (cd "${GST_PLUGIN_DIR}" && cargo build --release)
fi

echo "==> [5/5] verifying and saving NDI name"
export GST_PLUGIN_PATH="${GST_PLUGIN_DIR}/target/release"
export NDI_RUNTIME_DIR_V6="${NDI_SDK_LIB_DIR}"
if ! gst-inspect-1.0 ndisink >/dev/null 2>&1; then
  echo "error: ndisink didn't load — check the output above for the real error:" >&2
  gst-inspect-1.0 ndisink >&2
  exit 1
fi

echo "NDI_NAME=\"${NDI_NAME}\"" > "${SCRIPT_DIR}/scripts/ndi-name.conf"

cat <<EOF

Setup complete. This Pi will transmit as NDI source '${NDI_NAME}'.

Start it with:
  ${SCRIPT_DIR}/scripts/start-ndi-stream.sh

To have it start on boot, see the "Run on boot" section in README.md.
EOF
