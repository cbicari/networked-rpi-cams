# cam-recorder

Runs on a dedicated Raspberry Pi 4 acting as a storage unit. Discovers both
camera NDI sources on the LAN (from `cam-transmitter/`) and records each one
to its own file.

**Status:** not in active use — monitoring/recording is currently done on
the laptop via OBS instead, to avoid deploying a third Pi. This folder is
kept ready for when a dedicated recorder is wanted (e.g. once the laptop is
too loaded with DMX + ML work to also record reliably).

## Pipeline (per source)

```
ndisrc --> ndisrcdemux --> videoconvert --> x264enc --> matroskamux --> filesink
(one per camera)
```

`ndisrc` outputs a muxed `application/x-ndi` container, not raw video —
`ndisrcdemux` splits it into the actual `video/x-raw` pad (confirmed by
inspecting the element; easy to miss since `gst-inspect-1.0 ndisrc` alone
doesn't make this obvious).

Recording is done as two independent GStreamer pipelines (one per NDI
source), not a single combined one — so one camera dropping out doesn't take
the other's recording down with it.

## 1. System packages

```bash
./install.sh [path-to-ndi-sdk-installer-or-extracted-folder]
```

Same GStreamer + Rust + `gst-plugin-ndi` build as `cam-transmitter/` — see
[../cam-transmitter/README.md](../cam-transmitter/README.md#getting-the-ndi-sdk)
for how to get the NDI SDK installer onto this Pi (same steps, same
one-time-per-Pi caveat). This Pi has no NDI name of its own, so unlike
`cam-transmitter/install.sh` there's no required name argument — the SDK
installer/folder path is the only (optional, first-run-only) argument.

Differences from the transmitter install: no `libcamera` package (no camera
on this Pi), plus `gstreamer1.0-plugins-ugly` for `x264enc` to keep
recordings a manageable size. It verifies `ndisrc`/`ndisrcdemux` (from the
same plugin) instead of `ndisink`, since this Pi receives NDI rather than
sending it.

The script is idempotent — safe to re-run after a failure or to pick up a
newer `gst-plugin-ndi` release later (delete `~/gst-plugin-ndi` first to
force a rebuild).

## 2. Start recording

```bash
./scripts/record-ndi-streams.sh
```

With no `NDI_SOURCE_1` set, it scans the LAN for a few seconds (via
`scripts/discover-ndi-sources.py`, using GStreamer's device monitor —
needs `python3-gi`/`gir1.2-gstreamer-1.0`, installed by `install.sh`) and
prompts you to pick interactively:

```
scanning the network for NDI sources (4s)...
NDI sources found:
  1) SAT-CAM-DOMENORTH-PI (SAT-CAM-DOMENORTH)
  2) SAT-CAM-DOMESOUTH-PI (SAT-CAM-DOMESOUTH)
select stream to record (number): 1
select a second stream to also record (number, Enter to skip): 2
```

**Why the names look like `HOSTNAME (NAME)` and not just the short name:**
that's the actual value `ndisrc`'s `ndi-name` property matches against — NDI
prepends the sending machine's hostname to whatever short name (e.g.
`SAT-CAM-DOMENORTH`) was set via `NDI_NAME` on that transmitter Pi (see
[../README.md#naming](../README.md#naming)). Typing just the short name
yourself will silently fail to connect (`ndisrcdemux` errors with "EOS
without available srcpad(s)" once `ndisrc`'s 10s connect timeout expires) —
which is exactly why the picker exists instead of asking you to type it
from memory.

Env vars:

| Var | Default | Notes |
|---|---|---|
| `NDI_SOURCE_1` | *(none — if unset, triggers the interactive picker above; requires a real terminal, see below)* | The full `HOSTNAME (name)` string, not the transmitter's short `NDI_NAME`. |
| `NDI_SOURCE_2` | *(none — optional)* | Set only to record a second camera alongside the first. Also skipped/prompted the same way as `NDI_SOURCE_1`. |
| `NDI_DISCOVERY_TIMEOUT` | `4` (seconds) | How long the picker scans before showing results. |
| `OUTPUT_DIR` | `./recordings` | Created if missing. |

For unattended use (no terminal to answer the prompt — e.g. a systemd
unit), set `NDI_SOURCE_1` yourself to skip the picker entirely:

```bash
NDI_SOURCE_1="SAT-CAM-DOMENORTH-PI (SAT-CAM-DOMENORTH)" ./scripts/record-ndi-streams.sh
```

The script exits with an error rather than hanging if `NDI_SOURCE_1` is
unset and stdin isn't a terminal.

Each run produces one timestamped file per source recorded, named from a
filesystem-safe version of its NDI name:

```
recordings/SAT-CAM-DOMENORTH-PI_SAT-CAM-DOMENORTH_<timestamp>.mkv
recordings/SAT-CAM-DOMESOUTH-PI_SAT-CAM-DOMESOUTH_<timestamp>.mkv   # only if a second source was picked/set
```

Stop with Ctrl-C — the script traps it and lets both `gst-launch-1.0`
processes finalize their files cleanly (matroska needs a clean shutdown to
remux its index; killing `-9` will leave you needing `mkvalidator`/remux to
recover the file).

## 3. Run on boot (optional)

Same approach as `cam-transmitter`: once validated, wrap in a systemd unit.
Not created yet.
