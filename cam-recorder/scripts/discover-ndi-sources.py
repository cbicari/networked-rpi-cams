#!/usr/bin/env python3
# Lists NDI sources currently visible on the LAN. Used by
# record-ndi-streams.sh to offer an interactive picker instead of requiring
# NDI_SOURCE_1/2 to be typed out by hand.
#
# Prints one source per line as "<index>\t<full ndi-name>" to stdout.
# The full ndi-name (e.g. "RASPBERRYPI (ndi_cam_2)", hostname included) is
# what ndisrc's ndi-name property actually needs to match — not the short
# name passed as NDI_NAME on the transmitter side. See ../README.md.
import os
import sys
import time

import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gst

Gst.init(None)

timeout = float(os.environ.get("NDI_DISCOVERY_TIMEOUT", "4"))

monitor = Gst.DeviceMonitor.new()
monitor.add_filter("Source/Network", None)
monitor.start()
time.sleep(timeout)
devices = monitor.get_devices()
monitor.stop()

# dict preserves discovery order while deduping (a source can be reported
# more than once during the scan window).
seen = {}
for device in devices:
    props = device.get_properties()
    ndi_name = props.get_string("ndi-name") if props else None
    if ndi_name and ndi_name not in seen:
        seen[ndi_name] = True

for index, name in enumerate(seen, start=1):
    print(f"{index}\t{name}")
