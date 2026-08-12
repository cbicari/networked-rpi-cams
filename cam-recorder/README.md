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

Same GStreamer + Rust + `gst-plugin-ndi` build as `cam-transmitter/` — see
[../cam-transmitter/README.md](../cam-transmitter/README.md#setup). There's
no `install.sh` for this role yet (only asked for on the transmitter side so
far) — for now, either adapt `cam-transmitter/install.sh` (swap the
`ndisink` verification for `ndisrc`) or follow its steps manually. This Pi
needs `ndisrc`/`ndisrcdemux` (from the same plugin) instead of `ndisink`,
plus an H.264 encoder to keep recordings a manageable size:

```bash
sudo apt-get install -y gstreamer1.0-plugins-ugly  # x264enc, if not already pulled in by -bad
```

Confirm after building the plugin:

```bash
gst-inspect-1.0 ndisrc
gst-inspect-1.0 ndisrcdemux
```

## 2. Start recording

```bash
NDI_SOURCE_1=SAT-CAM-DOMENORTH NDI_SOURCE_2=SAT-CAM-DOMESOUTH ./scripts/record-ndi-streams.sh
```

Env vars:

| Var | Default | Notes |
|---|---|---|
| `NDI_SOURCE_1` | *(none — required, script exits with an error if unset)* | Must match the `NDI_NAME` set on that transmitter Pi. See [../README.md#naming](../README.md#naming). |
| `NDI_SOURCE_2` | *(none — required)* | |
| `OUTPUT_DIR` | `./recordings` | Created if missing. |

Each run produces two timestamped files:

```
recordings/SAT-CAM-DOMENORTH_<timestamp>.mkv
recordings/SAT-CAM-DOMESOUTH_<timestamp>.mkv
```

Stop with Ctrl-C — the script traps it and lets both `gst-launch-1.0`
processes finalize their files cleanly (matroska needs a clean shutdown to
remux its index; killing `-9` will leave you needing `mkvalidator`/remux to
recover the file).

## 3. Run on boot (optional)

Same approach as `cam-transmitter`: once validated, wrap in a systemd unit.
Not created yet.
