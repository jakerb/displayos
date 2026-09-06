# DisplayOS POC

DisplayOS turns a supported Intel iMac into a low-latency network display for a Mac.

## What is ready now

- `apps/host-macos` — native SwiftUI host application. It discovers receiver advertisements, lets you manage a session placeholder, and provides a guarded USB-image workflow.
- `image/build/build.sh` — reproducible Debian Bookworm live ISO builder for Intel (`amd64`) Macs. The image boots directly into the DisplayOS receiver service with no desktop session.
- `apps/receiver` — fullscreen receiver placeholder, systemd service, and capability endpoint used by the ISO.

## Build the Mac application

```bash
make macos-app
open dist/DisplayOS.app
```

The result is ad-hoc signed for local testing. Gatekeeper may require right-click → Open the first time.

## Build the Intel iMac ISO

Docker Desktop must be running and have internet access the first time.

```bash
make image
```

The ISO is written to `image/out/displayos-poc-amd64.iso`. It is for Intel Macs only, not Apple Silicon.

## Flash and boot

Use the macOS app’s **Create bootable USB** tab, or flash with a tool such as balenaEtcher. This destroys the selected USB drive. On the iMac, insert the USB stick and hold **Option (⌥)** while booting, then choose EFI Boot.

This first build establishes the appliance boot path, discovery UI, and imaging workflow. The H.264 streaming/virtual-display pipeline remains the next implementation milestone and is deliberately labelled in the app.
