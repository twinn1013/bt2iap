# bt2iap

*한국어* · [English](README.en.md)

라즈베리파이를 iPod 인 것처럼 USB로 붙여서, 폰 A2DP 오디오를 iPod USB 입력이 있는 **카오디오 헤드유닛**에 흘려 넣는 Bluetooth-to-iAP 브릿지.

```
[Phone] --BT A2DP--> [Pi] --USB iAP--> [Head unit iPod USB]
```

## 호환

- **Pi:** Raspberry Pi Zero 2 W (권장). Zero W 1세대도 가능하지만 A2DP 디코드 여유는 Zero 2 W가 낫다. Pi 4/5는 오버스펙.
- **OS:** Raspberry Pi OS Lite 64-bit (Bookworm 기준, 구버전도 스크립트가 자동 감지).
- **카오디오:** iPod 를 USB 로 받는(`iAP1` 기반) 순정/애프터 헤드유닛이면 대상. 실제 페어 동작은 헤드유닛마다 `product_id` 수용이 다르므로 `scripts/product-id-loop.sh`로 탐색하는 것이 전제.

## 설치 (Pi에서)

```bash
sudo git clone https://github.com/twinn1013/bt2iap /opt/bt2iap
cd /opt/bt2iap
sudo ./scripts/bootstrap.sh
sudo reboot
```

`bootstrap.sh`가 하는 일: apt 의존성 설치, `oandrew/ipod-gadget` + `oandrew/ipod` 클론/빌드, `/boot/firmware/config.txt` 또는 `/boot/config.txt` 에 `dtoverlay=dwc2` 적용, `/boot/*/cmdline.txt` 에 `modules-load=dwc2` 삽입, T1/T2 systemd 유닛 전부 설치 및 `enable --now`.

재부팅 후 검증:

```bash
sudo /opt/bt2iap/scripts/verify-audio.sh
```

## product_id 탐색

헤드유닛이 기본 `product_id`를 거부하면 순환 시도:

```bash
sudo BT2IAP_INTERACTIVE=1 /opt/bt2iap/scripts/product-id-loop.sh
```

동작하는 ID를 찾으면 영속화:

```bash
sudo sed -i 's/^#\?PRODUCT_ID=.*/PRODUCT_ID=0x1261/' /etc/default/bt2iap
sudo systemctl restart ipod-gadget.service
```

## 구조

| 경로 | 역할 |
| --- | --- |
| `scripts/` | bootstrap, gadget/audio 로더, product_id 루프, verify, 진단 번들 |
| `systemd/` | 서비스 유닛 + drop-in override |
| `boot/` | `/boot/.../{config,cmdline}.txt` 패치 |
| `bluetooth/` | BlueZ 설정 패치 + 페어링 에이전트 |
| `alsa/` | A2DP → snd-aloop → iPodUSB 라우팅 |
| `docs/` | 리서치, 검증 체크리스트, 오디오 토폴로지, 실패 triage, iAP 프로토콜 레퍼런스 |

## 문제가 생기면

- `docs/triage.md` — 실패 증상별 점검 매트릭스.
- `docs/iap-auth-deep-dive.md` — 헤드유닛이 인증에서 튕길 때 4단계 복구 (product_id 소진 → MFi 칩 feasibility → 업스트림 포크 스캔 → 프로토콜 리버싱).
- `docs/audio-topology.md` — Phone → BlueALSA → loopback → iPodUSB 신호 경로.
- 버그 리포트용 번들: `sudo /opt/bt2iap/scripts/collect-diagnostics.sh`.

## 기여

`make check` (shellcheck + systemd/ALSA/패치 검증) 통과가 PR 전제. 자세한 게이트는 `Makefile` 참고.

## 업스트림

- [oandrew/ipod-gadget](https://github.com/oandrew/ipod-gadget) — 커널 gadget + Go 클라이언트 (ground truth).
- [oandrew/ipod](https://github.com/oandrew/ipod) — Go iAP 클라이언트.
- [xtensa/PodEmu](https://github.com/xtensa/PodEmu) — 30-pin 레퍼런스 (T4 프로토콜 참조용).

## 라이선스

TBD.
