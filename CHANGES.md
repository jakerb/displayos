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
