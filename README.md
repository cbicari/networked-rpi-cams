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

## Naming

Every transmitter needs a unique NDI source name — two Pis broadcasting the
same name makes discovery ambiguous, and a receiver may connect to the wrong
one or flap between them. `cam-transmitter/install.sh` takes the name as a
required argument (no default) specifically so cloning the same install onto
a new Pi forces you to pick a new name rather than silently duplicating one.

**Format:** `SAT-CAM-<LOCATION>`, all caps, no spaces (hyphenate multi-word
locations) — e.g. `SAT-CAM-DOMENORTH`, `SAT-CAM-STAGE-L`, `SAT-CAM-ENTRANCE`.
Pick location tokens that mean something on-site, not a generic counter —
`SAT-CAM-1`/`SAT-CAM-2` tell you nothing when you're debugging which physical
camera dropped out.

Keep a running table here as machines get deployed, so there's one place to
check for collisions or to find which Pi is which:

| NDI name | Hostname | Physical location | Notes |
|---|---|---|---|
| `SAT-CAM-TEST` | `raspberrypi` | test bench | first HQ camera, used to validate the transmit/receive pipeline |

Optional: set the Pi's actual Linux hostname to match (e.g. `sat-cam-domenorth`)
so `ssh sat@sat-cam-domenorth.local` works via avahi/mDNS too. `install.sh`
doesn't do this automatically — a hostname change touches machine identity
and needs a reboot, so it's left as a deliberate manual step
(`sudo raspi-config` → System Options → Hostname).

## NDI SDK dependency

Every machine here needs the **NDI SDK for Linux** (aarch64 build) at runtime
(just the `libndi.so` runtime library — building `gst-plugin-ndi` itself
needs no NDI headers, see `cam-transmitter/README.md`). NewTek/Vizrt only
distribute it after a free account signup + EULA at ndi.video — this can't
be automated, and `install.sh` in each machine folder expects you to hand it
your own already-downloaded installer.

**Deliberately not bundled in this repo.** The NDI SDK license restricts
redistribution to specific files identified in NDI's own SDK documentation
(not a blanket "embed it anywhere" grant), and separately, its definition of
a freely-licensable "Product" explicitly excludes software built for
*"hardware that may be categorized as an embedded device, and utilizing an
operating system typically used for embedded devices... Linux, Linux
derivatives..."* — which a Raspberry Pi running a fixed-purpose camera
appliance sits close enough to that it's worth NDI/Vizrt confirming directly
if this ever needs to be certain, rather than us assuming. Since this repo
is on GitHub, committing the proprietary binary would make that ambiguity
everyone's problem. Instead: transfer your own downloaded installer between
your own machines via `scp` — same license coverage you already have, zero
redistribution question, and `install.sh` just asks for its path.
