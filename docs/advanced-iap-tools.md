# Advanced iAP Tools — 심층 해결용 하드웨어/소프트웨어 카탈로그

본 문서는 T4 확장 리서치의 두 번째 산출물로, `docs/iap-auth-deep-dive.md` Stage 2 ~ Stage 4 (MFi feasibility, upstream fork 스캔, wire-level 역공학) 에서 실제로 손에 쥘 만한 **도구/장비/환경의 카탈로그** 다. 구매 가이드와 capability map 을 겸한다.

- 원전 정책: `CLAUDE.md` §"Scope discipline" — 본 문서의 어느 항목도 FM transmitter 우회를 가정하지 않는다. 본 카탈로그의 목적은 iAP 완주 경로에서의 depth 확보뿐이다.
- 상위 runbook: `docs/iap-auth-deep-dive.md` Stage 2 / Stage 3 / Stage 4 에서 본 문서를 역참조한다.
- 공급처 정보는 hobbyist 시장 특성상 2026-04-19 snapshot 으로도 빠르게 변한다. URL 을 확정하지 않는 항목에는 `search:` prefix 로 키워드만 남긴다.

---

## 1. USB Protocol Analyzer (wire 캡처)

Stage 4 역공학에서는 "known-good iPhone 세션" 과 "우리 Pi gadget 세션" 을 **동일 헤드유닛 상대로** 캡처해 diff 하는 것이 핵심이다. 이를 위한 도구 비교다.

### 1.1 Wireshark + usbmon (Linux 표준, 무료)

가장 저렴하고 Pi 또는 어떤 Linux 박스에서도 바로 쓸 수 있는 소프트웨어-only 경로.

- 필요 커널 모듈: `usbmon` — 주류 배포판 커널에 기본 포함. `modprobe usbmon` 한 번이면 활성화되고, 루프백 인터페이스 `usbmon0` / `usbmon1` 이 Wireshark 인터페이스 목록에 뜬다.
- Pi OS Lite 에서의 활성화:
  ```bash
  sudo modprobe usbmon
  sudo chmod a+r /dev/usbmon*   # non-root 로 읽을 경우
  ```
- 캡처 (CLI):
  ```bash
  sudo tshark -i usbmon0 -w /tmp/iap.pcap
  ```
- 필터 예시 (Wireshark 디스플레이 필터 문법):
  ```
  usb.src == "2.5.0" || usb.dst == "2.5.0"       # 특정 디바이스 주소 2.5 의 트래픽
  usb.bInterfaceClass == 0xff                     # vendor-specific interface (iAP bulk)
  usb.capdata contains ff:55                      # iAP 프레임 sync 바이트 포함
  ```
- **강점:** 비용 0, Pi 위에서 Pi 자신의 gadget 트래픽 (= 자기 자신이 호스트에게 보내는 것) 도 관찰 가능.
- **약점:** 물리 계층(USB low-level timing, bit-level jitter, reset pulse) 은 전혀 안 보임. Apple 식별 과정에서 BUS reset 패턴이나 특수 Chirp 같은 미묘한 신호는 놓친다. "메시지 수준" diff 에는 충분하지만 "링크 계층 비교" 에는 부족.

### 1.2 Saleae Logic Analyzer (commercial ~$100-400)

Saleae 는 **USB 1.1 Full-Speed (12 Mbps)** 를 무리 없이 잡는 엔트리급 로직 분석기 제품군을 낸다. iAP/g_ipod_gadget 이 Full-Speed 로 고정된 사실(upstream commit `fda808e`, `docs/research-ipod-gadget.md` §3) 을 감안하면 입문급으로도 충분하다.

- 추천 모델:
  - **Saleae Logic 8 (현행 Pro 8 이전 구형 가격 대역)** — 24 MHz 샘플링, 8 채널. USB D+/D- 를 두 채널에 물려 decoding. 중고 가격대 $80~$150.
  - **Saleae Logic Pro 8** — 500 MHz 디지털 샘플링. USB 2.0 High-Speed (480 Mbps) 디코딩은 실용 한계지만 **우리 대상은 Full-Speed** 이므로 오버스펙.
- 디코더: Saleae Logic 2 소프트웨어에 내장된 **"USB LS and FS" 디코더** 사용. Full-Speed (12 Mbps) 패킷 구조(SYNC/PID/ADDR/ENDP/CRC/EOP) 까지 GUI에 풀어서 보여준다.
- 프로브 접근: USB-A 커넥터 내부의 D+/D- 선에 직접 물리기 어려우므로 **USB breakout board** (예: search: `USB-A breakout PCB`) 로 중간 삽입. AliExpress/Mouser 에서 수천 원 수준.
- **강점:** GUI에서 아날로그 파형과 디지털 디코드를 동시 확인. 타이밍 이슈(예: "첫 SETUP 패킷 후 5ms 내 응답 안 하면 MMCS 가 포기" 같은 시간 경계) 가 의심될 때 유일한 답.
- **약점:** 트랜잭션-레벨(IN/OUT/SETUP, ACK/NAK) 은 보이지만 프로토콜-상위 계층(iAP 프레임 내부)는 원시 hex 로 보이므로 후처리(스크립트 export → iAP 파서)가 필요.

### 1.3 Total Phase Beagle USB (commercial ~$400+)

iAP1 에 비해 오버킬이지만 완전성을 위해 기입.

- 모델:
  - **Beagle USB 12** — Full-Speed 전용, 정가 $400~$500 대.
  - **Beagle USB 480** — High-Speed 까지, $1,200+.
- 강점: Total Phase Data Center 소프트웨어가 USB 트랜잭션 decode 품질에서 Saleae 보다 정돈됨. iAP 같은 vendor-specific bulk transfer 도 raw hex 로 깔끔하게 저장 → scapy 후처리 용이.
- 약점: 가격. iAP1/Full-Speed 만 본다면 Saleae + Wireshark 조합이 가성비 압도.

### 1.4 Cypress CY7C68013A / FX2LP 개발보드 + sigrok (DIY, ~$10-20)

가장 저렴한 DIY 경로.

- 하드웨어: AliExpress "CY7C68013A USB logic analyzer" 검색(search: `CY7C68013A logic analyzer aliexpress`). 8채널, 최대 24 MHz 실용 한계.
- 소프트웨어: [sigrok PulseView](https://sigrok.org/wiki/PulseView) — 오픈소스, Saleae 구형 펌웨어 흉내 가능. USB LS/FS decoder 포함.
- 강점: 가격이 Saleae 의 1/10.
- 약점: 24 MHz 샘플링이 USB FS (12 Mbps) 기준 2x 샘플/bit 에 불과 → 노이즈·jitter 가 있으면 decode 실패율 높음. 실험용/입문용 권장, 정밀 측정에는 Saleae.

### 1.5 비교표

| Tool | 캡처 USB 속도 | 비용 (KRW 대략) | Protocol decode 품질 | Pi 에서 단독 사용 가능 | 판정 |
|------|---------------|----------------|---------------------|------------------------|------|
| Wireshark + usbmon | Full-Speed + High-Speed (software) | ₩0 | 메시지 레벨 (우수) / 링크 레벨 (불가) | Yes | **Stage 4 1순위** |
| Saleae Logic 8 (신규/중고) | Full-Speed ok, HS 한계 | ₩150k~₩500k | 링크 레벨 디코드 (우수) | No (별도 PC 필요) | Stage 4 타이밍 이슈 의심 시 |
| Saleae Logic Pro 8 | HS 가능 | ₩1.0m~₩1.5m | 우수 | No | iAP1에는 오버 |
| Total Phase Beagle USB 12 | Full-Speed 전용 | ₩500k~₩600k | 최상 (상업용) | No | 예산 여유 시 |
| CY7C68013A + sigrok | Full-Speed 한계 수준 | ₩10k~₩20k | FS 디코드 가능하나 불안정 | No | 실험용 |

---

## 2. MFi Chip Breakout (Stage 2 MFi feasibility)

`docs/iap-auth-deep-dive.md` §Stage 2 에서 다룬 MFi coprocessor 를 실제 Pi에 물리려 할 때의 부품 옵션이다. **구매·구현은 본 프로젝트 T3 범위에서 보류** 이며, 본 섹션은 "필요해지면 어디서 뭘 얼마에 살 수 있는가" 의 참고 카탈로그다.

### 2.1 조달 옵션 (3가지)

| Channel | 현실성 | 비고 |
|---------|--------|------|
| Apple 공식 MFi 프로그램 | 사실상 불가 (개인) | 법인 등록 + NDA + 품질 심사. hobbyist 대상 아님. Stage 2 feasibility 관점에서 "경로 없음" 으로 확정해도 무방. |
| Adafruit / Sparkfun 류 호비스트 스토어 재고 | 제한적 / 간헐적 | search: `MFi authentication coprocessor Adafruit`, `iPod auth IC Sparkfun`. 과거 특정 시점에 재고가 돈 사례가 있으나 2026-04-19 기준 정기 재고로 보이지 않음. 검색 시점에 직접 확인 필요. |
| AliExpress / Taobao 변형/복제 칩 | 접근성 높음 / 품질 편차 큼 | search: `MFi authentication IC aliexpress`, `iAP auth chip breakout`, `iPod Apple coprocessor`. Lightning 시대 복제 IC 와 30-pin 시대 MFi IC 는 **인터페이스가 다르므로 구매 전 I2C MFi coprocessor 인지 명세 확인 필수** (`docs/iap-auth-deep-dive.md` §Stage 2). |

공식 URL 을 단정하지 않는 이유: 2026년 hobbyist 시장에서 해당 부품 재고가 수시로 바뀐다. 검색 키워드를 출발점으로 삼아 현 시점의 판매자를 확인.

### 2.2 Pi Zero 2 W 배선 참조

MFi coprocessor 의 노출된 인터페이스(세대별 편차 있으나 공통 요약):

| Pin | 용도 | Pi Zero 2 W GPIO 헤더 매핑 (40-pin) |
|-----|------|-------------------------------------|
| VCC | 3.3V | Pin 1 (3V3) |
| GND | 접지 | Pin 6 (GND) 또는 9/14/20/25/30/34/39 |
| SDA | I2C data | Pin 3 (GPIO 2 / SDA1) |
| SCL | I2C clock | Pin 5 (GPIO 3 / SCL1) |
| RESET (선택적, 세대별) | 칩 리셋 | 임의 GPIO (예: Pin 11 = GPIO 17) |

추가 외부 부품:

- SDA/SCL 에 각각 **4.7 kΩ pull-up** 을 3.3V 로 (Pi 내부 pull-up 은 약하므로 외부 권장).
- 전원은 Pi 의 3.3V 레일(최대 500mA까지 안정) 에서 바로 분배. MFi IC 는 mA 단위로 소모하므로 여유.

Pi 핀맵 레퍼런스: `pinout.xyz` (search: `raspberry pi zero 2 w pinout`). Physical pin 번호와 BCM GPIO 번호 매핑의 표준 시각 자료.

### 2.3 커널 드라이버 통합 준비

`docs/iap-auth-deep-dive.md` §Stage 2 "소프트웨어 통합 요구" 에 정리되어 있듯이, upstream `oandrew/ipod-gadget` 에는 MFi coprocessor 호출 훅이 **없다**. 실제 통합에 들어간다면 필요한 도구는:

- `i2c-tools` apt 패키지 (`i2cdetect -y 1` 로 I2C1 버스에 붙은 MFi 칩 주소 확인).
- `dtparam=i2c_arm=on` 을 `/boot/config.txt` 에 추가 → 재부팅 후 I2C1 활성화.
- user-space 에서 먼저 `/dev/i2c-1` 을 열어 challenge/response 프로토콜을 Python/C 로 재현 → 검증 완료 후 커널 모듈(`gadget/ipod_gadget.c`) 에 i2c_client API 로 이식. 이 검증 단계를 건너뛰면 커널 panic 위험이 급증하므로 **반드시 user-space POC 먼저**.

### 2.4 관련 upstream 반응

- [#17 Mitsubishi detects iPod, but doesn't play audio](https://github.com/oandrew/ipod-gadget/issues/17) — auth 가능성 토론 스레드. MFi 통합을 구체적으로 제안하는 내용은 현재 댓글 레벨에서는 **없음** (`docs/iap-auth-deep-dive.md` §Stage 3 확인 대상).
- upstream 이 MFi 통합 PR 을 받아줄 의사가 있는지는 불명. DKMS 같은 non-invasive PR (#8, #30) 도 머지되지 않은 이력을 감안하면 **자체 fork 운용** 이 기본 전제여야 한다 (`docs/research-ipod-gadget.md` §3 인용).

---

## 3. ipod-gadget Fork 빌드 환경 (Stage 3)

upstream `oandrew/ipod-gadget` 에 패치가 들어가지 않을 가능성을 전제로 한 로컬 fork 운영 가이드다.

### 3.1 Fork 를 떠야 하는 시점

- Stage 3 에서 쓸 만한 패치 후보를 fork 목록(`gh api /repos/oandrew/ipod-gadget/forks`)에서 발견했고, 그대로 cherry-pick 하고 싶을 때.
- 자체 수정(MFi hook 추가, 로그 확장, product_id 런타임 스위치 등)이 필요해 upstream 에 PR 을 내기 전에 일단 로컬에서 돌려야 할 때.

### 3.2 빌드 전제 조건 (Pi 위에서 on-device)

- `raspberrypi-kernel-headers` apt 패키지 — 현재 실행 중인 커널 ABI 에 맞는 헤더. `/lib/modules/$(uname -r)/build` 심볼릭이 정상 걸려 있어야 함.
- `build-essential` (gcc, make).
- **Cross-compile 은 본 프로젝트 범위에서 요구되지 않음** (`.omc/specs/deep-interview-pre-pi-prep.md` §Non-Goals: "크로스 컴파일 (Pi에서 on-device build)"). 따라서 Mac 에서 빌드 시도하지 말 것.

Fork 를 만들고 빌드하는 전형적 흐름:

```bash
# Pi 위에서
cd ~/src
git clone https://github.com/<YOUR_GH>/ipod-gadget.git
cd ipod-gadget
git remote add upstream https://github.com/oandrew/ipod-gadget.git
git fetch upstream
git checkout -b local-patches upstream/master

# 패치 적용 (cherry-pick 또는 직접 편집)
# ... 파일 수정 ...

cd gadget
make clean
make
```

### 3.3 CI (선택) — GitHub Actions

Fork 저장소의 `.github/workflows/build.yml` 에 다중 커널 ABI 빌드 검증 파이프를 두면, upstream 의 2025-08 커밋(`ece6b7b`: HID rpt_desc API 대응) 같은 커널 헤더 호환성 회귀를 조기 감지할 수 있다.

- 활용 가능한 action: [raspberrypi-kernel-source-action](https://github.com/marketplace?type=actions) 에서 관련 키워드 검색(search: `raspberry pi kernel module github action`). 특정 action 이 stable 여부는 확인 필요.
- 대안: Docker 컨테이너 (예: `dtcooper/raspberrypi-os` 이미지) 안에서 `apt install raspberrypi-kernel-headers` 후 `make` 수행하는 workflow 를 직접 작성. ABI 별 매트릭스:
  ```yaml
  strategy:
    matrix:
      kernel: ["6.1.y", "6.6.y", "6.12.y"]
  ```

### 3.4 Upstream 으로의 PR 제출

- upstream `oandrew/ipod-gadget` 에는 `CONTRIBUTING.md` 가 2026-04-19 기준 **없다**(`gh api /repos/oandrew/ipod-gadget/contents` 결과 재확인). README 상단의 간단한 지침이 전부.
- 제출 자체는 막혀 있지 않으나 머지 속도가 sparse 함은 `docs/research-ipod-gadget.md` §1 의 commit cadence 에서 그대로 드러난다 (최근 커밋 2025-08). 3년째 open 인 PR (#8, #30) 이 증거.
- 전략: **먼저 이슈로 설계/동기 제안 → 피드백 후 PR.** 작은 범위의 변경(빌드 수정, 주석 보완) 은 단독 PR 로 시도 가능. 기능 확장(MFi 훅, 메타데이터 응답)은 프로토타입이 완성된 후 논의 개시.

### 3.5 DKMS 패키징 (유지보수 자동화)

커널 업그레이드 때마다 수동 rebuild 를 피하려면 DKMS 로 묶는다. 기본 `debian/` 디렉토리 스켈레톤:

```
ipod-gadget/
├── debian/
│   ├── control                 # Source: ipod-gadget-dkms, Depends: dkms, raspberrypi-kernel-headers
│   ├── rules                   # dh $@ --with dkms
│   ├── compat
│   ├── changelog
│   ├── copyright               # MIT (upstream와 동일)
│   └── ipod-gadget-dkms.dkms   # PACKAGE_NAME=ipod-gadget\nPACKAGE_VERSION=x.y.z\nBUILT_MODULE_NAME[0]=g_ipod_gadget\n...
└── gadget/
    ├── Makefile
    └── *.c / *.h
```

upstream PR #8 / #30 이 DKMS 관련인 이유는 이 편의성이 크기 때문이며, 두 PR이 머지 안 됐다는 사실은 우리가 fork 로 갖고 가야 할 이유이기도 하다. (`docs/research-ipod-gadget.md` §3 인용.)

---

## 4. Bluetooth A2DP / AVRCP 분석 (audio-path debugging)

본 섹션은 iAP 문제가 아니라 **오디오 경로 디버깅** 을 위한 도구 — `docs/triage.md` §4 (failure mode #4) 대응 시의 참고용이다. auth 쪽과 혼동하지 말 것.

### 4.1 `hciconfig` / `btmgmt` — 컨트롤러 상태

```bash
hciconfig hci0                    # Pi 내장 BT 컨트롤러 기본 상태
hciconfig hci0 features            # 프로필 지원 비트마스크
sudo btmgmt --index 0 info         # 최신 BlueZ 선호 — pairable/discoverable 상태
```

A2DP source 프로파일이 활성인지, 링크 키가 제대로 저장돼 있는지 여기서 먼저 확인.

### 4.2 `btmon` — HCI 실시간 캡처

```bash
sudo btmon                         # 실시간 HCI 프레임
sudo btmon -w /tmp/hci.snoop        # 파일로 저장
```

페어링 실패, RFCOMM 채널 거부, A2DP SDP 실패 같은 이벤트를 실시간으로 본다. Wireshark 에서도 `.snoop` 열기 가능.

### 4.3 프로파일 상태 — BlueALSA vs PulseAudio

본 프로젝트는 **BlueALSA 를 선택** (`CLAUDE.md` §"Architecture decisions already made") 했으므로 정상 경로 기준:

```bash
bluealsa-cli list-pcms             # BlueALSA 가상 PCM 목록
bluealsa-aplay -L                  # 재생 가능한 source 목록
```

만약 PulseAudio / PipeWire 가 동시 동작 중이면 A2DP 소스가 거기로 빠져나가 BlueALSA 쪽은 비어 보일 수 있다 (`docs/triage.md` §4 Recovery step 6 와 동일 원인).

```bash
pactl list sink-inputs             # PulseAudio 가 살아있다면 여기로 audio 빠질 수 있음
systemctl --user status pipewire   # PipeWire 활성 여부
```

### 4.4 AVRCP (메타데이터/버튼 전달) 확인

AVRCP 는 BlueZ 의 `org.bluez.MediaPlayer1` D-Bus 인터페이스로 노출된다. Stage의 `docs/iap-messages.md` §7.3 "user-agent" 설계에 직접 연관.

```bash
busctl --system tree org.bluez             # BlueZ D-Bus 트리
busctl --system call org.bluez /org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX/player0 \
  org.freedesktop.DBus.Properties Get ss \
  org.bluez.MediaPlayer1 Track             # 현재 트랙 메타 query
```

이 경로가 살아 있으면 폰 → Pi 방향의 메타데이터 공급이 확보된다 (iap-messages.md §7.3 에 정의된 user-agent 데몬이 먹을 데이터).

---

## 5. iAP Test Harness / Simulator

"Pi 대신 소프트웨어 iPod 시뮬레이터" 는 현실적으로 성립하지 않는다. 아래는 대체 접근이다.

### 5.1 PodEmu 실 하드웨어 운용 (제한적)

- PodEmu 는 Android 앱 + 30-pin dock 커넥터용 HW 설계.
- USB-A 경로인 우리 Outlander 에 **직접 꽂을 수 없음**. 따라서 테스트 타깃은 아니고, `docs/iap-messages.md` 에서처럼 **iAP 메시지 레퍼런스 소스** 로만 쓴다.

### 5.2 Wireshark 캡처 replay (DIY)

`tshark -i usbmon0 -w session.pcap` 로 떴던 세션을 다시 재현하려면:

- Linux kernel 의 `gadget usbip` 를 써서 pcap 으로 저장된 디바이스-측 프레임을 시뮬레이션 디바이스로 재생 → 호스트(MMCS 또는 대체 헤드유닛) 에 흘려 넣는 DIY 러너를 작성. 공개 툴은 없고, `scapy` + `pyusb` 수준으로 스크립트 작성해야 한다.
- 이 경로는 Stage 4 역공학 반복 실험에서 "고정된 known-good 세션을 계속 재생하며 우리 gadget 의 응답을 A/B 한다" 류 용도.

### 5.3 Custom usbreplay 툴 — 자체 제작 필요

상용/오픈소스 기성 툴은 사실상 없음. iAP 세션 replay 는 직접 작성이 기본이라고 본다. Python `scapy.layers.usb` + USBIP 조합이 가장 접근성 좋음.

---

## 6. Capture 파싱 / 프로그래매틱 분석

pcap 파일을 사람이 훑지 않고 batch 로 돌리고 싶을 때.

### 6.1 `tshark` 필터링

```bash
# iAP 데이터 bulk transfer 만 추출 — vendor-specific class 인터페이스만 필터
tshark -r session.pcap -Y 'usb.bInterfaceClass == 0xff' \
       -T fields -e frame.time -e usb.src -e usb.dst -e usb.capdata \
  > session.iap.tsv
```

capdata 필드를 hex string 으로 떨어뜨리면 후단 파서에 바로 먹일 수 있다.

### 6.2 `scapy` USB dissector

```python
from scapy.all import rdpcap
packets = rdpcap("session.pcap")
for p in packets:
    if hasattr(p, 'capdata'):
        data = bytes(p.capdata)
        # FF 55 로 시작하는 iAP 프레임 식별
        if len(data) > 2 and data[0] == 0xFF and data[1] == 0x55:
            length = data[2]
            mode = data[3]
            # ... docs/iap-messages.md §2-4 에 따라 파싱
```

scapy 의 USB 레이어는 libpcap 의 usbmon 포맷을 그대로 읽는다. 위 `usb.capdata` 가 scapy 쪽에서는 `Raw` 또는 `DLT_USB_LINUX_MMAPPED` payload 로 접근된다.

### 6.3 `pyusbmon` / `linux-usbmon` 라이브러리

`usbmon` 바이너리 포맷을 Python 으로 다루는 경로. search: `python usbmon parser`. scapy 에 밀려 점유율 낮지만, pcap 이 아니라 커널 `/sys/kernel/debug/usb/usbmon/0u` 를 실시간 소비해야 할 때 유용.

---

## 7. When to buy what — 의사결정 매트릭스

예산 대비 용도 매핑. "Pi 도착 후" 시점 기준.

| 상황 / 목적 | 필요한 도구 | 필요 예산 (KRW) | 소요 시간 |
|-------------|-------------|----------------|-----------|
| "iAP 프레임이 나오긴 하는지만 확인" | Wireshark + usbmon (Pi 내장) | ₩0 | 당일 |
| "특정 product_id 에서 dmesg/wire 로그 diff" | Wireshark + tshark CLI 자동화 스크립트 | ₩0 | 수 시간 |
| "비트-레벨 타이밍 의심 (auth challenge 응답이 delay 되는가?)" | Saleae Logic 8 (중고) + USB breakout | ₩200k~₩500k | 2~3일 셋업 |
| "Pi 의 USB 트래픽과 iPhone known-good 세션을 나란히 비교" | Wireshark + 별도 Linux 노트북 (MITM) | 보유 장비 활용 ₩0 | 1~2일 |
| "MFi auth chip 시도 (Stage 2 실제 구현 진입)" | MFi IC 모듈 + breakout + 풀업 저항 | ₩30k~₩80k 부품 + 2~6주 공수 | 수 주 |
| "upstream 커널 패치 필요 (Stage 3 결과 after cherry-pick)" | fork + 로컬 빌드 환경 (추가 HW 불필요) | ₩0 | 수 일~수 주 |
| "iAP 프로토콜 전수 역공학 (Stage 4)" | Wireshark + 별도 Linux + Saleae (옵션) + 충분한 시간 | ₩0~₩500k | 수 주~수 개월 |

기본 원칙:

- **먼저 Wireshark + usbmon 으로 시작한다.** 무료에 즉시 활용 가능하고 메시지 레벨 diff 의 90%는 이걸로 해결된다.
- Saleae 는 "타이밍 이슈가 진짜로 의심될 때" 만 구매. 메시지 diff 수준에서 해결 기미 있으면 굳이 안 산다.
- MFi chip 부품비 자체는 크지 않으나 **커널 드라이버 통합 공수가 진짜 비용** 이다. hobbyist 1인 기준 수 주 단위.

---

## 8. 예산 테이블 (hobbyist scale, KRW 추정)

| 항목 | 최소 | 현실적 | 상한 |
|------|------|--------|------|
| USB breakout board (D+/D- 탭) | ₩2k | ₩10k | ₩30k |
| 로직 분석기 (DIY CY7C68013A) | ₩10k | ₩15k | ₩25k |
| 로직 분석기 (Saleae Logic 8 중고) | ₩150k | ₩250k | ₩500k |
| 로직 분석기 (Saleae Logic Pro 8 신품) | ₩1.0m | ₩1.2m | ₩1.5m |
| MFi IC 모듈 (AliExpress, 품질 보장 없음) | ₩10k | ₩30k | ₩50k |
| MFi breakout board + 풀업 저항/와이어 세트 | ₩5k | ₩15k | ₩30k |
| 별도 Linux 노트북 (MITM 캡처용, 중고 활용) | 보유 활용 ₩0 | ₩300k | ₩800k |
| USB isolator (캡처 시 noise 차단용 선택적) | ₩15k | ₩30k | ₩60k |
| 멀티미터 / 케이블 교체 일체 | ₩5k | ₩20k | ₩50k |
| **(합) Stage 4 까지 풀셋 (Saleae 포함)** | ₩200k | ₩400k | ₩1.0m |
| **(합) MFi 시도 풀셋 (Stage 2 실 구현)** | ₩30k | ₩80k | ₩150k |
| **(합) 최소 경로 (Wireshark + Pi 기본)** | ₩0 | ₩0 | ₩10k (케이블류) |

예산 소수점 이하는 반올림. USD/KRW 환율 약 1,350 KRW/USD 기준으로 환산한 추정치이며, 실 구매 시 환율/할인에 따라 편차 있음.

---

## 9. 참조 / 원전

- 본 프로젝트 교차참조:
  - `docs/iap-auth-deep-dive.md` Stage 2 ~ Stage 4 — 본 카탈로그가 실제로 호출되는 상위 runbook.
  - `docs/iap-messages.md` §6 / §7 — 메타데이터 확장 구현 맥락에서 본 문서의 도구 선택이 어디에 걸리는지.
  - `docs/research-ipod-gadget.md` §3 — upstream 의 커밋 cadence / 머지 속도 특성 (§3 의 caveat 이 fork 운용 전제의 근거).
  - `docs/triage.md` §4 — Bluetooth 경로 디버깅 도구 사용 시점.
- 외부 레포:
  - [`oandrew/ipod-gadget`](https://github.com/oandrew/ipod-gadget).
  - [`oandrew/ipod`](https://github.com/oandrew/ipod).
  - [`xtensa/PodEmu`](https://github.com/xtensa/PodEmu).
- 외부 도구 홈페이지:
  - [Wireshark](https://www.wireshark.org/) — libpcap + dissector.
  - [sigrok PulseView](https://sigrok.org/wiki/PulseView) — FOSS 로직 분석기 GUI.
  - [Saleae Logic 2](https://www.saleae.com/) — 상용 로직 분석기 소프트웨어.
  - [Total Phase Data Center](https://www.totalphase.com/) — Beagle USB 분석기 SW.
- 검색 힌트 (URL 이 시점에 따라 변동):
  - `search: 'MFi authentication IC aliexpress'`
  - `search: 'MFi authentication coprocessor Adafruit'`
  - `search: 'USB-A breakout PCB'`
  - `search: 'raspberry pi zero 2 w pinout'`
  - `search: 'raspberry pi kernel module github action'`
  - `search: 'python usbmon parser'`
  - `search: 'iPod Accessory Protocol Interface Specification PDF'` (iAP 명세 PDF, 공식 경로 없음)
- Linux 커널 문서:
  - [`Documentation/usb/gadget_configfs.rst`](https://www.kernel.org/doc/html/latest/usb/gadget_configfs.html) — configfs 기반 composite gadget.
  - [`Documentation/usb/usbmon.rst`](https://www.kernel.org/doc/html/latest/usb/usbmon.html) — usbmon 인터페이스 설명.

---

## 10. 본 문서 사용 지침

- `docs/iap-auth-deep-dive.md` Stage 2 / 3 / 4 로 진입할 때 이 문서를 같이 연다.
- "Stage N 에서 필요한 도구가 뭐지?" → §7 의사결정 매트릭스에서 해당 행을 찾는다.
- 구매 결정이 필요한 순간에는 §8 예산 테이블을 근거로 사용자 승인 루틴을 연다. 본 문서가 자동 구매를 승인하지는 않는다 ― 구매 실행은 반드시 사용자 명시 승인 뒤에만.
- 공급처 URL 은 검색 힌트 위주로 남겼다. 실 구매 전 해당 시점 재고/정품 여부를 직접 확인한다.
