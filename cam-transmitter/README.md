# cam-transmitter

Runs on a Raspberry Pi 4 with a Raspberry Pi HQ Camera (IMX477) on the CSI
port. Captures video with `libcamera` and publishes it as an NDI source on
the LAN, using GStreamer as the glue.

## Pipeline

```
libcamerasrc  -->  videoconvert  -->  ndisink
(IMX477, CSI)      (to UYVY)         (NDI source on LAN)
```

## 1. System packages

```bash
sudo apt-get update
sudo apt-get install -y \
  gstreamer1.0-libcamera gstreamer1.0-tools \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
  build-essential pkg-config curl
```

Verify the camera pipeline works before touching NDI:

```bash
gst-launch-1.0 libcamerasrc ! videoconvert ! autovideosink
```

(skip if headless — `rpicam-hello -t 2000` from the earlier check is enough
proof libcamera sees the sensor)

## 2. NDI SDK (manual step — can't be scripted)

1. Create a free account at ndi.video and accept the EULA.
2. Download **NDI SDK for Linux** (look for the aarch64/arm64 build).
3. Extract it somewhere stable, e.g.:
   ```bash
   sudo mkdir -p /opt/NDI
   sudo tar xf NDI_SDK_Linux.tar.gz -C /opt/NDI
   ```
4. Note the path to `lib/aarch64-linux-gnu` (or similar) inside the SDK — the
   next step needs it.

## 3. Rust + gst-plugin-ndi

`gst-plugin-ndi` (github.com/teltek/gst-plugin-ndi) provides the `ndisink`
element. It's a Rust `gstreamer-rs` plugin, built with `cargo-c`.

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
cargo install cargo-c

git clone https://github.com/teltek/gst-plugin-ndi.git
cd gst-plugin-ndi
```

The exact env var this crate expects for the SDK location (commonly
`NDI_SDK_DIR`, but check the repo's own README/`build.rs` at clone time —
it has changed across versions) needs to point at the SDK folder from step 2:

```bash
export NDI_SDK_DIR=/opt/NDI   # confirm the variable name against the repo README
cargo cbuild --release
sudo cargo cinstall --release --prefix=/usr
```

Confirm the plugin registered:

```bash
gst-inspect-1.0 ndisink
```

If the property names below (`ndi-name`) don't match what `gst-inspect-1.0`
shows, use whatever it reports instead — plugin versions have renamed these.

## 4. Start streaming

```bash
./scripts/start-ndi-stream.sh
```

Env vars (all optional, defaults shown):

| Var | Default | Notes |
|---|---|---|
| `NDI_NAME` | `SAT-CAM-1` | Name this source shows as in OBS/Ossia. Give each transmitter Pi a unique name. |
| `WIDTH` | `2028` | Native 2x2-binned IMX477 mode — full sensor width, no scaling cost. |
| `HEIGHT` | `1080` | |
| `FRAMERATE` | `30` | This mode supports up to ~74fps if you need more headroom; raise if the network/decode side keeps up. |

Other native binned modes (from `rpicam-hello --list-cameras`), in case you
want to trade resolution for fps or vice versa:

| Mode | Max fps | Notes |
|---|---|---|
| 1332x990 | ~120 | fast motion, cropped FOV |
| 2028x1080 | ~74 | **default** — good balance, slightly cropped FOV |
| 2028x1520 | ~53 | full sensor FOV (4:3), a bit lower fps |
| 4056x3040 | ~14 | full resolution, not suited to smooth motion |

## 5. Run on boot (optional)

Once the manual pipeline works reliably, wrap `start-ndi-stream.sh` in a
systemd unit (`/etc/systemd/system/cam-transmitter.service`) with
`Restart=on-failure` so it survives reboots and camera hiccups. Not created
yet — do this once the stream has been validated end-to-end into OBS/Ossia.

## Bandwidth note

Standard NDI at 2028x1080p30 runs roughly 100-150 Mbps. Use wired Ethernet
on this Pi, not Wi-Fi.
