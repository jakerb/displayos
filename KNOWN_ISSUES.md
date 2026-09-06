# Known issues

## Receiver remains on “Waiting for a connection” after the host connects

**Status:** Open  
**Area:** Receiver UI / video rendering  
**Observed:** 2026-09-06

The fullscreen `receiver-ui` process redraws tty1 every three seconds without
knowing whether the video server has accepted a client. As a result, the iMac
continues to show “Waiting for a connection” after the macOS app connects. Its
console output may also compete with GStreamer's KMS output.

### Required fix

- Share connection state between `announce.py` and `receiver-ui`.
- Stop repainting or hide the waiting UI while a stream is active.
- Restore the waiting UI when the stream ends.
- Show a distinct connecting, streaming, and failed state.

### Acceptance criteria

- The waiting message disappears when port 9877 accepts a host connection.
- Video output is not overwritten by tty1.
- Disconnecting returns the receiver to the waiting screen.
- A connection that fails before video playback displays an actionable error.

## Receiver video-pipeline failures are silent

**Status:** Open  
**Area:** Receiver diagnostics / GStreamer  
**Observed:** 2026-09-06

`announce.py` launches `gst-launch-1.0` with quiet output and does not monitor
or report its exit status. Decoder, parser, DRM/KMS, and device-permission
failures therefore leave the user on the unchanged waiting screen with no
indication of what failed.

### Required fix

- Capture and persist GStreamer stderr in the system journal.
- Monitor early process exit and expose a useful error to the receiver UI.
- Log client connection and disconnection events, pipeline startup, and the
  selected decoder and render sink.
- Handle player shutdown without allowing `wait(timeout=3)` to terminate the
  receiver server when GStreamer does not exit promptly.

### Acceptance criteria

- `journalctl -u displayos-announce` explains why playback did not start.
- The receiver UI distinguishes network connection from successful playback.
- A failed pipeline is cleaned up and the server accepts a subsequent client.

