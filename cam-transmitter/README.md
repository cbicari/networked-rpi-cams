# cam-transmitter

Runs on a Raspberry Pi 4 with a Raspberry Pi HQ Camera (IMX477) on the CSI
port. Captures video with `libcamera` and publishes it as an NDI source on
the LAN, using GStreamer as the glue.

## Pipeline

```
libcamerasrc  -->  videoconvert  -->  ndisink
(IMX477, CSI)      (to UYVY)         (NDI source on LAN)
```

## Getting the NDI SDK

This is the one step `install.sh` can't do for you — NDI's SDK requires a
free account + clicking through a EULA on NDI's own site, per machine or per
person. Everything else below is scripted.

1. **Sign up and download.** Go to ndi.video, create a free account, agree
   to the license. You'll get an email with per-platform download links.
2. **Pick "Linux," not "Android for Linux."** Both appear in the email —
   easy to grab the wrong one. "Android for Linux" is a cross-compiler
   toolchain for building *Android* apps from a Linux host; it produces
   Android/Bionic binaries, not something that runs on Raspberry Pi OS.
   "Linux" is the one with native glibc libraries — that's Raspberry Pi OS.
3. **This downloads an installer shell script**, something like
   `Install_NDI_SDK_v6_Linux.sh`. It's small (a few KB) — the actual SDK is
   bundled inside it as a self-extracting archive. Download it wherever's
   convenient (your laptop is fine, doesn't have to be the Pi itself).
4. **Get that file onto the Pi.** If you downloaded it on your laptop:
   ```bash
   scp Install_NDI_SDK_v6_Linux.sh sat@<pi-ip-or-hostname>:~/Documents/
   ```
   (any destination folder works — `install.sh` just needs the path to it.)
5. **Hand the installer straight to `install.sh` — don't run it yourself
   first.** `install.sh` runs it for you, extraction included:
   ```bash
   ./install.sh SAT-CAM-DOMENORTH ~/Documents/Install_NDI_SDK_v6_Linux.sh
   ```
   It'll pause partway through to show you the license text — type `y` to
   accept when it asks. That's the only interactive part of this whole step.

**What happens after you type `y` (useful if something goes wrong):**
the installer self-extracts into a folder literally named `NDI SDK for
Linux`, created next to wherever the `.sh` file was (so given the path
above, that's `~/Documents/NDI SDK for Linux/`). `install.sh` then copies
*only* the one file this Pi actually needs — the aarch64 runtime library at
`NDI SDK for Linux/lib/aarch64-rpi4-linux-gnueabi/libndi.so.*` (yes, that
folder name is really `-rpi4-` — that's NDI's own naming, confirmed correct
for 64-bit Raspberry Pi OS on a Pi 4) — into `~/ndi-sdk/lib/`, alongside the
`libndi.so`/`libndi.so.6` symlinks GStreamer needs. Nothing else from the SDK
(headers, docs, other architectures) is used or needed.

**Already extracted it yourself, or copying an already-extracted folder from
another Pi instead of the raw installer?** Point `install.sh` at the folder
directly instead of the `.sh` file — it accepts both:
```bash
./install.sh SAT-CAM-DOMENORTH "~/Documents/NDI SDK for Linux"
```

**Verify it actually landed correctly**, independent of `install.sh`:
```bash
ls -la ~/ndi-sdk/lib/
#   libndi.so.6.3.2   (real file)
#   libndi.so.6 -> libndi.so.6.3.2   (symlink)
#   libndi.so -> libndi.so.6.3.2     (symlink)
file ~/ndi-sdk/lib/libndi.so.6.*
#   should say: ELF 64-bit LSB shared object, ARM aarch64
```

**You only ever do this once per Pi.** Once `~/ndi-sdk/lib/libndi.so.6`
exists, `install.sh` detects it on every future run and skips straight past
this whole section — you can delete the installer/extracted folder
afterward, and you never need to pass the SDK argument again unless you
`rm -rf ~/ndi-sdk` (or you're setting up a different Pi from scratch, which
needs its own accepted EULA anyway).

**Common mistakes, in order of how often they bite:**
- Picking "Android for Linux" in step 2 (see above).
- Running the installer `.sh` manually first, then also passing it to
  `install.sh` — harmless (it'll just re-extract), but unnecessary; just
  hand `install.sh` the file directly.
- Assuming `~/ndi-sdk/lib` needs the SDK's `include/` headers too — it
  doesn't. `gst-plugin-ndi` loads `libndi.so.6` at runtime via `dlopen`, not
  at compile time, so only that one shared library file ever matters here.

## Setup

```bash
./install.sh <ndi-name> [path-to-ndi-sdk-installer-or-extracted-folder]
```

`<ndi-name>` is required — see [../README.md#naming](../README.md#naming)
before picking one. The SDK argument is only needed the first time, per the
section above.

The script is idempotent — safe to re-run after a failure or to pick up a
newer `gst-plugin-ndi` release later (delete `~/gst-plugin-ndi` first to
force a rebuild).

It installs, in order: GStreamer + its libcamera plugin + dev headers (apt,
needs your `sudo` password interactively), Rust via rustup, the NDI runtime
library (see above), and
[`gst-plugin-ndi`](https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs/-/tree/main/net/ndi)
v0.15.3 (the actively-maintained one bundled in GStreamer's own `gst-plugins-rs`
collection — built from its published crates.io source). Finally it saves
your chosen name to `scripts/ndi-name.conf` (git-ignored, per-machine).

Sanity-check the camera alone first, before NDI is even in the picture:

```bash
gst-launch-1.0 libcamerasrc ! videoconvert ! autovideosink
```

(skip if headless — `rpicam-hello -t 2000` from the earlier check is enough
proof libcamera sees the sensor)

## Start streaming

```bash
./scripts/start-ndi-stream.sh
```

Env vars (all optional except that `NDI_NAME` must come from somewhere —
either this or `scripts/ndi-name.conf`, written by `install.sh`):

| Var | Default | Notes |
|---|---|---|
| `NDI_NAME` | *(none — from `ndi-name.conf`, or the script exits with an error)* | Deliberately has no hardcoded fallback — see [../README.md#naming](../README.md#naming). |
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

## Run on boot (optional)

Once the manual pipeline works reliably, wrap `start-ndi-stream.sh` in a
systemd unit (`/etc/systemd/system/cam-transmitter.service`) with
`Restart=on-failure` so it survives reboots and camera hiccups. Not created
yet — do this once the stream has been validated end-to-end into OBS/Ossia.

## Bandwidth note

Standard NDI at 2028x1080p30 runs roughly 100-150 Mbps. Use wired Ethernet
on this Pi, not Wi-Fi.
