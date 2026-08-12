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
ndisrc (one per camera) --> videoconvert --> x264enc --> matroskamux --> filesink
```

Recording is done as two independent GStreamer pipelines (one per NDI
source), not a single combined one — so one camera dropping out doesn't take
the other's recording down with it.

## 1. System packages

Same GStreamer + Rust + `gst-plugin-ndi` build as `cam-transmitter/` — see
[../cam-transmitter/README.md](../cam-transmitter/README.md) steps 1-3. This
Pi needs the `ndisrc` element (from the same plugin) instead of `ndisink`,
plus an H.264 encoder to keep recordings a manageable size:

```bash
sudo apt-get install -y gstreamer1.0-plugins-ugly  # x264enc, if not already pulled in by -bad
```

Confirm after building the plugin:

```bash
gst-inspect-1.0 ndisrc
```

## 2. Start recording

```bash
./scripts/record-ndi-streams.sh
```

Env vars:

| Var | Default | Notes |
|---|---|---|
| `NDI_SOURCE_1` | `SAT-CAM-1` | Must match the `NDI_NAME` set on that transmitter Pi. |
| `NDI_SOURCE_2` | `SAT-CAM-2` | |
| `OUTPUT_DIR` | `./recordings` | Created if missing. |

Each run produces two timestamped files:

```
recordings/SAT-CAM-1_<timestamp>.mkv
recordings/SAT-CAM-2_<timestamp>.mkv
```

Stop with Ctrl-C — the script traps it and lets both `gst-launch-1.0`
processes finalize their files cleanly (matroska needs a clean shutdown to
remux its index; killing `-9` will leave you needing `mkvalidator`/remux to
recover the file).

## 3. Run on boot (optional)

Same approach as `cam-transmitter`: once validated, wrap in a systemd unit.
Not created yet.
