# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository status

This repo is **pre-implementation**. The only tracked artifact is `아웃랜더 블루투스 프로젝트 정리.pdf` — a Korean-language design/feasibility memo. No source code, build system, or package manifest exists yet. Treat the PDF as the spec. Any automatic hints suggesting this is a JavaScript/TypeScript npm project are incorrect for this directory.

When asked to start implementation, the work will target a Raspberry Pi (cross-compiled or built on-device), not this Mac. Do not scaffold a Node/TS project here.

## Project goal (what we are building)

A Bluetooth-to-iAP bridge so a phone can stream audio (A2DP) through a Raspberry Pi Zero that impersonates an iPod over USB, into a 2007–2012 Mitsubishi Outlander's MMCS head-unit USB-A port (iPod-only, iAP protocol).

```
[Phone] --BT A2DP--> [Pi Zero 2 W] --USB iAP--> [Outlander USB-A]
                                                         |
                                        MMCS recognizes as iPod
```

Key premise: the iPhone is already recognized as iPod by this head unit, so MFi authentication is assumed to be loose → `ipod-gadget` alone should suffice (no MFi auth chip).

## Upstream dependencies (authoritative references)

- `ipod-gadget` — kernel module + Go client that simulates an iPod over USB: https://github.com/oandrew/ipod-gadget
- `ipod` client — https://github.com/oandrew/ipod
- `PodEmu` (30-pin reference, not directly usable over USB-A): https://github.com/xtensa/PodEmu

Before modifying anything iAP-related, check the current state of `oandrew/ipod-gadget` — activity there is sparse and its behavior is the ground truth. Also consult `doc/apple-usb.ids` in that repo for candidate `product_id` values.

## Architecture decisions already made

- **Hardware:** Raspberry Pi Zero 2 W (direct target — no separate prototype step; user decision 2026-04-19 skipped the Zero W 1st-gen prototype). Pico/Pico W are explicitly rejected (no Linux, no gadget mode). Pi 4/5 rejected as overspec. BeagleBone Black rejected (no on-board Bluetooth).
- **OS:** Raspberry Pi OS Lite (64-bit), headless (Wi-Fi + SSH pre-configured via Imager).
- **USB role:** Gadget/device mode via `dwc2` (`dtoverlay=dwc2` in `/boot/config.txt`, `modules-load=dwc2` in `/boot/cmdline.txt` after `rootwait`). The Pi's "USB" port is the data port; the "PWR" port is power-only.
- **Audio path:** Bluetooth A2DP sink → ALSA loopback → `iPodUSB` ALSA card (exposed by `g_ipod_audio.ko`). Preferred stack is `bluez` + `bluealsa` (lighter than PulseAudio/PipeWire, and the Pi OS move to PipeWire is noted as a risk).
- **Android-on-phone-as-gadget** and **laptop-as-gadget** paths were considered and rejected (root/kernel/BIOS barriers, USB stack conflicts).

## Planned build/run commands

These are from the design doc and will run on the Pi (not on this Mac). When the user starts implementation, stage them as an Ansible playbook / shell script / systemd unit under this repo rather than re-typing them.

```bash
# one-time host setup (on the Pi)
sudo apt update
sudo apt install -y git build-essential raspberrypi-kernel-headers golang \
                    bluez bluez-tools bluealsa

# build the kernel modules
git clone https://github.com/oandrew/ipod-gadget.git
cd ipod-gadget/gadget
make

# build the Go client
git clone https://github.com/oandrew/ipod.git
cd ipod
go build ./cmd/ipod

# load the gadget (order matters)
sudo modprobe libcomposite
sudo insmod gadget/g_ipod_audio.ko
sudo insmod gadget/g_ipod_hid.ko
sudo insmod gadget/g_ipod_gadget.ko

# if MMCS refuses the default ID, try alternate product IDs from doc/apple-usb.ids
sudo insmod gadget/g_ipod_gadget.ko product_id=0x1297
```

Verification signals after loading modules:
- `dmesg` shows `/dev/iap0` created
- When tethered to a PC, it enumerates as "Apple iPod"
- ALSA card `iPodUSB` appears (`aplay -l`)

## Known failure modes — triage in this order

1. **`dmesg` shows authentication error from the head unit** → MFi path is stricter than assumed. **Do NOT fall back to FM transmitter** (user policy 2026-04-19: pursue iAP to completion). Recovery order: exhaust candidate `product_id`s from `doc/apple-usb.ids` → investigate MFi authentication chip add-on (hardware breakout feasibility) → scan upstream `oandrew/ipod-gadget` issues/forks for known auth-handshake fixes → iAP protocol reverse-engineering as last resort.
2. **MMCS sees the device but won't play** → iterate `product_id` from `doc/apple-usb.ids`. This is the single most likely tuning knob.
3. **Pi boot-loops in the car** → car USB-A is under 1A; use a 2A+ cigarette-lighter USB charger for power, keep only the data line from the head unit.
4. **Audio path issues** → prefer `bluealsa` over PulseAudio/PipeWire when debugging routing; the doc deliberately picked BlueALSA for resource/stability reasons.

## Scope discipline

- Music playback is the goal. Track metadata display and steering-wheel buttons require extra iAP message implementation and are explicitly out of the initial scope.
- Expected outcome is ambitious. If blocked on head-unit auth, commit to deeper iAP investigation (product_id exhaustion → MFi chip feasibility → reverse-engineering). **FM transmitter fallback is explicitly rejected by user policy (2026-04-19) — iAP to completion.**

## Working directory layout

- `.omc/` — oh-my-claudecode state; not part of the product, safe to ignore when reasoning about the project itself.
- `아웃랜더 블루투스 프로젝트 정리.pdf` — the spec. To read it here, use `pdftotext -layout <pdf> <out.txt>` (poppler is installed at `/opt/homebrew/bin/pdftotext`); the filename contains Korean so quote it.
