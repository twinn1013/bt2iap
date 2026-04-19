# bt2iap

[한국어](README.md) · *English*

A Bluetooth-to-iAP bridge. A Raspberry Pi impersonates an iPod over USB so phone audio (A2DP) plays through any head unit that accepts an iPod on USB.

```
[Phone] --BT A2DP--> [Pi] --USB iAP--> [Head unit iPod USB]
```

## Compatibility

- **Pi:** Raspberry Pi Zero 2 W (recommended). Zero W 1st-gen works but has less headroom for A2DP decode. Pi 4/5 is overkill.
- **OS:** Raspberry Pi OS Lite 64-bit. Bookworm is the primary target; the bootstrap auto-detects older layouts.
- **Head unit:** any factory or aftermarket stereo that accepts an iPod over USB (iAP1). Which `product_id` values each head unit accepts varies, so expect to use `scripts/product-id-loop.sh` to find one.

## Install (on the Pi)

```bash
sudo git clone https://github.com/twinn1013/bt2iap /opt/bt2iap
cd /opt/bt2iap
sudo ./scripts/bootstrap.sh
sudo reboot
```

`bootstrap.sh` installs apt dependencies, clones and builds `oandrew/ipod-gadget` and `oandrew/ipod`, patches `/boot/firmware/config.txt` or `/boot/config.txt` with `dtoverlay=dwc2`, inserts `modules-load=dwc2` into `/boot/*/cmdline.txt`, installs every T1/T2 systemd unit, and enables them with `enable --now`.

After reboot, verify:

```bash
sudo /opt/bt2iap/scripts/verify-audio.sh
```

## Finding a working product_id

If the head unit rejects the default `product_id`, cycle through candidates:

```bash
sudo BT2IAP_INTERACTIVE=1 /opt/bt2iap/scripts/product-id-loop.sh
```

Persist a working ID across reboots:

```bash
sudo sed -i 's/^#\?PRODUCT_ID=.*/PRODUCT_ID=0x1261/' /etc/default/bt2iap
sudo systemctl restart ipod-gadget.service
```

## Layout

| Path | Purpose |
| --- | --- |
| `scripts/` | bootstrap, gadget/audio loaders, product_id loop, verify, diagnostics bundler |
| `systemd/` | service units + drop-in overrides |
| `boot/` | `/boot/.../{config,cmdline}.txt` patches |
| `bluetooth/` | BlueZ config patch + pairing agent |
| `alsa/` | A2DP → snd-aloop → iPodUSB routing |
| `docs/` | research, verification checklist, audio topology, triage, iAP protocol reference |

## Troubleshooting

- `docs/triage.md` — symptom-indexed failure matrix.
- `docs/iap-auth-deep-dive.md` — 4-stage recovery when the head unit rejects authentication (exhaust product_ids → MFi chip feasibility → upstream fork scan → protocol reverse engineering).
- `docs/audio-topology.md` — Phone → BlueALSA → loopback → iPodUSB signal path.
- Bug-report bundle: `sudo /opt/bt2iap/scripts/collect-diagnostics.sh`.

## Contributing

`make check` (shellcheck + systemd/ALSA/patch gates) must pass before a PR lands. See `Makefile` for the full gate list.

## Upstream

- [oandrew/ipod-gadget](https://github.com/oandrew/ipod-gadget) — kernel gadget + Go client (ground truth).
- [oandrew/ipod](https://github.com/oandrew/ipod) — Go iAP client.
- [xtensa/PodEmu](https://github.com/xtensa/PodEmu) — 30-pin reference used for T4 protocol notes.

## License

TBD.
