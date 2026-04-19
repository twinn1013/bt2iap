# bt2iap

[한국어](README.md) · *English*

Bluetooth-to-iAP bridge: streams phone audio via A2DP through a Raspberry Pi Zero 2 W that impersonates an iPod over USB into a 2007-2012 Mitsubishi Outlander MMCS head unit.

## Architecture

```
[Phone] --BT A2DP--> [Pi Zero 2 W] --USB iAP--> [Outlander USB-A]
                                                         |
                                        MMCS recognizes as iPod
```

The Pi presents itself as an Apple iPod using the `ipod-gadget` kernel module over USB gadget mode (`dwc2`). Audio is received via Bluetooth A2DP (BlueALSA), routed through an ALSA loopback, and fed into the `iPodUSB` ALSA card exposed by `g_ipod_audio.ko`.

## Status

All four tiers (T1 gadget boot, T2 audio path, T3 iAP deep recovery runbook, T4 extension research) complete. Awaiting Pi Zero 2 W hardware.

## Hardware

- **Pi:** Raspberry Pi Zero 2 W, Raspberry Pi OS Lite 64-bit, headless (Wi-Fi + SSH configured via Imager)
- **Car:** Mitsubishi Outlander 2007-2012, MMCS head unit, USB-A port (iPod-only, iAP protocol)
- **Power note:** Car USB-A is under 1A. Use a 2A+ cigarette-lighter USB charger for Pi power; connect only the data line from the head unit.

## Repository layout

```
bt2iap/
|-- scripts/       # Pi-side automation (bootstrap, gadget load, product_id loop,
|                  #   audio bridge, verify-audio, collect-diagnostics)
|-- systemd/       # Unit files installed to /etc/systemd/system/ (+ drop-in overrides)
|-- boot/          # Patches for /boot/config.txt and /boot/cmdline.txt
|-- bluetooth/     # BlueZ config patch and pairing agent script
|-- alsa/          # ALSA routing config (A2DP sink -> loopback -> iPodUSB)
|-- docs/          # Research notes, verification checklists, audio topology diagram,
|                  #   triage matrix (triage.md), iAP auth deep-dive (iap-auth-deep-dive.md),
|                  #   iAP message protocol reference (iap-messages.md),
|                  #   advanced debugging tools catalog (advanced-iap-tools.md)
|-- Makefile       # Mac-side quality gates (check-t1, check-t2, check-t3, check-t4)
`-- CLAUDE.md      # Project context for AI assistants
```

## T1 install (on Pi)

```bash
# 1. Clone this repo to /opt/bt2iap on the Pi
sudo git clone https://github.com/twinn1013/bt2iap /opt/bt2iap
cd /opt/bt2iap

# 2. Run bootstrap (installs deps, builds modules, enables services)
sudo ./scripts/bootstrap.sh

# 3. Reboot
sudo reboot

# 4. After reboot, verify
sudo ./scripts/load-gadget.sh                           # T1 gadget load (manual sanity)
systemctl is-active ipod-gadget.service ipod-session.service
```

The bootstrap script handles: `apt` dependencies (`build-essential`, `raspberrypi-kernel-headers`, `golang`, `bluez`, `bluez-tools`, `bluealsa`), cloning and building `oandrew/ipod-gadget`, building the `oandrew/ipod` Go client, installing **both** the `ipod-gadget` kernel-loader unit and the `ipod-session` userspace iAP handler unit (the Go client is what actually activates the iAP session by opening `/dev/iap0`), and enabling them via `systemctl enable --now`.

Boot patches (`boot/config.txt.patch`, `boot/cmdline.txt.patch`) must be applied before reboot to enable `dwc2` gadget mode:

- `dtoverlay=dwc2` in `/boot/firmware/config.txt` (Bookworm; pre-Bookworm uses `/boot/config.txt`)
- `modules-load=dwc2` appended after `rootwait` in `/boot/firmware/cmdline.txt` (Bookworm; pre-Bookworm uses `/boot/cmdline.txt`)

`bootstrap.sh` auto-detects whether the boot directory is `/boot/firmware/` (Bookworm, current Pi OS) or `/boot/` (Bullseye and older) and patches whichever pair exists, failing loudly if neither is present.

### Persisting a working PRODUCT_ID

If `scripts/product-id-loop.sh` finds a `product_id` that the Outlander head unit accepts, persist it across reboots by writing it into `/etc/default/bt2iap`:

```bash
# Example after the loop lands on 0x1261:
sudo sed -i 's/^#\?PRODUCT_ID=.*/PRODUCT_ID=0x1261/' /etc/default/bt2iap
sudo systemctl restart ipod-gadget.service
```

`systemd/ipod-gadget.service` reads this file via `EnvironmentFile=-/etc/default/bt2iap` (the `-` prefix makes it optional — if the file is absent, the module's built-in default `product_id` is used).

## T1 verify

See `docs/verification-t1.md` for the full checklist. Quick inline checks:

```bash
# 1. Confirm /dev/iap0 was created
dmesg | grep iap

# 2. Confirm kernel modules loaded
lsmod | grep ipod

# 3. Confirm ALSA card is present
aplay -l | grep iPodUSB
```

When the Pi is tethered to a PC (not the car), it should enumerate as "Apple iPod" in the host's USB device list.

## T2 install (on Pi)

`scripts/bootstrap.sh` now handles T2 installation end-to-end. A second run after T1 is unnecessary — the same `sudo ./scripts/bootstrap.sh` invocation also installs the T2 artifacts (BlueZ patch, BlueALSA override, `asound.conf`, `audio-bridge`/`audio-loopback`/`pair-agent`/`ipod-session` services, `modules-load.d/bt2iap.conf`), reloads systemd, and enables every service `--now`.

Post-install, verify the audio chain:

```bash
sudo /opt/bt2iap/scripts/verify-audio.sh
```

Manual copy reference (for inspection / partial redeployment only — bootstrap handles all of this automatically):

```bash
# BlueZ config patch (idempotent: only appends if sentinel absent).
# Use the pure-INI payload, NOT the Markdown .patch documentation file.
sudo bash -c '
  block=bluetooth/main.conf.patch.block
  target=/etc/bluetooth/main.conf
  if ! grep -qF "# --- begin bt2iap ---" "$target"; then
    cat "$block" >> "$target"
  fi
'

# BlueALSA service drop-in
sudo install -D -m 0644 systemd/bluealsa.service.d/override.conf \
        /etc/systemd/system/bluealsa.service.d/override.conf

# ALSA routing config
sudo install -D -m 0644 alsa/asound.conf /etc/asound.conf

# modules-load.d for snd-aloop + libcomposite
sudo install -D -m 0644 modules-load.d/bt2iap.conf /etc/modules-load.d/bt2iap.conf

# T2 systemd units (audio-bridge = 1st leg, audio-loopback = 2nd leg)
sudo install -m 0644 systemd/audio-bridge.service /etc/systemd/system/audio-bridge.service
sudo install -m 0644 systemd/audio-loopback.service /etc/systemd/system/audio-loopback.service
sudo install -m 0644 systemd/pair-agent.service /etc/systemd/system/pair-agent.service
sudo install -m 0644 systemd/ipod-session.service /etc/systemd/system/ipod-session.service

sudo systemctl daemon-reload
sudo systemctl enable --now bluealsa.service audio-bridge.service \
    audio-loopback.service pair-agent.service ipod-session.service
```

**Why the second bridge (`audio-loopback.service`) matters:** `asound.conf` wires `default` PCM → `aloop_playback` (loopback write side). Without `alsaloop` reading the capture side and writing to `iPodUSB`, audio literally dead-ends inside the kernel loopback buffer. Prior reviews flagged this as C1 (critical). The unit orders itself via `Requires=audio-bridge.service` + `After=audio-bridge.service`.

## T2 verify

See `docs/audio-topology.md` for the full signal-path diagram:

```
Phone --BT A2DP--> BlueALSA --> ALSA loopback (snd-aloop) --> g_ipod_audio --> USB (iPodUSB card)
```

Run the verification script on the Pi to confirm each stage is live:

```bash
sudo /opt/bt2iap/scripts/verify-audio.sh
```

The script runs 10 checks in order:
1. `snd_aloop` module loaded (`lsmod | grep snd_aloop`)
2. `Loopback` card present in `/proc/asound/cards`
3. `iPodUSB` card present in `/proc/asound/cards` (depends on T1 `g_ipod_audio.ko`)
4. `aplay -l` lists both Loopback and iPodUSB cards
5. `/etc/asound.conf` exists and is non-empty
6. `bluealsa.service` is active
7. `bluetooth.service` is active
8. `audio-bridge.service` is active
9. Bluetooth controller powered (`bluetoothctl show | grep "Powered: yes"`)
10. End-to-end probe: 1 second of silence routed through `default` PCM via the full chain without ALSA errors

Exits 0 if all pass, 1 otherwise. Use `--verbose` for extra diagnostic dumps.

## T3 usage (operator runbook)

### Failure triage

`docs/triage.md` covers all 4 failure modes with a symptom / confirm-command / action matrix:

1. `dmesg` shows authentication error from head unit
2. MMCS sees device but won't play
3. Pi boot-loops in car
4. Audio path issues

**Policy (2026-04-19):** FM transmitter fallback is explicitly rejected. The project commits to iAP to completion. The triage doc reflects this — auth failures route to deeper iAP recovery, not FM pivot.

### Deep auth recovery

`docs/iap-auth-deep-dive.md` documents the 4-stage escalation path for auth failures:

1. Exhaust `product_id` candidates from `doc/apple-usb.ids` in `oandrew/ipod-gadget`
2. MFi authentication chip add-on feasibility (circuit and driver change points)
3. Scan upstream `oandrew/ipod-gadget` issues and forks for known auth-handshake fixes
4. iAP protocol reverse-engineering direction notes

### Support bundle

When filing a bug or escalating a failure, collect a diagnostic bundle on the Pi:

```bash
sudo /opt/bt2iap/scripts/collect-diagnostics.sh
```

This gathers: `uname`, `os-release`, `lsmod`, `lsusb`, ALSA card state, BlueZ/BlueALSA service status, per-service `journalctl` tails, and filtered `dmesg` output — packed into a single `.tar.gz`. Bluetooth MAC addresses are partially masked (OUI retained). Review for Wi-Fi SSIDs before sharing.

Use `--no-tar` to leave the directory unpacked for local inspection:

```bash
sudo /opt/bt2iap/scripts/collect-diagnostics.sh --no-tar
```

## T4 extension research

Forward-looking notes for when T2 is working and the project wants to add steering-wheel button support, track metadata display, or needs hardware capture tools for deeper protocol analysis. T4 is docs-only — no scripts, no hardware purchases in this tier.

- `docs/iap-messages.md` — iAP message protocol reference: wire format, lingoes, playback and metadata commands. Useful when implementing lingo handlers beyond basic audio playback.
- `docs/advanced-iap-tools.md` — tool catalog for deeper debugging: USB analyzers (usbmon, Saleae), MFi chip breakout options, alternative fork build environments. Consulted only if T3 escalation paths are exhausted.

## Developer quality gates (on Mac)

```bash
brew install shellcheck make
make check        # runs check-t1, check-t2, check-t3, check-t4
make check-t1     # T1 gates only
make check-t2     # T2 gates only
make check-t3     # T3 gates only
make check-t4     # T4 gates only
```

`make check-t1` runs:
1. `shellcheck -x` on all files in `scripts/`
2. Systemd unit header validation (`[Unit]`, `[Service]`, `[Install]` present in `systemd/ipod-gadget.service`)
3. Boot patch content check (`dtoverlay=dwc2` and `modules-load=dwc2`)
4. Docs presence check (`docs/research-ipod-gadget.md`, `docs/verification-t1.md` exist and are non-empty)

`make check-t2` runs:
1. `shellcheck -x` on all files in `bluetooth/*.sh` and `scripts/*.sh`
2. Systemd unit header validation (`[Unit]`, `[Service]`, `[Install]` in `systemd/audio-bridge.service` and `systemd/pair-agent.service`; `[Service]` in `systemd/bluealsa.service.d/override.conf`)
3. ALSA config sanity check (`alsa/asound.conf` contains `pcm.*` or `type` directives)
4. Docs presence check (`docs/audio-topology.md` exists and is non-empty)
5. BlueZ patch payload check (`bluetooth/main.conf.patch.block` contains sentinel + `[General]`/`[Policy]`)

`make check-t3` runs:
1. `shellcheck -x` on all files in `scripts/` (includes `collect-diagnostics.sh`)
2. T3 docs presence check (`docs/triage.md` and `docs/iap-auth-deep-dive.md` exist and are non-empty)
3. Cross-reference sanity: `docs/triage.md` must contain the string `iap-auth-deep-dive.md` (confirms escalation link is present)
4. FM transmitter rejection context: if `FM transmitter` appears in `docs/triage.md`, it must be within 3 lines of a rejection keyword (`rejected`, `거부`, `명시적`, `policy`, or `금지`)
5. `scripts/collect-diagnostics.sh` exists and is executable

`make check-t4` runs:
1. `shellcheck -x` on all files in `scripts/` (inherits any new scripts added since T3)
2. T4 docs presence check (`docs/iap-messages.md` and `docs/advanced-iap-tools.md` exist and are non-empty)
3. Content sanity: `docs/iap-messages.md` must mention both `iAP` and `lingo`
4. Content sanity: `docs/advanced-iap-tools.md` must mention `usbmon` or `Saleae` (at least one capture tool referenced)

## Failure triage

See `CLAUDE.md` — "Known failure modes" section for triage order and recovery steps.

Triage priority:

1. `dmesg` shows authentication error from head unit — exhaust `product_id` candidates from `doc/apple-usb.ids` in the `ipod-gadget` repo, then investigate MFi auth chip options, then upstream issues/forks, then iAP reverse-engineering.
2. MMCS sees device but won't play — iterate `product_id` using `scripts/product-id-loop.sh`.
3. Pi boot-loops in car — power issue; use 2A+ cigarette-lighter charger.
4. Audio path issues — debug with BlueALSA, not PulseAudio/PipeWire.

**Policy:** FM transmitter fallback is explicitly rejected. iAP to completion.

## Upstream and credits

- [oandrew/ipod-gadget](https://github.com/oandrew/ipod-gadget) — kernel modules (`g_ipod_audio.ko`, `g_ipod_hid.ko`, `g_ipod_gadget.ko`) and Go client; ground truth for iAP gadget behavior
- [oandrew/ipod](https://github.com/oandrew/ipod) — Go iAP client library
- [xtensa/PodEmu](https://github.com/xtensa/PodEmu) — 30-pin iPod dock reference; not directly usable over USB-A, consulted for iAP message reference (T4)

## Project status summary

### What's done (pre-hardware)

- T1: gadget boot minimum (scripts, boot patches, systemd unit, docs) — pushed
- T2: audio path complete (BlueZ, BlueALSA, ALSA loopback, audio-bridge, pair-agent) — pushed (this is the spec acceptance line)
- T3: iAP deep recovery runbook (triage.md, iap-auth-deep-dive.md, collect-diagnostics.sh) — pushed
- T4: extension research (iap-messages.md, advanced-iap-tools.md) — pushed

### What needs Pi hardware

- Actually running `sudo ./scripts/bootstrap.sh` on a Raspberry Pi Zero 2 W.
- Installing in-car, testing pairing with phone, confirming MMCS recognizes the gadget as iPod.
- Running `scripts/product-id-loop.sh` if the default product_id doesn't work.
- Running `scripts/verify-audio.sh` post-audio-install.
- Escalating to `docs/iap-auth-deep-dive.md` stages if auth blocks.

All documentation and automation artifacts are complete. Hardware arrival is the next gate.

## License

License: TBD
