# Building and testing

`make macos-app` creates `dist/DisplayOS.app` for the current Mac. It is ad-hoc signed, suitable for local use only.

`make image` runs Debian live-build inside an `amd64` Docker container and produces `image/out/displayos-poc-amd64.iso` plus a SHA-256 file. Docker Desktop must be running. The image is UEFI bootable and intended for an Intel iMac.

To test: flash the ISO to USB, boot the iMac holding Option, choose **EFI Boot**, connect Ethernet, and open DisplayOS. The host discovers `_displayos._tcp` receivers (stream port 9877) and the receiver exposes `/capabilities` on port 9876.

The POC image currently provides the appliance boot UI and receiver discovery. End-to-end capture, H.264 transmission/decoding, secure pairing, persistence, and update delivery are not yet implemented; do not use it for sensitive content.
