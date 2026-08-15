#!/usr/bin/env bash
# Records one or two NDI sources (from cam-transmitter Pis) to separate
# matroska files. See ../README.md for setup (GStreamer + gst-plugin-ndi +
# NDI SDK).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISCOVER_SCRIPT="${SCRIPT_DIR}/discover-ndi-sources.py"

export GST_PLUGIN_PATH="${GST_PLUGIN_PATH:-$HOME/gst-plugin-ndi/target/release}"
export NDI_RUNTIME_DIR_V6="${NDI_RUNTIME_DIR_V6:-$HOME/ndi-sdk/lib}"

OUTPUT_DIR="${OUTPUT_DIR:-./recordings}"

if ! gst-inspect-1.0 ndisrc >/dev/null 2>&1; then
  echo "error: ndisrc element not found. Run install.sh first (see README.md)." >&2
  exit 1
fi

# If NDI_SOURCE_1 isn't already set (e.g. by a systemd unit for unattended
# recording), scan the LAN and let the user pick interactively instead of
# having to know the exact NDI name up front — this is also the full
# "HOSTNAME (name)" string ndisrc actually needs, not just the short NDI_NAME
# a transmitter Pi was given, so guessing it by hand is error-prone anyway.
if [ -z "${NDI_SOURCE_1:-}" ]; then
  if [ ! -t 0 ]; then
    echo "error: NDI_SOURCE_1 is not set and this isn't an interactive terminal to pick one in." >&2
    echo "  set NDI_SOURCE_1 (and optionally NDI_SOURCE_2) explicitly for unattended use." >&2
    exit 1
  fi
  if ! python3 -c "import gi; gi.require_version('Gst', '1.0'); from gi.repository import Gst" >/dev/null 2>&1; then
    echo "error: python3-gi / gir1.2-gstreamer-1.0 not found, needed for NDI source discovery." >&2
    echo "  re-run install.sh to pick them up, or set NDI_SOURCE_1 (and optionally NDI_SOURCE_2) yourself." >&2
    exit 1
  fi

  discovery_timeout="${NDI_DISCOVERY_TIMEOUT:-4}"
  echo "scanning the network for NDI sources (${discovery_timeout}s)..."
  mapfile -t discovered < <(NDI_DISCOVERY_TIMEOUT="${discovery_timeout}" python3 "${DISCOVER_SCRIPT}")
  if [ "${#discovered[@]}" -eq 0 ]; then
    echo "error: no NDI sources found on the network." >&2
    echo "  check the transmitter Pi(s) are running (see ../cam-transmitter/README.md)" >&2
    echo "  and that this Pi and the transmitters are on the same wired LAN." >&2
    exit 1
  fi

  declare -A source_by_index
  echo "NDI sources found:"
  for line in "${discovered[@]}"; do
    index="${line%%$'\t'*}"
    name="${line#*$'\t'}"
    source_by_index["${index}"]="${name}"
    echo "  ${index}) ${name}"
  done

  prompt_for_source() {
    local prompt="$1"
    local allow_skip="$2"
    local choice
    while true; do
      read -r -p "${prompt}" choice
      if [ -z "${choice}" ] && [ "${allow_skip}" = "1" ]; then
        return 0
      fi
      if [ -n "${source_by_index[${choice}]:-}" ]; then
        printf '%s' "${source_by_index[${choice}]}"
        return 0
      fi
      echo "invalid selection, try again" >&2
    done
  }

  NDI_SOURCE_1="$(prompt_for_source "select stream to record (number): " 0)"
  NDI_SOURCE_2="$(prompt_for_source "select a second stream to also record (number, Enter to skip): " 1)"
fi

mkdir -p "${OUTPUT_DIR}"
timestamp="$(date +%Y%m%d_%H%M%S)"

record_source() {
  local ndi_name="$1"
  # ndi_name may be the full "HOSTNAME (stream name)" form from discovery,
  # which isn't filesystem-safe as-is — sanitize for the filename only, the
  # gst pipeline below still gets the exact, unsanitized ndi_name.
  local safe_name
  safe_name="$(printf '%s' "${ndi_name}" | tr -c 'A-Za-z0-9_.-' '_' | tr -s '_' | sed -e 's/^_//' -e 's/_$//')"
  local outfile="${OUTPUT_DIR}/${safe_name}_${timestamp}.mkv"
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

pids=()

record_source "${NDI_SOURCE_1}"
pids+=("$!")

if [ -n "${NDI_SOURCE_2:-}" ]; then
  record_source "${NDI_SOURCE_2}"
  pids+=("$!")
fi

trap 'echo "stopping, finalizing files..."; kill -INT "${pids[@]}" 2>/dev/null || true; wait "${pids[@]}"' INT TERM

wait "${pids[@]}"
