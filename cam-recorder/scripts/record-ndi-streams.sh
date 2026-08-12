#!/usr/bin/env bash
# Records two NDI sources (from cam-transmitter Pis) to separate matroska
# files. See ../README.md for setup (GStreamer + gst-plugin-ndi + NDI SDK).
set -euo pipefail

export GST_PLUGIN_PATH="${GST_PLUGIN_PATH:-$HOME/gst-plugin-ndi/target/release}"
export NDI_RUNTIME_DIR_V6="${NDI_RUNTIME_DIR_V6:-$HOME/ndi-sdk/lib}"

# No hardcoded defaults on purpose: recording from the wrong (or a
# nonexistent) source name silently produces an empty file. Fail loudly
# instead — see ../../README.md#naming for the names assigned to each
# cam-transmitter Pi.
: "${NDI_SOURCE_1:?set NDI_SOURCE_1 to the first transmitter's NDI name}"
: "${NDI_SOURCE_2:?set NDI_SOURCE_2 to the second transmitter's NDI name}"
OUTPUT_DIR="${OUTPUT_DIR:-./recordings}"

if ! gst-inspect-1.0 ndisrc >/dev/null 2>&1; then
  echo "error: ndisrc element not found. Run install.sh first (see README.md)." >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
timestamp="$(date +%Y%m%d_%H%M%S)"

record_source() {
  local ndi_name="$1"
  local outfile="${OUTPUT_DIR}/${ndi_name}_${timestamp}.mkv"
  echo "recording '${ndi_name}' -> ${outfile}"
  # ndisrc outputs a muxed application/x-ndi container — ndisrcdemux splits
  # it into the actual video/x-raw pad. Video-only: cam-transmitter doesn't
  # send audio, so there's no demux.audio branch here.
  gst-launch-1.0 -e \
    ndisrc ndi-name="${ndi_name}" ! ndisrcdemux name=demux \
    demux.video ! queue ! videoconvert \
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
