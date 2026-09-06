# Changes

## 2026-09-06 — Receiver connection reset investigation and fixes

### Reported problem

The DisplayOS macOS host discovered the iMac receiver, but attempting to
connect failed with:

```text
Receiver connection failed: The operation couldn't be completed.
(Network.NWError error 54 - connection reset by peer)
```

The iMac continued to display its waiting screen and did not provide any
visible failure details.

### Investigation

- Confirmed that the host's direct Ethernet interface was active.
- Confirmed that Bonjour advertised `DisplayOS iMac` as
  `_displayos._tcp.local` on TCP port 9877.
- Resolved the receiver as `debian.local` / `192.168.1.81` on the local
  network.
- Successfully queried `http://192.168.1.81:9876/capabilities`, confirming
  that the receiver service was running and reachable.
- Confirmed that TCP port 22 was open, but the receiver only accepted a
  preconfigured SSH public key. The host's key was not authorized, so the
  receiver journal could not be read remotely.
- Identified that the host's receiver-discovery code tested reachability by
  opening TCP port 9877. Port 9877 is the video protocol itself, so the
  receiver treated this probe as a real streaming session and launched
  GStreamer before any framed H.264 data was available.
- Older receiver code could fail while cleaning up that empty session and
  terminate its video-server thread. A subsequent real connection could then
  be reset or left without a process accepting the stream.
- Confirmed that the receiver currently booted on the iMac is an older image:
  it does not publish the newer connecting, streaming, or failed UI states.

### Host discovery fix

Updated `apps/host-macos/Sources/DisplayOSApp.swift`:

- Removed the active TCP reachability probes against port 9877.
- Receiver availability now follows the Bonjour browse results directly.
- Removed the associated candidate/probe connection bookkeeping and timeout
  tasks.
- Restored discovery status messages to report discovered receivers instead
  of claiming that the destructive video-port probe made them reachable.

This prevents receiver discovery from being mistaken for a video session.
Only an explicit click on **Connect** now opens the stream port.

### Accurate host connection state

Updated `apps/host-macos/Sources/StreamingManager.swift` after observing that
the app displayed `Streaming` even though `lsof` and `netstat` showed no TCP
connection to port 9877:

- Stream setup now waits asynchronously for `NWConnection` to enter the
  `ready` state before configuring capture and encoding.
- Connection failure and cancellation now terminate setup with the real
  Network framework error.
- Added identity checks after asynchronous setup operations so cancelled or
  superseded work cannot publish a stale success status.
- Added monitoring for failures after the connection becomes ready.
- Added a small lock-protected, single-use continuation gate so concurrent
  Network framework state callbacks cannot resume startup more than once.
- Capture is stopped if the receiver connection disappears while capture is
being initialized.

After a live run appeared stuck on `Creating virtual display`, a process stack
sample confirmed that CoreDisplay had created the virtual display and the app
was actually waiting for its network connection. The receiver was advertised
on multiple interfaces, but the host discarded Bonjour's interface-specific
endpoint and reconstructed an unscoped service endpoint. The host now:

- Stores the exact `NWEndpoint` returned by each Bonjour browse result.
- Uses that endpoint when opening the video connection, preserving its network
  interface scope.
- Displays `Connecting to <receiver>…` after virtual-display creation so the
  current startup stage is no longer mislabeled.

The host can therefore no longer claim to be streaming solely because screen
capture started while its receiver connection was pending or had already
failed.

### Receiver protocol hardening

Updated both receiver source copies:

- `apps/receiver/announce.py`
- `image/config/includes.chroot/opt/displayos/releases/0.1.0/announce.py`

The receiver now:

- Accepts the TCP connection and waits for a complete four-byte frame header.
- Validates the declared H.264 frame size.
- Reads the complete first frame before starting GStreamer or allocating
  DRM/KMS resources.
- Reports that it is waiting for the first frame, then reports that it is
  starting the video pipeline.
- Continues processing subsequent length-prefixed frames with the existing
size validation.

### Direct-Ethernet IPv6 listener fix

While the host was stuck on `Connecting to DisplayOS iMac…`, live Bonjour and
socket diagnostics established that:

- Bonjour advertised the receiver on interface `en8` at the IPv6 link-local
  address `fe80::6e5a:40d3:ceae:a905%en8`.
- The receiver's capabilities port 9876 was unreachable at that address.
- The advertised video port 9877 returned `connection refused`.
- `announce.py` created both servers as IPv4-only listeners (`AF_INET` and
  `0.0.0.0`), so it could not accept the IPv6 connection advertised by Avahi
  on a direct Ethernet link.

Both packaged copies of `announce.py` now:

- Create the video socket with `AF_INET6` and bind to `::`.
- Clear `IPV6_V6ONLY` so the Linux listener also accepts IPv4-mapped clients.
- Use a `DualStackHTTPServer` with the same behavior for the capabilities
  endpoint.

This keeps normal IPv4 support while allowing the receiver to work when a
direct Ethernet connection only resolves to an IPv6 link-local address.

As a result, port scanners, connectivity checks, and clients that disconnect
without sending the DisplayOS protocol no longer start and stop the playback
pipeline.

The two packaged receiver scripts were checked to ensure they remain
byte-for-byte identical.

### macOS app packaging fix

Updated `scripts/build-macos-app.sh`:

- Added `xattr -cr` before code signing the application bundle.

Finder metadata (`com.apple.FinderInfo`) had been attached to the generated
bundle and caused strict signature verification to fail. Clearing extended
attributes before signing produces a valid ad-hoc signed bundle.

### Streaming latency improvements

Live profiling of a working session found that the direct Ethernet adapter had
negotiated at `100baseTX` (100 Mbps), while the encoder was configured for 35
Mbps and allowed every captured frame to be queued without backpressure.

Updated `apps/host-macos/Sources/StreamingManager.swift`:

- Reduced the H.264 target bitrate from 35 Mbps to 18 Mbps, leaving more
  headroom on a 100 Mbps link for bursts and TCP overhead.
- Added a lock-protected frame gate permitting a bounded three-frame pipeline.
  A one-frame limit was tested and rejected because VideoToolbox can retain its
  initial input until subsequent frames arrive, deadlocking encoder startup.
- Frames are dropped before encoding while the previous frame is pending. This
  avoids an ever-growing TCP send queue while preserving H.264 prediction,
  because frames omitted before encoding never become codec references.
- The gate is released on encoding failure, packet-conversion failure, and send
  completion, and fully reset on stream shutdown.

Updated `image/config/package-lists/displayos.list.chroot`:

- Added `gstreamer1.0-vaapi` so Intel receivers can use VA-API hardware H.264
  decoding instead of relying on a CPU decoder selected by `decodebin`.

The frame-queue and bitrate changes are included in the rebuilt host app. The
VA-API package requires rebuilding and reflashing the receiver ISO.

### Verification performed

- Both receiver Python files passed `python3 -m py_compile`.
- Both receiver source copies were compared successfully with `cmp`.
- `git diff --check` reported no whitespace errors.
- The release macOS host executable compiled successfully with SwiftPM.
- The app was rebuilt at `dist/DisplayOS.app`.
- `codesign --verify --deep --strict` confirmed that the rebuilt app is valid
  on disk and satisfies its designated requirement.
- The rebuilt app was launched successfully from `dist/DisplayOS.app`.

### Deployment status and remaining work

The repaired host application is built and running locally. The receiver-side
change exists in the source tree and will be included in the next ISO, but it
has not yet been installed on the iMac.

The iMac boot USB was not attached to the host, so it could not be patched or
reflashed. An attempt to begin building a replacement ISO was cancelled before
completion. To finish deploying the fix:

1. Build a new image with `make image`.
2. Attach the receiver USB drive to the host.
3. Flash the newly built ISO to that drive.
4. Boot the iMac from the updated USB.
5. Connect using the rebuilt `dist/DisplayOS.app`.

If the updated receiver still closes the connection, collect the receiver
pipeline error with:

```sh
journalctl -u displayos-announce -n 100 --no-pager
```

The updated receiver UI and journal logging should then expose whether the
remaining fault is in H.264 parsing/decoding, DRM/KMS access, device selection,
or another GStreamer component.
