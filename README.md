# bt2iap

Bluetooth-to-iAP bridge: streams phone audio via A2DP through a Raspberry Pi Zero 2 W that impersonates an iPod over USB into a 2007-2012 Mitsubishi Outlander MMCS head unit.

## Architecture

```
[Phone] --BT A2DP--> [Pi Zero 2 W] --USB iAP--> [Outlander USB-A]
                                                         |
                                        MMCS recognizes as iPod
```

The Pi presents itself as an Apple iPod using the `ipod-gadget` kernel module over USB gadget mode (`dwc2`). Audio is received via Bluetooth A2DP (BlueALSA), routed through an ALSA loopback, and fed into the `iPodUSB` ALSA card exposed by `g_ipod_audio.ko`.

## Status

Pre-hardware. Currently at T1 (gadget boot minimum). See `.omc/specs/deep-interview-pre-pi-prep.md` for the tiered plan.

## Hardware

- **Pi:** Raspberry Pi Zero 2 W, Raspberry Pi OS Lite 64-bit, headless (Wi-Fi + SSH configured via Imager)
- **Car:** Mitsubishi Outlander 2007-2012, MMCS head unit, USB-A port (iPod-only, iAP protocol)
- **Power note:** Car USB-A is under 1A. Use a 2A+ cigarette-lighter USB charger for Pi power; connect only the data line from the head unit.

## Repository layout

```
bt2iap/
|-- scripts/       # Pi-side automation (bootstrap, gadget load, product_id loop)
|-- systemd/       # Unit files installed to /etc/systemd/system/
|-- boot/          # Patches for /boot/config.txt and /boot/cmdline.txt
|-- docs/          # Research notes and verification checklists
|-- Makefile       # Mac-side quality gates
`-- CLAUDE.md      # Project context for AI assistants
```

## T1 install (on Pi)

```bash
# 1. Clone this repo to /opt/bt2iap on the Pi
sudo git clone https://github.com/twinn1013/bt2iap /opt/bt2iap
cd /opt/bt2iap

# 2. Run bootstrap (installs deps, builds modules, enables service)
sudo ./scripts/bootstrap.sh

# 3. Reboot
sudo reboot

# 4. After reboot, verify
sudo ./scripts/load-gadget.sh  # or: systemctl status ipod-gadget
```

The bootstrap script handles: `apt` dependencies (`build-essential`, `raspberrypi-kernel-headers`, `golang`, `bluez`, `bluez-tools`, `bluealsa`), cloning and building `oandrew/ipod-gadget`, building the `oandrew/ipod` Go client, and enabling the `ipod-gadget` systemd service.

Boot patches (`boot/config.txt.patch`, `boot/cmdline.txt.patch`) must be applied before reboot to enable `dwc2` gadget mode:

- `dtoverlay=dwc2` in `/boot/config.txt`
- `modules-load=dwc2` appended after `rootwait` in `/boot/cmdline.txt`

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

## Developer quality gates (on Mac)

```bash
brew install shellcheck make
make check-t1
```

`make check-t1` runs:
1. `shellcheck -x` on all files in `scripts/`
2. Systemd unit header validation (`[Unit]`, `[Service]`, `[Install]` present in `systemd/ipod-gadget.service`)
3. Boot patch content check (`dtoverlay=dwc2` and `modules-load=dwc2`)
4. Docs presence check (`docs/research-ipod-gadget.md`, `docs/verification-t1.md` exist and are non-empty)

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

## License

License: TBD
