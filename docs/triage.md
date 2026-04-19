# T3 Triage Runbook — 4대 failure mode 통합 점검표

Pi 하드웨어 도착 후 실제 차량·벤치 테스트에서 마주칠 수 있는 **4대 failure mode**를 한 장으로 정리한 문서다. `CLAUDE.md` §"Known failure modes"가 원전이고, 본 문서는 각 failure mode를 **증상 / 원인 / 확인 명령 / 조치 / 에스컬레이션** 5단 구조로 확장한다.

- 원전(Origin): `/Users/2026editor/Documents/proj/bt2iap/CLAUDE.md` §"Known failure modes"
- 보조 레퍼런스:
  - `/Users/2026editor/Documents/proj/bt2iap/docs/research-ipod-gadget.md` (product_id tiering + upstream caveats)
  - `/Users/2026editor/Documents/proj/bt2iap/docs/verification-t1.md` (T1 검증 Step 1~8)
  - `/Users/2026editor/Documents/proj/bt2iap/docs/audio-topology.md` (T2 오디오 경로 stage 분해)
  - `/Users/2026editor/Documents/proj/bt2iap/docs/iap-auth-deep-dive.md` (auth error 심층 runbook, 본 문서의 에스컬레이션 대상)

**정책 리마인더 (2026-04-19 고정):** auth 에러가 나더라도 FM transmitter로 우회하지 **않는다**. 사용자 명시 정책이며, `.omc/specs/deep-interview-pre-pi-prep.md` §Non-Goals 및 `CLAUDE.md` §"Scope discipline"에 명문화되어 있다. 본 문서의 failure mode #1 섹션에 해당 규칙이 재명시된다.

---

## 0. At-a-glance matrix

빠르게 어떤 failure mode에 해당하는지 분류하기 위한 1-line 표다. 상세 진단은 각 섹션 본문을 따른다.

| # | Symptom summary | Confirm command (one-liner) | Primary fix | Escalation |
|---|-----------------|-----------------------------|-------------|------------|
| 1 | dmesg에 auth/reject 계열 메시지 | `dmesg \| grep -iE 'auth\|reject\|iap'` | product_id 소진 (`scripts/product-id-loop.sh`) | `docs/iap-auth-deep-dive.md` Stage 1 |
| 2 | MMCS가 디바이스는 보지만 재생 안 됨 | `lsusb -v \| grep -E 'idVendor\|idProduct\|iProduct'` | Tier A/B product_id 순환 (재생까지 확인) | `docs/iap-auth-deep-dive.md` Stage 1 종료 후 Stage 2~3 |
| 3 | Pi가 차량 연결 시 boot-loop / 재부팅 반복 | `journalctl -b -1 --no-pager \| tail -50` (직전 boot) + 카메라로 LED 관찰 | 2A+ 시가 차저 전원 교체, 차량 USB-A는 data-only로 분리 | 전원 안정화 후 재현되면 §3 본문의 hardware side-check |
| 4 | 폰 연결은 되는데 스피커에서 소리 없음 / 찌그러짐 | `aplay -l`, `systemctl status audio-bridge.service` | BlueALSA→aloop→iPodUSB 체인을 stage별로 분해 점검 | `docs/audio-topology.md` §5 Failure Modes 후 필요 시 §3 (전원) |

---

## 1. Failure mode #1 — dmesg에 authentication error

### Symptom (증상)

Pi를 차량 USB-A에 연결한 뒤 `dmesg`를 보면 아래 패턴 중 하나가 출력된다.

```
[  123.456] iap0: Authentication failed
[  124.012] g_ipod_gadget: Host rejected iPod
[  124.234] ipod iAP: auth error, session terminated
```

MMCS UI에서는 보통 "USB 기기 인식 실패", "지원하지 않는 기기", 또는 아이콘만 잠깐 떴다가 바로 사라지는 거동이 관측된다. 차량에 따라 "iPod" 아이콘이 표시되었다가 수 초 내에 사라진다.

### Likely cause (원인)

Outlander MMCS가 iAP 세션에 대해 **MFi(Made-For-iPod) hardware 인증을 실제로 요구**하는 상태다. `CLAUDE.md`의 "MFi auth는 loose할 것이다"라는 전제가 깨진 케이스로, 업스트림 `oandrew/ipod-gadget` README 말미의 경고(`currently it works only if the host device doesn't authenticate the iPod`)와 정확히 맞물린다.

동시에 이 증상은 **product_id 불일치로 인한 초기 enumeration 거부**와 증상이 비슷하게 보일 수 있기 때문에, auth error처럼 보여도 먼저 product_id 후보부터 소진하는 것이 올바른 순서다(`iap-auth-deep-dive.md` Stage 1 참조).

### Confirm command (확인 명령)

```bash
dmesg | grep -iE 'auth|reject|iap|05ac' | tail -40
sudo journalctl -k --no-pager | grep -iE 'auth|reject|iap' | tail -40
```

추가로 USB 디스크립터가 어떻게 노출됐는지 확인:

```bash
lsusb -v 2>/dev/null | grep -E 'idVendor|idProduct|iManufacturer|iProduct' | head -20
```

Vendor가 `0x05ac`으로 나오지만 Product 문자열이 `iPod`/`iPhone`이 아닌 경우, auth error 이전에 product_id 문제일 가능성이 크다.

### Recovery steps (조치)

**정책 재확인:** FM transmitter로 우회하지 **않는다**. 본 failure mode는 `iap-auth-deep-dive.md`로 에스컬레이션한다.

1. **dmesg 전문을 캡처한다.** `dmesg > /tmp/dmesg-auth-fail-$(date +%s).log` — 증상 스냅샷을 남기고 이후 단계에서 참조한다.
2. **product_id 후보 소진을 먼저 수행한다.** `sudo BT2IAP_INTERACTIVE=1 /opt/bt2iap/scripts/product-id-loop.sh` 를 실행해 Tier A → B → C → D 순으로 53개 후보를 시험한다. 후보 출처·Tier 정의: `docs/research-ipod-gadget.md` §2.2.
3. **product_id 소진에도 auth error가 지속되면** `docs/iap-auth-deep-dive.md` Stage 2 (MFi chip feasibility) 검토로 진입한다.
4. Stage 2가 문서 단계에서 막히면 Stage 3 (upstream issues/forks 스캔) → Stage 4 (iAP 역공학) 순으로 내려간다.

### Escalation (에스컬레이션)

- **NOT an option:** FM transmitter pivot (사용자 정책 2026-04-19 명시적 거부).
- **Jump to:** `docs/iap-auth-deep-dive.md` Stage 1 (product_id 전수 소진). Stage 1 실패 시 Stage 2~4 순차 진행.

---

## 2. Failure mode #2 — MMCS가 디바이스는 보지만 재생 안 됨

### Symptom (증상)

MMCS UI에 "iPod" 또는 "USB 기기" 아이콘이 표시되고 사라지지 않는다. 그러나:

- 재생 버튼을 눌러도 반응이 없거나 "곡을 읽어오는 중" 상태에서 멈춘다.
- 트랙 리스트가 비어 있거나 "파일 없음" 류 메시지가 뜬다.
- dmesg에는 auth 계열 에러가 **없다**.

업스트림에서 우리와 정확히 같은 이슈가 보고된 바 있다: [oandrew/ipod-gadget#17 "Mitsubishi detects iPod, but doesn't play audio"](https://github.com/oandrew/ipod-gadget/issues/17). 반드시 읽어두기.

### Likely cause (원인)

**MMCS가 기대하는 iPod 세대의 product_id와 우리가 주입한 값이 불일치**한다. 이 head unit 세대(2007~2012)는 iPod Classic / Nano 2~5세대를 주 타깃으로 설계됐기 때문에, README 예시값인 `0x1297`(iPhone 4)이 반드시 먹힌다는 보장이 없다. `CLAUDE.md` 및 `research-ipod-gadget.md` §2.2 Tier A가 가리키는 `0x1261` (iPod Classic 2007) 주변이 우선 탐색 영역이다.

### Confirm command (확인 명령)

```bash
# 현재 디바이스가 어떤 Apple product_id로 노출되는지
lsusb -v 2>/dev/null | grep -E 'idVendor|idProduct|iManufacturer|iProduct' | head -20

# dmesg에 auth 계열은 없고 단순히 세션만 살아 있는지 확인
dmesg | grep -i iap | tail -20

# MMCS 재생 시도 중 dmesg에 특이 에러가 나는지 관찰
sudo dmesg -W
```

`dmesg -W` 상태에서 차량 UI에서 재생을 눌렀을 때 추가 로그가 찍히지 않으면 MMCS 쪽에서 silent reject 중인 것이고, 이는 product_id 탐색으로 풀어야 한다.

### Recovery steps (조치)

1. **`scripts/product-id-loop.sh`를 interactive 모드로 실행한다.**
   ```bash
   sudo BT2IAP_INTERACTIVE=1 /opt/bt2iap/scripts/product-id-loop.sh
   ```
   각 후보에 대해 MMCS UI에서 실제 재생을 시도해보고, 소리가 나는 후보가 등장하면 `y`로 답해 종료한다.
2. Tier A (`0x1261` / `0x1260` / `0x1262` / `0x1263` / `0x1265`)를 우선 시도한다. 2007~2009년식 iPod Classic/Nano는 Outlander MY 범위와 정확히 매칭된다.
3. Tier A에서 승자가 없으면 Tier B → C → D 순으로 넘어간다. 사용자 정책상 **44개 유효 후보(DFU/WTF 제외)를 전수 소진**할 때까지는 auth deep dive 단계로 올리지 않는다.
4. 승자 발견 시 product_id를 고정:
   ```bash
   sudo /opt/bt2iap/scripts/load-gadget.sh --product-id=0x1261  # 예시
   ```
   이후 `systemd/ipod-gadget.service`에 `PRODUCT_ID=0x1261`을 환경으로 박아 재부팅 시에도 유지되도록 한다.

### Escalation (에스컬레이션)

- 44개 후보 전부 실패 → `docs/iap-auth-deep-dive.md` Stage 1의 "failure criterion"에 해당. Stage 2 (MFi chip) 진입.
- 일부 후보에서 MMCS가 "iPod"으로 잡히지만 여전히 재생 불가 → **이 시점부터는 auth 계열 failure로 재분류한다.** iAP 핸드셰이크 후반부에서 MFi가 요구되는 흐름일 가능성이 있다. `iap-auth-deep-dive.md` Stage 2로 이동.

---

## 3. Failure mode #3 — Pi가 차량 연결 시 boot-loop / 재부팅 반복

### Symptom (증상)

엔진 시동 후 Pi의 전원 LED가:

- 반복적으로 꺼졌다 켜졌다 한다 (boot-loop).
- 켜졌지만 activity LED가 거의 안 깜빡이고 SSH도 안 들어온다 (under-voltage 제한 걸린 상태).
- 30초~1분 뒤에 자동 재부팅이 반복된다.

Outlander 차량 USB-A는 **데이터 + 제한된 전원(1A 미만)** 을 공급하는 포트로, Pi Zero 2 W가 부팅 중 피크 전류를 끌어올 때 전압이 drop 하면서 일어나는 전형적인 증상이다.

### Likely cause (원인)

차량 USB-A 포트의 전원 용량 부족. Pi Zero 2 W는 peak ~1A를 쓸 수 있고, 특히 Wi-Fi/Bluetooth가 동시에 동작할 때 전류 스파이크가 발생한다. 차량 포트가 정격 1A 미만이면 under-voltage throttling → kernel panic → reboot 사이클이 돈다. `CLAUDE.md` §"Known failure modes" #3 및 `.omc/specs/deep-interview-pre-pi-prep.md` §"Technical Context"에도 명시되어 있다.

### Confirm command (확인 명령)

```bash
# 직전 부팅 로그에서 under-voltage / throttle 흔적 확인
vcgencmd get_throttled
journalctl -b -1 --no-pager | tail -100

# 커널 under-voltage 경고
dmesg | grep -iE 'under-voltage|throttle|voltage'
```

`vcgencmd get_throttled`의 반환값 해석:

| Hex value | 의미 |
|-----------|------|
| `0x0` | 문제 없음 |
| `0x50000` | 현재 under-voltage 발생 중 또는 과거에 발생 |
| `0x50005` | 현재 진행 중인 under-voltage + throttle |

값이 `0x0`이 아니면 전원 문제로 거의 확정.

### Recovery steps (조치)

1. **2A+ 시가 차저로 전원을 분리한다.** 차량 USB-A에서 데이터만 받고, 전원은 차량 시가잭 → 2A 이상 출력 USB 차저 → Pi의 PWR 포트 (micro-USB 전원 전용 포트)로 공급한다. Pi Zero 2 W의 "USB" 포트가 데이터, "PWR" 포트가 전원 전용임을 혼동하지 말 것.
2. **차량 USB-A에서 Pi로 가는 케이블의 VBUS 라인을 끊는다** (data-only 케이블 사용 또는 5V 라인을 물리적으로 커팅). 그러지 않으면 차량 포트와 시가 차저 두 소스가 VBUS에서 충돌한다.
3. 재부팅 후 `vcgencmd get_throttled` 로 `0x0`이 유지되는지 5~10분 주행 테스트로 확인.
4. 여전히 재부팅이 나면: **(a)** 시가 차저의 실제 출력 전류 측정(2A 이상 보장), **(b)** micro-USB 케이블을 굵은 게이지(AWG 22 이하)로 교체, **(c)** SD 카드를 수명이 남은 것으로 교체(파일시스템 파손이 kernel panic으로 이어질 수 있음).

### Escalation (에스컬레이션)

- 전원 교체 후에도 boot-loop 지속 → 하드웨어 문제 가능성. SD 카드 재플래시 + Pi 본체 교체를 고려. `docs/verification-t1.md` Step 1~3 (boot sanity)부터 다시 통과시키기.
- 전원은 안정인데 연결 시에만 재부팅 → USB 데이터 라인 short 가능성. 데이터 케이블을 교체하고 Pi의 USB 데이터 포트와 차량 포트 사이에 직결이 아닌 인라인 USB 테스터(voltage/current 측정 가능 모델)를 넣어 스파이크 관찰.

---

## 4. Failure mode #4 — 폰 연결은 되는데 스피커에서 소리 없음 / 찌그러짐

### Symptom (증상)

스마트폰에서 Pi로의 Bluetooth 페어링/연결은 정상이고 MMCS도 iPod로 인식했지만:

- 스피커에서 소리가 전혀 안 난다.
- 소리가 나지만 심하게 찌그러지거나 노이즈가 낀다.
- 재생 시작 직후에만 잠깐 들리고 곧 끊긴다.

phone UI에서는 "출력 장치: bt2iap(또는 라즈베리파이 이름)" 으로 표시되어 있다.

### Likely cause (원인)

오디오 경로 여러 stage 중 어느 하나가 끊겨 있거나 샘플레이트 mismatch가 발생한 상태다. BlueALSA → ALSA loopback(snd-aloop) → g_ipod_audio(iPodUSB) → USB 의 4단 체인 중 어느 구간이 문제인지 stage별로 좁혀야 한다. 원전 토폴로지: `docs/audio-topology.md` §2 "End-to-end Diagram".

### Confirm command (확인 명령)

```bash
# Stage 5: iPodUSB 카드 존재 확인
aplay -l | grep -iE 'iPodUSB|Loopback'
cat /proc/asound/cards

# Stage 1-2: Bluetooth 페어링 및 BlueALSA 상태
bluetoothctl show
systemctl status bluealsa.service --no-pager
bluealsa-aplay -L

# Stage 3-4: audio-bridge + loopback 상태
systemctl status audio-bridge.service --no-pager
journalctl -u audio-bridge.service --no-pager | tail -30
lsmod | grep snd_aloop

# 샘플레이트 확인 (찌그러짐 계열일 때 필수)
cat /proc/asound/card*/pcm0p/sub0/hw_params 2>/dev/null
```

### Recovery steps (조치)

BlueALSA → aloop → iPodUSB 체인을 **역방향(가까운 곳부터)** 으로 좁히는 것이 효율적이다.

1. **iPodUSB 카드가 실제로 존재하는지 먼저 확인한다.**
   ```bash
   aplay -l | grep -i iPodUSB
   ```
   없으면 `g_ipod_audio.ko`가 로드되지 않은 것. `docs/verification-t1.md` Step 4부터 재점검(`load-gadget.sh` 실패 가능성). 이 경우는 T2가 아니라 T1 회귀.
2. **snd-aloop 카드가 존재하는지 확인한다.**
   ```bash
   aplay -l | grep -i Loopback
   lsmod | grep snd_aloop
   ```
   없으면 `sudo modprobe snd-aloop` + `/etc/modules`에 `snd-aloop` 추가로 영구 로드.
3. **audio-bridge.service가 살아있는지 확인한다.**
   ```bash
   systemctl status audio-bridge.service --no-pager
   ```
   `Active: failed` 이면 `journalctl -u audio-bridge.service --no-pager | tail -50` 로 실패 원인 확인. `bluealsa-aplay`가 크래시하는 것이 알려진 상층 이슈이며, `--keep-alive=5` 플래그가 `scripts/audio-bridge.sh` 에 들어있는지 확인(`docs/audio-topology.md` §5 참조).
4. **BlueALSA 자체의 상태를 확인한다.**
   ```bash
   bluealsa-aplay -L
   systemctl status bluealsa.service --no-pager
   ```
   가상 PCM 디바이스 목록이 비어 있으면 A2DP 프로파일이 제대로 활성화되지 않았거나 페어링이 풀린 상태. `bluetoothctl connect <MAC>` 재시도 후 재확인.
5. **샘플레이트 mismatch(찌그러짐 증상)**: iPodUSB가 지원하는 레이트와 BlueALSA 출력 레이트가 다르면 왜곡 발생.
   ```bash
   cat /proc/asound/card*/pcm0p/sub0/hw_params 2>/dev/null  # iPodUSB 지원 범위
   ```
   `/etc/asound.conf`의 `rate` 와 `scripts/audio-bridge.sh`의 `--rate` 플래그를 일치시킨다(보통 44100 또는 48000).
6. **PulseAudio/PipeWire 충돌 확인.** Pi OS 최신 버전은 PipeWire를 기본 탑재할 수 있는데, BlueALSA와 PipeWire가 동시에 블루투스 오디오를 점유하면 경로가 꼬인다:
   ```bash
   systemctl --user status pipewire pipewire-pulse 2>/dev/null
   systemctl --user status pulseaudio 2>/dev/null
   ```
   둘 다 활성화돼 있으면 BlueALSA와 경합 중. BlueALSA를 쓰는 본 프로젝트에서는 PipeWire/PulseAudio를 비활성화한다(`systemctl --user mask pipewire pipewire-pulse`).

### Escalation (에스컬레이션)

- Stage 1~5 전부 정상인데 여전히 소리 없음 → iAP 오디오 세션 자체가 MMCS 쪽에서 활성화되지 않은 것일 수 있다. 이 경우 failure mode #2와 증상이 겹치므로 **#2 경로(product_id 재탐색)** 로 재분류해 조치한다.
- 전원 여유 부족으로 오디오가 간헐적으로 끊기는 경우도 관측됨 → §3 (failure mode #3) side-check. `vcgencmd get_throttled` 가 `0x0`이 아닌지 확인.
- 체계적 로그 수집이 필요하면 `scripts/collect-diagnostics.sh` 를 돌려 번들을 만들고, 번들을 읽으며 `docs/audio-topology.md` §3 Stage-by-stage 설명과 대조한다.

---

## 5. Policy reminder — FM transmitter는 선택지가 아니다

본 문서의 모든 failure mode, 특히 **#1 (auth error)** 는 "막히면 FM transmitter로 우회"라는 선택지를 **명시적으로 거부**한다. 사용자 정책(2026-04-19)으로 고정된 내용이며:

- `CLAUDE.md` §"Scope discipline"에 재명시됨.
- `.omc/specs/deep-interview-pre-pi-prep.md` §Non-Goals에 "FM transmitter로 우회 (사용자 명시적 거부 2026-04-19 — iAP로만 완주)"로 박혀 있음.

따라서 #1 (auth error) 또는 #2 (재생 불가)가 product_id 소진으로도 해결되지 않을 때의 경로는 단 하나다:

> `docs/iap-auth-deep-dive.md` Stage 1 → Stage 2 → Stage 3 → Stage 4 (순차 심화)

Stage 4 (iAP 프로토콜 역공학)가 본 프로젝트의 iAP 기반 해결 경로의 end-of-line이다.
