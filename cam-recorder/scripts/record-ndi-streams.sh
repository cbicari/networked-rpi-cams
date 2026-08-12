#!/usr/bin/env bash
# Records two NDI sources (from cam-transmitter Pis) to separate matroska
# files. See ../README.md for setup (GStreamer + gst-plugin-ndi + NDI SDK).
set -euo pipefail

NDI_SOURCE_1="${NDI_SOURCE_1:-SAT-CAM-1}"
NDI_SOURCE_2="${NDI_SOURCE_2:-SAT-CAM-2}"
OUTPUT_DIR="${OUTPUT_DIR:-./recordings}"

if ! gst-inspect-1.0 ndisrc >/dev/null 2>&1; then
  echo "error: ndisrc element not found. Build gst-plugin-ndi first (see README.md)." >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
timestamp="$(date +%Y%m%d_%H%M%S)"

record_source() {
  local ndi_name="$1"
  local outfile="${OUTPUT_DIR}/${ndi_name}_${timestamp}.mkv"
  echo "recording '${ndi_name}' -> ${outfile}"
  gst-launch-1.0 -e \
    ndisrc ndi-name="${ndi_name}" \
    ! videoconvert \
    ! x264enc tune=zerolatency bitrate=8000 \
    ! matroskamux \
    ! filesink location="${outfile}" &
}

record_source "${NDI_SOURCE_1}"
pid1=$!
record_source "${NDI_SOURCE_2}"
pid2=$!

trap 'echo "stopping, finalizing files..."; kill -INT "${pid1}" "${pid2}" 2>/dev/null || true; wait "${pid1}" "${pid2}"' INT TERM

wait "${pid1}" "${pid2}"
