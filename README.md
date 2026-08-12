# networked-rpi-cams

Code and setup docs for every machine in this camera installation. Each machine
gets its own folder with its own README — clone this repo on each Pi and only
follow the folder that matches its role.

## Architecture

```
[ RPi4 + HQ Camera #1 ]--NDI-->\
                                 [ LAN / switch ] -- NDI --> [ Laptop: OBS (monitor) + Ossia Score (interactivity/ML) ]
[ RPi4 + HQ Camera #2 ]--NDI-->/        |
                                        \--NDI--> [ RPi4 storage unit: records both fluxes to file ] (cam-recorder/)
```

- **[cam-transmitter/](cam-transmitter/)** — runs on each camera Pi. Captures
  from the IMX477 (HQ Camera) over CSI and publishes it as an NDI source on
  the LAN.
- **[cam-recorder/](cam-recorder/)** — runs on a dedicated storage Pi.
  Discovers both camera NDI sources and records each to its own file. Not in
  active use yet (monitoring/recording currently happens on the laptop via
  OBS instead), but kept ready here for when a dedicated recorder is needed.

## Why NDI

Chosen over RTSP because both destination apps — **OBS** (via the DistroAV
plugin) and **Ossia Score** — support NDI natively, with LAN auto-discovery
and no ingest server to run. RTSP would have been simpler to set up on the Pi
side alone, but NDI is simpler end-to-end given these two receivers.

**Trade-off to know about:** standard NDI (not NDI|HX) is bandwidth-heavy —
roughly 100–150 Mbps per 1080p30 stream. Two camera fluxes landing on the same
laptop that's also doing DMX + ML work means:
- Use **wired Ethernet**, not Wi-Fi, for both transmitter Pis, the switch, and
  the laptop. Two NDI streams over Wi-Fi will be unreliable.
- Watch CPU load on the laptop — NDI receive-side decoding is not free.
  If OBS/Ossia struggle, the fallback is NDI|HX (hardware H.264 via the Pi's
  encoder, far lower bitrate), which needs NDI's separate Advanced SDK and is
  a bigger setup lift — worth revisiting only if bandwidth/CPU actually
  becomes a problem.

## NDI SDK dependency

Every machine here needs the **NDI SDK for Linux** (aarch64 build) to build
`gst-plugin-ndi`. NewTek/Vizrt only distribute it after a free account
signup + EULA at their official site, ndi.video — this can't be automated.
Each folder's README notes exactly where it's needed.
