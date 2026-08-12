#!/usr/bin/env bash
# Captures from the IMX477 (HQ Camera) via libcamera and publishes it as an
# NDI source. See ../README.md for setup (GStreamer + gst-plugin-ndi + NDI SDK).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export GST_PLUGIN_PATH="${GST_PLUGIN_PATH:-$HOME/gst-plugin-ndi/target/release}"
export NDI_RUNTIME_DIR_V6="${NDI_RUNTIME_DIR_V6:-$HOME/ndi-sdk/lib}"

# NDI_NAME resolution order: explicit env var > per-machine config written by
# install.sh > loud failure. Never silently falls back to a fixed name — that's
# how two Pis end up broadcasting the same NDI source. See ../../README.md#naming.
if [ -z "${NDI_NAME:-}" ] && [ -f "${SCRIPT_DIR}/ndi-name.conf" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/ndi-name.conf"
fi
if [ -z "${NDI_NAME:-}" ]; then
  echo "error: NDI_NAME is not set and ${SCRIPT_DIR}/ndi-name.conf doesn't exist." >&2
  echo "       Run install.sh (which prompts for a name) or export NDI_NAME=... yourself." >&2
  exit 1
fi

WIDTH="${WIDTH:-2028}"
HEIGHT="${HEIGHT:-1080}"
FRAMERATE="${FRAMERATE:-30}"

if ! gst-inspect-1.0 ndisink >/dev/null 2>&1; then
  echo "error: ndisink element not found. Run install.sh first (see README.md)." >&2
  exit 1
fi

echo "Starting NDI source '${NDI_NAME}'"

exec gst-launch-1.0 -e \
  libcamerasrc \
  ! "video/x-raw,width=${WIDTH},height=${HEIGHT},framerate=${FRAMERATE}/1" \
  ! videoconvert \
  ! "video/x-raw,format=UYVY" \
  ! queue \
  ! ndisink ndi-name="${NDI_NAME}"
