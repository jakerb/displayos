# DisplayOS POC — Codex Build Specification

> **Purpose:** Build a proof of concept that turns an older Intel iMac into a low-latency secondary display for a Mac host, using a bootable Linux-based receiver and a native macOS host application.
>
> This document is intended to be dropped into Codex as the primary implementation brief. Codex should use it as the source of truth, work incrementally, commit completed milestones, and keep the roadmap updated as progress is made.

---

## Repository

**Repository URL:**  
git@github.com:jakerb/displayos.git

Codex may commit changes to this repository.

### Repository strategy

Use a **single monorepo** for the POC.

The host app, receiver, shared protocol, update tooling, ISO build tooling, documentation, and test utilities should live together so that protocol changes can be developed and versioned atomically.

Do not split into multiple repositories during the POC unless there is a very strong technical reason.

Suggested structure:

```text
displayos/
├── apps/
│   ├── host-macos/
│   └── receiver/
├── packages/
│   ├── protocol/
│   ├── discovery/
│   └── shared/
├── image/
│   ├── build/
│   ├── overlay/
│   ├── config/
│   └── scripts/
├── updater/
│   ├── manifest/
│   ├── signing/
│   └── scripts/
├── tools/
│   ├── diagnostics/
│   └── benchmarks/
├── docs/
│   ├── architecture.md
│   ├── protocol.md
│   ├── updates.md
│   ├── pairing.md
│   └── development.md
├── .github/
│   └── workflows/
├── README.md
└── ROADMAP.md
```

The receiver application must be runnable independently during development. Do not require rebuilding an ISO for every receiver code change.

---

# 1. Product concept

DisplayOS allows an older Intel iMac to be repurposed as an external display.

The iMac boots from a DisplayOS USB image and immediately becomes a display receiver rather than behaving like a normal Linux desktop.

The host Mac runs a native DisplayOS application that:

- discovers compatible DisplayOS receivers;
- creates or captures a display surface;
- hardware-encodes that surface;
- transmits it to the iMac;
- handles pairing and authentication;
- exposes quality and connection controls;
- manages receiver updates;
- later creates and flashes DisplayOS USB images.

The user experience should feel like using an appliance, not a Linux computer.

---

# 2. POC target

The first complete POC should demonstrate:

```text
Apple Silicon Mac
      │
      │ direct Gigabit Ethernet
      ▼
Intel iMac running DisplayOS
      │
      ▼
Full-screen secondary display
```

Initial target:

- macOS host;
- Intel iMac receiver;
- direct Ethernet;
- 2560 × 1440;
- 60 fps target;
- hardware video encoding on the host;
- hardware decoding on the receiver where supported;
- low enough latency that cursor movement and window dragging feel usable;
- stable connection for at least one hour.

The POC does **not** need to be App Store compliant.

If private macOS APIs are required to prove true virtual-display functionality, they may be used for the POC, but must be isolated behind an abstraction and clearly documented as a production risk.

---

# 3. Core design principles

## 3.1 Appliance-like receiver

The receiver should never expose a normal Ubuntu/Debian desktop during standard operation.

The normal boot flow should be:

```text
UEFI
↓
Linux boot
↓
DisplayOS services start
↓
Receiver UI launches full screen
↓
Waiting for connection
```

The user should see only DisplayOS branding and state information.

## 3.2 Transport abstraction

The streaming protocol must not be tightly coupled to Ethernet.

Create a transport interface so these can be added later:

1. direct Ethernet;
2. routed LAN;
3. Wi-Fi;
4. Thunderbolt networking;
5. other point-to-point IP transports.

The codec, session, pairing, discovery, and frame protocol should remain independent of the underlying transport.

## 3.3 Host controls streaming

Streaming configuration should primarily live in the host application.

The receiver advertises capabilities such as:

- native resolution;
- supported decode codecs;
- maximum tested decode resolution;
- maximum tested frame rate;
- GPU;
- available hardware decoder;
- network interface;
- link speed;
- receiver version.

The host chooses the stream configuration.

The receiver UI should remain deliberately minimal.

## 3.4 Auto mode first

The host should default to an **Auto** quality mode.

Advanced overrides may expose:

- resolution;
- refresh rate;
- bitrate;
- codec;
- encoder mode;
- latency mode.

Auto mode should choose the best stable configuration based on receiver capability and link speed.

---

# 4. Deliverable A — DisplayOS Receiver

Build a Linux receiver application that can run on an Intel iMac.

For the earliest development stage it may run inside a normal Ubuntu/Debian install.

Once the streaming path is working, package it into a custom bootable image.

## 4.1 Receiver responsibilities

The receiver must:

- start automatically;
- discover available network interfaces;
- obtain an address automatically;
- support direct Ethernet using DHCP or link-local fallback;
- optionally connect to pre-provisioned Wi-Fi;
- advertise itself to the host;
- accept a secure host connection;
- receive the video stream;
- decode it;
- render it full screen;
- expose receiver capabilities;
- detect connection loss;
- automatically return to the waiting screen;
- support reconnection;
- expose version/build information;
- support remote update checks and update installation.

## 4.2 Receiver UI states

Implement a clean full-screen UI with no visible Linux chrome.

Minimum states:

### Waiting

Show:

```text
DisplayOS

Waiting for a connection

Wi-Fi: Connected to <SSID>
Ethernet: Connected / Disconnected

Wireless / shared network pairing code:
AB12-CD34

For a direct connection, connect the cable to your Mac.
```

The pairing code should only be relevant for shared network connections.

### Connecting

```text
Connecting to <Host Name>…
Securing connection…
```

### Connected

Keep UI overlays minimal.

Optionally show a temporary toast:

```text
Connected to Jake’s MacBook Pro
2560 × 1440 @ 60 Hz
Ethernet
```

Then fade the status away.

### Disconnected

```text
Connection lost
Waiting for host…
```

Auto-reconnect where possible.

### Updating

```text
Updating DisplayOS
Do not power off
```

---

# 5. Deliverable B — DisplayOS for macOS

Build a native macOS host application.

Suggested stack:

- Swift;
- SwiftUI for UI;
- VideoToolbox for hardware encoding;
- Network.framework for transport where appropriate;
- Bonjour / mDNS for discovery;
- Keychain for persisted pairing credentials.

Do not over-engineer the UI during the POC.

## 5.1 Host responsibilities

The app must:

- detect DisplayOS receivers;
- show available receivers;
- pair securely;
- establish a stream;
- create or select the source display;
- encode with low latency;
- transmit frames;
- show current connection state;
- show quality metrics;
- expose Auto and Advanced quality controls;
- stop/restart sessions;
- manage receiver software updates;
- eventually create and flash receiver USB images.

## 5.2 Host UI

Suggested top-level layout:

```text
DisplayOS

Available Displays
────────────────────────────────

Office iMac
Connected via Ethernet
2560 × 1440 @ 60 Hz
[Disconnect]

Bedroom iMac
Available on Wi-Fi
[Connect]

────────────────────────────────

Quality
● Auto

Advanced ▸

Receiver
Version 0.1.3
[Check for update]
```

---

# 6. Virtual display strategy

A true secondary display on macOS is one of the highest-risk technical areas.

The end goal is:

> The DisplayOS receiver appears to macOS as a normal additional display so that macOS handles arrangement, cursor transition, window placement, Spaces, scaling, and display positioning.

Do not build a custom cursor-sharing system.

macOS should remain responsible for:

- monitor arrangement;
- cursor crossing;
- drag-between-displays behavior;
- window positioning;
- resolution selection where possible.

## 6.1 POC implementation order

### Stage 1 — Prove streaming first

Before tackling true virtual display creation, allow the host to stream:

- an existing physical display;
- a chosen app/window; or
- a test rendering surface.

This proves:

- capture;
- encode;
- transport;
- decode;
- render;
- latency.

### Stage 2 — Add true virtual display

Research and implement the best feasible macOS virtual-display method.

Public APIs are preferred.

If private APIs are required for the POC:

- isolate them inside a dedicated module;
- document every private dependency;
- add a production-risk note;
- do not let the rest of the app depend directly on them.

The virtual display layer should expose a stable internal interface such as:

```text
VirtualDisplayManager
├── createDisplay(...)
├── destroyDisplay(...)
├── setMode(...)
├── enumerateDisplays()
└── captureSurface(...)
```

---

# 7. Streaming pipeline

Target architecture:

```text
Virtual / captured display
        │
        ▼
macOS frame capture
        │
        ▼
VideoToolbox low-latency encoder
        │
        ▼
DisplayOS stream protocol
        │
        ▼
Ethernet / LAN / Wi-Fi / Thunderbolt-IP
        │
        ▼
Receiver transport
        │
        ▼
Hardware decoder
        │
        ▼
Full-screen renderer
```

## 7.1 Codec

For the POC:

1. test H.264 first for compatibility and low-latency simplicity;
2. add HEVC where supported;
3. prefer hardware encoding and hardware decoding;
4. avoid B-frames;
5. minimize buffering;
6. use short GOP/keyframe intervals;
7. tune for interactive latency rather than broadcast quality.

The protocol should be codec-agnostic.

## 7.2 Metrics

Collect and expose:

- capture fps;
- encode time;
- network send time;
- receiver queue depth;
- decode time;
- render time;
- dropped frames;
- current bitrate;
- packet loss if applicable;
- end-to-end latency estimate;
- negotiated resolution;
- negotiated fps;
- link speed.

Create a diagnostics mode that can be enabled without changing normal UI behavior.

---

# 8. Network modes

## 8.1 Direct Ethernet — POC priority

Support:

```text
Host Mac ←→ Ethernet cable ←→ iMac
```

No router should be required.

Use:

- DHCP if one side can provide it; otherwise
- IPv4 link-local / self-assigned addressing.

Discovery must work automatically.

The ideal user flow is:

```text
1. Boot iMac into DisplayOS
2. Plug Ethernet cable between devices
3. Open DisplayOS host app
4. iMac appears automatically
5. Click Connect
```

## 8.2 Routed LAN

Support later in the POC if straightforward.

Both machines may be connected to the same switch/router.

Require pairing because other hosts may exist on the same network.

## 8.3 Wi-Fi

Wi-Fi is optional.

During image creation the user may pre-provision:

- SSID;
- password;
- device name.

Wi-Fi may be used for either:

1. wireless display transport; and/or
2. automatic DisplayOS updates.

The setup wizard should explain this clearly:

> **Wi-Fi is optional. Use it for wireless display connections and automatic DisplayOS updates.**

Provide a clear **Skip Wi-Fi** option.

Wi-Fi must never be required solely because the display is using a wired transport.

---

# 9. Pairing and security

The receiver should not accept arbitrary connections from any device on an office or shared network.

## 9.1 Shared network pairing

On first boot, generate a short human-readable pairing code.

Suggested format:

```text
AB12-CD34
```

The short code is **not** the long-term secret.

Use it only to bootstrap trust.

After pairing:

- generate/exchange long-lived cryptographic keys;
- persist trusted host identity;
- store host credentials securely;
- do not require the pairing code for every reconnect.

## 9.2 Direct physical connection

For direct Ethernet or future Thunderbolt point-to-point transport, the POC may automatically establish trust.

However:

- still use encrypted transport;
- still exchange persistent device identities;
- log which host is trusted.

The user should not need to type a code merely because they physically connected a dedicated cable.

## 9.3 Host identity

Receiver UI may show:

```text
Connected to Jake’s MacBook Pro
```

Allow multiple trusted hosts later.

---

# 10. USB image creation

The final host application should eventually include an imager similar in spirit to Raspberry Pi Imager.

For the POC this can initially be a separate script or utility, but the architecture should assume it becomes part of the host app.

Wizard:

```text
Create DisplayOS USB

1. Select target USB device
2. Device name
3. Configure Wi-Fi?  [Yes / Skip]
4. If yes:
   - SSID
   - Password
5. Generate receiver identity
6. Generate pairing seed / credentials
7. Write image
8. Verify image
9. Eject
```

The wizard must warn clearly before erasing the selected USB device.

Never hard-code user Wi-Fi credentials into the repository.

Provisioned credentials must live only in the generated image/config partition.

---

# 11. Receiver update system — POC requirement

The receiver must be updatable without requiring the user to recreate the USB stick.

This is part of the POC, not merely a future roadmap item.

## 11.1 Update goals

Codex should implement an update mechanism that supports:

- checking for receiver updates;
- downloading them;
- verifying integrity/authenticity;
- installing them;
- rebooting into the new version where necessary;
- reporting update status to the host;
- keeping the installed receiver usable if an update fails.

## 11.2 GitHub-backed update channel

Use GitHub Releases as the initial release distribution mechanism.

Repository URL is defined at the top of this file.

Suggested release assets:

```text
displayos-receiver-0.1.0.tar.zst
displayos-receiver-0.1.0.sha256
manifest.json
manifest.sig
```

Possible later assets:

```text
displayos-image-0.1.0.img.zst
displayos-image-0.1.0.sha256
```

Suggested manifest:

```json
{
  "channel": "poc",
  "version": "0.1.0",
  "minimum_host_version": "0.1.0",
  "receiver": {
    "url": "<release asset URL>",
    "sha256": "<hash>",
    "size": 12345678
  }
}
```

Do not trust an unsigned manifest in production architecture.

For the POC, implement signing if reasonably achievable.

At minimum:

- HTTPS;
- SHA-256 validation;
- release version validation.

Preferred:

- Ed25519 signed manifest;
- embedded public verification key in the receiver;
- signing private key stored only in CI secrets.

## 11.3 Update architecture

For the POC, prefer **application-level receiver updates** first rather than replacing the entire OS image on every release.

Recommended layout:

```text
/opt/displayos/releases/
├── 0.1.0/
├── 0.1.1/
└── current -> 0.1.1
```

Update flow:

```text
Check manifest
↓
Download release to staging
↓
Verify SHA/signature
↓
Extract into versioned release directory
↓
Run self-test
↓
Atomically switch "current" symlink
↓
Restart receiver service
↓
Confirm health
↓
Rollback automatically if unhealthy
```

This gives the POC fast receiver updates without reflashing.

OS/kernel updates can come later.

## 11.4 Host-orchestrated updates

The macOS host app should be able to:

- query receiver version;
- compare against latest release;
- show update availability;
- tell the receiver to update;
- display progress;
- reconnect after update.

Suggested flow:

```text
Receiver 0.1.2
Update 0.1.3 available

[Update now]
```

Then:

```text
Downloading…
Verifying…
Installing…
Restarting receiver…
Reconnecting…
Updated to 0.1.3
```

## 11.5 Updates when receiver has no Internet

Wi-Fi must not be mandatory.

If the receiver is using direct Ethernet or another private physical connection and cannot reach GitHub:

1. host app downloads the release;
2. host verifies it;
3. host transfers the update to the receiver over the existing DisplayOS connection;
4. receiver verifies it again;
5. receiver installs it.

Support both:

```text
Receiver → Internet → GitHub
```

and:

```text
Receiver ← Host Mac ← Internet → GitHub
```

The host-proxy method is important and should be part of the update architecture from the start.

---

# 12. ISO / image build strategy

Do not fork an entire Linux distribution unless necessary.

Start with a reproducible Debian/Ubuntu live-image build.

The build should:

- install only required packages;
- install the receiver;
- install graphics/network drivers;
- enable auto-login or direct service launch as appropriate;
- start DisplayOS automatically;
- disable desktop/session UI not needed;
- disable sleep/screensaver while connected;
- display a clean Plymouth/boot experience if practical;
- mount the base system read-only where practical;
- persist only configuration, keys, logs, and installed receiver releases.

Image creation must be reproducible from the repository.

Provide a single documented build command, for example:

```bash
make image
```

or:

```bash
./image/build/build.sh
```

---

# 13. Receiver persistence

Even when booting from USB, persist:

- device ID;
- trusted hosts;
- Wi-Fi settings;
- receiver configuration;
- last known good receiver version;
- update state;
- diagnostic logs.

Avoid persisting unnecessary user data.

The receiver is a display appliance, not a general-purpose workstation.

---

# 14. Development workflow

Codex should work in small, testable milestones.

For each milestone:

1. implement;
2. run relevant tests;
3. update documentation;
4. update ROADMAP.md;
5. commit changes;
6. use a clear conventional commit message.

Example:

```text
feat(receiver): add mDNS discovery and capability advertisement
```

Avoid large, opaque commits.

---

# 15. POC milestones

## Milestone 0 — Repository/bootstrap

Build:

- monorepo structure;
- README;
- architecture documentation;
- build scripts;
- host skeleton;
- receiver skeleton;
- common protocol package;
- GitHub Actions baseline;
- versioning strategy.

Acceptance:

- host app builds;
- receiver builds on Linux;
- protocol package tests run;
- CI runs successfully.

---

## Milestone 1 — Receiver discovery

Build:

- receiver identity;
- capability advertisement;
- Bonjour/mDNS discovery;
- host discovery UI;
- connection handshake.

Acceptance:

- boot receiver;
- open host app;
- receiver appears automatically;
- host can display receiver name/version/capabilities.

---

## Milestone 2 — Basic video path

Build:

- host screen/window capture;
- H.264 hardware encode;
- network stream;
- receiver decode;
- full-screen presentation.

Start with an existing host display or test surface.

Acceptance:

- receiver shows live host content;
- video runs continuously;
- basic reconnect works.

---

## Milestone 3 — Low-latency direct Ethernet

Build:

- direct cable support;
- link-local fallback;
- low-latency encoder tuning;
- receiver queue tuning;
- frame timing metrics;
- packet/transport metrics.

Acceptance:

- no router required;
- 2560 × 1440 target;
- 60 fps target;
- cursor/window motion visibly responsive;
- stable 60-minute session.

---

## Milestone 4 — Pairing/security

Build:

- 8-character pairing code;
- shared-network secure pairing;
- persistent trusted-host keys;
- encrypted authenticated sessions;
- automatic direct-link pairing policy.

Acceptance:

- random machine on LAN cannot display content without pairing;
- previously paired host reconnects without entering code;
- direct cable path remains low-friction.

---

## Milestone 5 — Receiver self-update

Build:

- receiver version endpoint;
- GitHub Release manifest;
- release downloader;
- integrity verification;
- versioned install directories;
- atomic activation;
- health check;
- rollback;
- host UI update trigger;
- host-proxy update transfer.

Acceptance:

- install receiver 0.1.0;
- publish 0.1.1;
- update receiver without reflashing USB;
- simulate bad update;
- receiver rolls back automatically.

---

## Milestone 6 — Bootable DisplayOS image

Build:

- reproducible bootable image;
- DisplayOS branding;
- no visible Linux desktop;
- auto-start receiver;
- persistent config partition/state;
- USB-flash instructions.

Acceptance:

- image fresh USB;
- boot Intel iMac;
- user sees DisplayOS waiting screen;
- no Linux setup wizard;
- receiver is discoverable.

---

## Milestone 7 — Wi-Fi provisioning

Build:

- image configuration template;
- optional SSID/password provisioning;
- Wi-Fi status on receiver;
- setup UI copy explaining Wi-Fi uses;
- Skip Wi-Fi support.

Required wording/theme:

> Wi-Fi is optional. Use it for wireless display connections and automatic DisplayOS updates.

Acceptance:

- pre-provisioned image connects automatically;
- skipped image still works over direct Ethernet;
- receiver can update via Wi-Fi when wired display transport is being used.

---

## Milestone 8 — True macOS virtual display

Build:

- virtual display abstraction;
- research public API route;
- POC fallback using isolated private API if required;
- capture virtual display;
- macOS normal display arrangement.

Acceptance:

- DisplayOS appears as an additional display;
- user arranges it in macOS Displays;
- cursor crosses between monitors normally;
- windows can be dragged onto receiver.

This is a major POC milestone and may require technical investigation.

---

# 16. Definition of POC complete

The POC is complete when:

- Intel iMac boots from DisplayOS USB;
- no normal Linux desktop is exposed;
- Apple Silicon Mac discovers it;
- direct Ethernet works without router configuration;
- secure connection establishes;
- host can use it as an additional display or the closest technically viable POC implementation;
- 2560 × 1440 @ 60 Hz is usable;
- connection remains stable for one hour;
- receiver can update without USB reflashing;
- Wi-Fi can be preconfigured optionally;
- host can orchestrate receiver updates;
- documentation explains all known macOS virtual display limitations.

---

# 17. Performance targets

These are targets rather than hard blockers during early stages.

## Initial POC

- Resolution: 2560 × 1440
- Refresh: 60 Hz
- Transport: direct Gigabit Ethernet
- Codec: H.264 low-latency
- Hardware encode: required where supported
- Hardware decode: strongly preferred
- End-to-end latency: aim for < 50 ms, then optimize toward < 30 ms
- Stability: 60 minutes continuous
- Frame drops: negligible during normal desktop use

Add a benchmark tool to measure the pipeline.

Do not hide poor latency behind buffering.

---

# 18. Error handling

Handle gracefully:

- cable unplugged;
- host sleeps;
- receiver sleeps unexpectedly;
- network interface changes;
- corrupted frame;
- decoder restart;
- host application crash;
- receiver application crash;
- failed update;
- partial update download;
- GitHub unavailable;
- Wi-Fi unavailable;
- receiver has no Internet;
- incompatible receiver version;
- incompatible host version.

The receiver should return to a known-good waiting state whenever possible.

---

# 19. Logging

Use structured logs.

Do not log:

- Wi-Fi passwords;
- pairing secrets;
- private keys;
- raw video frames.

Include:

- version;
- device ID;
- transport;
- connection state;
- stream mode;
- encode/decode performance;
- update state;
- errors.

Logs should be accessible from the host app in a later roadmap item.

---

# 20. Testing

Create automated tests where practical for:

- protocol serialization;
- pairing flow;
- version negotiation;
- update manifest parsing;
- signature/hash verification;
- rollback logic;
- configuration parsing;
- capability negotiation.

Create integration test utilities for:

- simulated receiver;
- packet delay;
- packet loss;
- bandwidth throttling;
- disconnect/reconnect;
- update failure.

---

# 21. CI/CD

Use GitHub Actions.

At minimum:

- build macOS host;
- build Linux receiver;
- run unit tests;
- lint;
- package receiver release artifact;
- generate checksums.

Later:

- signed release manifest;
- ISO/image build;
- release creation;
- nightly builds.

Use repository secrets for signing keys.

Never commit signing private keys.

---

# 22. Versioning

Use semantic versioning initially.

Example:

```text
Host:     0.1.0
Receiver: 0.1.0
Protocol: 1
```

Protocol version must be negotiated separately from app version.

Allow a compatibility matrix such as:

```text
Host 0.2.x supports protocol 1–2
Receiver 0.1.x supports protocol 1
```

---

# 23. ROADMAP — prioritized

Codex should work on roadmap items in the following order after the core POC.

## Priority 0 — Core POC blockers

These must be completed before expanding scope.

1. Reliable direct-Ethernet discovery
2. Video encode / transport / decode pipeline
3. 1440p60 latency optimization
4. Secure pairing
5. Receiver application self-update
6. Host-proxy receiver updates
7. Bootable DisplayOS image
8. Optional Wi-Fi provisioning
9. True virtual-display feasibility and implementation

---

## Priority 1 — Make it feel like a monitor

After the POC works:

1. automatic stream-quality negotiation;
2. HEVC support;
3. Retina / HiDPI scaling;
4. native iMac resolution modes;
5. improved color management;
6. EDID-like capability reporting;
7. sleep/wake integration;
8. reconnect after host wake;
9. polished macOS display lifecycle;
10. host-controlled receiver blanking.

---

## Priority 2 — Thunderbolt transport

Add Thunderbolt networking as a high-performance transport.

Goal:

```text
Mac ← Thunderbolt → iMac
```

Explore IP over Thunderbolt first.

Requirements:

- transport plugs into the existing stream layer;
- discovery behaves like Ethernet;
- latency/throughput benchmarked against Gigabit Ethernet;
- auto-select fastest viable transport;
- fall back cleanly.

Do not rewrite the streaming protocol specifically for Thunderbolt.

---

## Priority 3 — 4K / 5K optimization

Once Thunderbolt or another sufficiently fast transport exists:

1. 4K60;
2. 5K30;
3. 5K60 where hardware permits;
4. HEVC tuning;
5. 10-bit color investigation;
6. receiver GPU-specific optimization;
7. frame pacing;
8. scaling quality.

Build a compatibility database by iMac model.

---

## Priority 4 — Host USB image creator

Move image generation/flashing into the macOS app.

Features:

- download latest image;
- select USB;
- optional Wi-Fi;
- device name;
- pre-generated identity;
- progress;
- verify;
- eject;
- clear destructive-action warning.

The host app should feel like Raspberry Pi Imager but specific to DisplayOS.

---

## Priority 5 — OTA system image updates

Application-level receiver updates come first.

Later add full operating-system A/B updates.

Possible architecture:

```text
EFI
├── root-A
├── root-B
└── persistent-data
```

Update inactive root partition, validate, boot it, and roll back automatically if health checks fail.

Do not implement this before application-level updating is stable.

---

## Priority 6 — Audio

Expose iMac speakers as an audio destination.

Requirements:

- synchronized audio/video;
- host audio device routing;
- mute/volume control;
- latency handling.

---

## Priority 7 — Brightness and display control

Investigate control of:

- panel brightness;
- screen blanking;
- sleep;
- wake;
- backlight;
- possibly ambient light behavior.

Hardware support will vary by iMac generation.

---

## Priority 8 — Multiple receivers

Allow a single host Mac to connect to multiple DisplayOS iMacs.

Example:

```text
MacBook Pro
├── iMac Left
└── iMac Right
```

Requirements:

- separate virtual displays;
- independent quality;
- independent transport;
- bandwidth awareness;
- independent reconnect.

---

## Priority 9 — Receiver management

Add a management panel:

- rename receiver;
- trusted hosts;
- forget host;
- network details;
- current version;
- update channel;
- diagnostics;
- reboot;
- shutdown.

Keep it remote-first.

Avoid requiring a keyboard attached to the iMac.

---

## Priority 10 — USB peripheral forwarding

Investigate forwarding:

- keyboard;
- mouse;
- webcam;
- microphone;
- USB storage only if there is a compelling reason.

This is not required for the display use case and should remain low priority.

---

## Priority 11 — Additional host platforms

Only after Mac-to-Mac is solid:

1. Windows host;
2. Linux host.

Do not let cross-platform abstractions slow the initial macOS POC unnecessarily.

---

## Priority 12 — Broader hardware support

Investigate non-iMac receivers after the primary use case is stable.

Possible examples:

- old Mac mini + monitor;
- old MacBook;
- generic x86 PC;
- mini PC;
- single-board computer with suitable decode hardware.

---

# 24. Explicit non-goals for the first POC

Do **not** spend POC time on:

- Windows host support;
- Linux host support;
- App Store distribution;
- cloud accounts;
- user subscriptions;
- remote Internet streaming;
- collaboration features;
- USB peripheral forwarding;
- audio before video is stable;
- complex settings UI;
- visual themes;
- full distro fork;
- perfect 5K support;
- multi-receiver support.

The goal is to prove that an old iMac can become a genuinely usable Mac secondary display.

---

# 25. Codex operating instructions

When working from this document:

1. Read the entire specification before changing code.
2. Inspect the existing repository before choosing an implementation.
3. Do not rewrite working components unnecessarily.
4. Work through milestones in order unless blocked.
5. If blocked, document the blocker and move only to work that does not invalidate the dependency order.
6. Keep architecture modular.
7. Keep transport independent from codec/session logic.
8. Keep macOS virtual-display implementation isolated.
9. Keep receiver image building separate from normal receiver development.
10. Implement receiver self-update early enough that repeated USB flashing is not part of the development loop.
11. Prefer measurable latency data over subjective claims.
12. Add diagnostics as the streaming path is built, not afterwards.
13. Update `ROADMAP.md` after each milestone.
14. Commit each meaningful completed milestone.
15. Never commit credentials, Wi-Fi passwords, private signing keys, or provisioning secrets.

---

# 26. First task for Codex

Start with **Milestone 0**.

Create the repository structure, architecture docs, build skeletons, shared protocol definitions, CI baseline, and a minimal discovery plan.

Then proceed to **Milestone 1 — Receiver discovery**.

Do not begin custom ISO/image work until the receiver can run as a normal Linux application and the Mac host can discover it.

The first useful demonstration should be:

```text
Linux receiver running on Intel iMac
        ↓
Host macOS app discovers receiver
        ↓
Host shows receiver identity and capabilities
```

Then begin the video path.

---

# 27. Product vision beyond POC

The desired end-state should feel like this:

```text
1. Download DisplayOS for Mac
2. Click "Create DisplayOS USB"
3. Select USB
4. Optionally configure Wi-Fi
5. Boot old iMac from USB
6. Open DisplayOS on the host Mac
7. iMac appears automatically
8. Click Connect
9. Arrange it in macOS Displays
10. Use it like a normal monitor
```

For a direct cable connection, the ideal experience becomes:

```text
Boot iMac
Plug cable in
Display connects
```

The technology underneath may be Linux, video encoding, IP networking, discovery, pairing, and update orchestration.

The product experience should hide all of that.

**It should feel like a monitor.**
