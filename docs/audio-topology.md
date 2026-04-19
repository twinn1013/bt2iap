# T2 오디오 경로 토폴로지 (Audio Topology)

## 1. Overview

스마트폰이 블루투스 A2DP로 음악을 Pi에 전송하면, BlueALSA가 이를 받아 ALSA PCM 스트림으로 변환하고, ALSA loopback 카드(snd-aloop)를 거쳐 g_ipod_audio 커널 모듈이 노출하는 iPodUSB ALSA 카드로 라우팅된다. iPodUSB 카드는 USB iAP 프로토콜을 통해 Outlander MMCS 헤드유닛에 오디오를 전달하며, 헤드유닛은 Pi를 iPod으로 인식한다.

---

## 2. End-to-end Diagram (ASCII)

```
+---------+   A2DP BT      +-----------------+   virtual PCM    +--------------------+
|  Phone  | -------------> |    BlueALSA      | ---------------> |   bluealsa-aplay   |
+---------+  (a2dp-sink)   |  (bluealsa.svc)  |  (bluealsa:...)  |  (audio-bridge.sh) |
                           +-----------------+                   +--------------------+
                                                                          |
                                                                   ALSA PCM write
                                                                  (default / loopback)
                                                                          |
                                                                          v
                                                                +------------------+
                                                                |  ALSA loopback   |
                                                                |  snd-aloop card  |
                                                                |  (Loopback:0,0)  |
                                                                +------------------+
                                                                          |
                                                                   ALSA PCM read
                                                                   (loopback hw)
                                                                          |
                                                                          v
                                                                +-----------------+
                                                                |  g_ipod_audio   |
                                                                |  (iPodUSB card) |
                                                                +-----------------+
                                                                          |
                                                                   USB (iAP audio)
                                                                          |
                                                                          v
                                                                +------------------+
                                                                | Outlander MMCS   |
                                                                | (iPod recognized)|
                                                                +------------------+
```

---

## 3. Stage-by-stage Explanation

### Stage 1 — Phone → Bluetooth A2DP

**무엇을 하나:** 스마트폰이 블루투스 A2DP(Advanced Audio Distribution Profile) sink 역할을 하는 Pi에 압축 오디오(SBC 또는 AAC)를 전송한다. Pi가 A2DP sink이므로 폰은 source가 된다.

**어떤 패키지/모듈:** `bluez` (블루투스 스택), 커널 내 `btusb` / `hci_uart` 드라이버.

**어떤 설정 파일/서비스:**
- `/etc/bluetooth/main.conf` — `bluetooth/main.conf.patch`로 Discoverable=true, Pairable=true 등 설정.
- `bluetooth.service` — systemd 단위.

**디버깅 명령:**
```bash
bluetoothctl show           # 컨트롤러 상태 (Powered, Discoverable, Pairable)
bluetoothctl devices        # 페어링된 기기 목록
hciconfig hci0              # HCI 인터페이스 상태
journalctl -u bluetooth.service --no-pager | tail -30
```

---

### Stage 2 — BlueALSA (A2DP sink → virtual PCM)

**무엇을 하나:** BlueALSA(`bluealsa` 데몬)가 A2DP 스트림을 수신하여 ALSA virtual PCM 디바이스(`bluealsa:DEV=XX:XX:XX:XX:XX:XX,PROFILE=a2dp`)로 노출한다. PulseAudio/PipeWire 없이 동작하므로 Pi Zero 2 W의 제한된 리소스에 적합하다.

**어떤 패키지/모듈:** `bluealsa` 패키지 (`bluealsa` 데몬 + `bluealsa-aplay` 유틸리티).

**어떤 설정 파일/서비스:**
- `systemd/bluealsa.service.d/override.conf` — A2DP 프로파일만 활성화, `/etc/systemd/system/bluealsa.service.d/`에 설치.
- `bluealsa.service` — systemd 단위.

**디버깅 명령:**
```bash
bluealsa-aplay -L           # BlueALSA가 노출하는 PCM 디바이스 목록
journalctl -u bluealsa.service --no-pager | tail -30
systemctl status bluealsa.service --no-pager
```

---

### Stage 3 — bluealsa-aplay (virtual PCM → ALSA loopback write)

**무엇을 하나:** `audio-bridge.sh`가 `bluealsa-aplay`를 실행하여 BlueALSA virtual PCM 스트림을 읽고, ALSA loopback 카드의 playback 서브디바이스(`hw:Loopback,0`)에 PCM 데이터를 쓴다. 이 브릿지가 A2DP와 loopback 사이의 연결 고리이다.

**어떤 패키지/모듈:** `bluealsa` 패키지의 `bluealsa-aplay` 바이너리.

**어떤 설정 파일/서비스:**
- `scripts/audio-bridge.sh` — `bluealsa-aplay` 실행 래퍼 (`/opt/bt2iap/scripts/`에 설치).
- `systemd/audio-bridge.service` — 부팅 후 자동 실행 (`/etc/systemd/system/`에 설치).

**디버깅 명령:**
```bash
systemctl status audio-bridge.service --no-pager
journalctl -u audio-bridge.service --no-pager | tail -30
# bluealsa-aplay 직접 실행 (수동 테스트):
bluealsa-aplay -D hw:Loopback,0 --keep-alive=5
```

---

### Stage 4 — ALSA loopback (snd-aloop)

**무엇을 하나:** `snd-aloop` 커널 모듈이 가상의 loopback ALSA 카드를 생성한다. playback 서브디바이스(`hw:Loopback,0`)에 쓰인 PCM 데이터가 capture 서브디바이스(`hw:Loopback,1`)에서 읽힌다. 이 loopback이 BlueALSA 출력과 iPodUSB 입력을 연결하는 중간 버퍼 역할을 한다.

**어떤 패키지/모듈:** `snd-aloop` 커널 모듈 (Raspberry Pi OS 기본 커널에 포함).

**어떤 설정 파일/서비스:**
- `/etc/asound.conf` (`alsa/asound.conf`) — `default` ALSA 디바이스를 loopback으로 지정하고, iPodUSB로의 라우팅 규칙을 정의.
- 모듈 로드: `bootstrap.sh` 또는 `/etc/modules`에 `snd-aloop` 추가.

**디버깅 명령:**
```bash
lsmod | grep snd_aloop                  # 모듈 로드 확인
aplay -l | grep -i loopback             # ALSA card 목록에서 Loopback 확인
cat /proc/asound/cards                  # 카드 번호 확인
aplay -D hw:Loopback,0 -f S16_LE -r 48000 -c 2 /dev/zero &   # 수동 write 테스트
arecord -D hw:Loopback,1 -f S16_LE -r 48000 -c 2 /tmp/test.wav &  # 수동 read 테스트
```

---

### Stage 5 — g_ipod_audio → MMCS (USB iAP)

**무엇을 하나:** `g_ipod_audio.ko` 커널 모듈이 iPodUSB라는 이름의 ALSA 카드를 노출한다. 이 카드에 들어오는 PCM 데이터는 USB gadget 레이어를 통해 iAP 오디오 스트림으로 변환되어 Outlander MMCS 헤드유닛에 전달된다. MMCS는 Pi를 Apple iPod으로 인식하고 음악 재생을 수행한다.

**어떤 패키지/모듈:** `g_ipod_audio.ko`, `g_ipod_hid.ko`, `g_ipod_gadget.ko` (`oandrew/ipod-gadget` 레포에서 빌드), `libcomposite` 커널 모듈, `dwc2` USB gadget 드라이버.

**어떤 설정 파일/서비스:**
- `scripts/load-gadget.sh` — 모듈 로드 순서 관리.
- `systemd/ipod-gadget.service` — 부팅 시 자동 로드.
- `/boot/config.txt` (`dtoverlay=dwc2`), `/boot/cmdline.txt` (`modules-load=dwc2`).

**디버깅 명령:**
```bash
aplay -l | grep -i ipodusb              # iPodUSB 카드 존재 확인
cat /proc/asound/cards                  # 카드 번호 + 이름 확인
dmesg | grep -i g_ipod_audio | tail -20
# iPodUSB 지원 샘플레이트 확인:
cat /proc/asound/card*/pcm0p/sub0/hw_params 2>/dev/null
lsmod | grep g_ipod                     # 3개 모듈 모두 로드 확인
```

---

## 4. File Map

T2에서 생성하는 artifact 전체 목록이다.

| File | Purpose | Installed to (Pi) |
|------|---------|-------------------|
| `bluetooth/main.conf.patch` | BlueZ 컨트롤러 설정 (Discoverable, Pairable, Auto-agent) | `/etc/bluetooth/main.conf` (append) |
| `bluetooth/pair-agent.sh` | 입력 없이 페어링을 수립하는 agent 래퍼 | `/opt/bt2iap/bluetooth/` (systemd unit 또는 직접 실행) |
| `systemd/bluealsa.service.d/override.conf` | BlueALSA를 A2DP sink 프로파일로 제한 | `/etc/systemd/system/bluealsa.service.d/` |
| `alsa/asound.conf` | ALSA 라우팅 (A2DP → loopback → iPodUSB) | `/etc/asound.conf` |
| `scripts/audio-bridge.sh` | bluealsa-aplay 루프 러너 | `/opt/bt2iap/scripts/` |
| `systemd/audio-bridge.service` | audio-bridge.sh의 systemd 래퍼 | `/etc/systemd/system/` |
| `scripts/verify-audio.sh` | T2 오디오 경로 헬스체크 스크립트 | `/opt/bt2iap/scripts/` |

---

## 5. Failure Modes

### 차량 스피커에서 소리가 안 나오는데 폰은 연결됨으로 표시될 때

1. `aplay -l`로 iPodUSB 카드가 존재하는지 확인:
   ```bash
   aplay -l | grep -i iPodUSB
   ```
   없으면 `g_ipod_audio.ko`가 로드되지 않은 것 → T1 `load-gadget.sh`부터 재점검.

2. `dmesg`에서 g_ipod_audio 관련 메시지 확인:
   ```bash
   dmesg | grep -i g_ipod_audio | tail -20
   ```

3. audio-bridge.service가 실제로 실행 중인지 확인:
   ```bash
   systemctl status audio-bridge.service --no-pager
   journalctl -u audio-bridge.service --no-pager | tail -30
   ```

---

### 폰이 페어링을 거부할 때

```bash
bluetoothctl show   # Powered: yes, Discoverable: yes, Pairable: yes 모두 필요
```

컨트롤러가 꺼져 있으면: `bluetoothctl power on && bluetoothctl discoverable on && bluetoothctl pairable on`

pair-agent.sh가 실행 중인지 확인. agent 없이는 PIN 확인 단계에서 자동 수락이 안 된다.

---

### bluealsa-aplay가 크래시될 때

upstream에 알려진 이슈이다. `audio-bridge.sh`에서 `--keep-alive=5` 플래그를 추가한 후 audio-bridge.service를 재시작:

```bash
systemctl restart audio-bridge.service
journalctl -u audio-bridge.service -f
```

---

### 연결은 되는데 소리가 찌그러지거나 노이즈가 낄 때

샘플레이트 불일치가 원인일 가능성이 높다. BlueALSA는 보통 44100 Hz 또는 48000 Hz로 스트리밍하는데, iPodUSB 카드가 지원하는 레이트와 다를 경우 왜곡이 발생한다.

```bash
# iPodUSB 카드가 지원하는 파라미터 확인:
cat /proc/asound/card*/pcm0p/sub0/hw_params 2>/dev/null

# BlueALSA 현재 스트림 포맷 확인:
bluealsa-aplay -L
```

`/etc/asound.conf`의 `rate` 설정과 `audio-bridge.sh`의 `--rate` 플래그를 iPodUSB 지원 레이트에 맞게 조정한 후 서비스 재시작.

---

## 6. Policy Reminder — Auth Error 발생 시

`dmesg`에서 "Authentication failed", "Host rejected iPod", "iAP auth error" 류 메시지가 나타날 경우, **FM transmitter로 우회하지 말 것.** 사용자 정책 2026-04-19에 의해 명시적으로 금지된 경로이다.

대신 T3 문서로 이동하여 다음 순서를 따른다:

1. `docs/research-ipod-gadget.md`의 product_id 후보를 Tier A → B → C → D 순서로 전수 소진 (`scripts/product-id-loop.sh` 활용).
2. MFi 인증 칩 브레이크아웃 feasibility 검토 (회로/드라이버 수준, 실제 구매 없이 문서 단계까지).
3. `oandrew/ipod-gadget` 이슈 및 포크 스캔 (특히 #28, #34, #36).
4. iAP 프로토콜 역공학 방향 노트 (최후 수단).

상세 절차: `docs/iap-auth-deep-dive.md` (T3 완료 후 생성).
