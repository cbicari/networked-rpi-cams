#!/usr/bin/env bash
# Captures from the IMX477 (HQ Camera) via libcamera and publishes it as an
# NDI source. See ../README.md for setup (GStreamer + gst-plugin-ndi + NDI SDK).
set -euo pipefail

NDI_NAME="${NDI_NAME:-SAT-CAM-1}"
WIDTH="${WIDTH:-2028}"
HEIGHT="${HEIGHT:-1080}"
FRAMERATE="${FRAMERATE:-30}"

if ! gst-inspect-1.0 ndisink >/dev/null 2>&1; then
  echo "error: ndisink element not found. Build gst-plugin-ndi first (see README.md)." >&2
  exit 1
fi

exec gst-launch-1.0 -e \
  libcamerasrc \
  ! "video/x-raw,width=${WIDTH},height=${HEIGHT},framerate=${FRAMERATE}/1" \
  ! videoconvert \
  ! "video/x-raw,format=UYVY" \
  ! ndisink ndi-name="${NDI_NAME}"
