# T1 Verification Checklist (Pi 하드웨어 도착 후)

T1의 목표는 **"ipod-gadget 커널 모듈이 Pi Zero 2 W에서 정상 로드되고, PC에 꽂았을 때 Apple iPod로 열거된다"** 까지이다. 차량 실제 연결 이전 단계까지만 다룬다.

- 프로젝트 루트: `/Users/2026editor/Documents/proj/bt2iap` (Mac 쪽)
- Pi 쪽 작업 디렉토리 제안: `/opt/bt2iap/` (scripts, logs), `/opt/bt2iap/vendor/ipod-gadget/` (upstream clone)
- 관련 문서: `/Users/2026editor/Documents/proj/bt2iap/docs/research-ipod-gadget.md` (product_id 튜닝 원전)
- 실패 모드 triage 원본: `/Users/2026editor/Documents/proj/bt2iap/CLAUDE.md` §"Known failure modes"

각 Step은 **커맨드 → 기대 출력 → 실패 시 대응** 3단 구조로 작성한다. Step 1→8 순서대로 진행하며, 한 단계라도 실패하면 해당 단계의 troubleshooting을 해결하기 전까지 다음 단계로 넘어가지 말 것.

---

### Step 1 — Boot sanity (커널/아키텍처 확인)

```bash
uname -a
uname -m
cat /etc/os-release | grep -E '^(NAME|VERSION)='
```

**Expected output**

```
Linux raspberrypi 6.12.XX-v8+ #1 SMP PREEMPT ... aarch64 GNU/Linux
aarch64
NAME="Raspberry Pi OS"
VERSION="12 (bookworm)"
```

`aarch64` (= 64-bit ARM) 및 커널 버전이 `6.12.34` 이상이면 이상적 (`research-ipod-gadget.md` §3 첫 번째 caveat 참조).

**Troubleshooting:** `aarch64`가 아니라 `armv7l`/`armv6l`로 나오면 Imager에서 32-bit 이미지를 구운 것이다. 64-bit Lite로 재플래시할 것. 커널이 6.12 미만이면 `sudo apt update && sudo apt full-upgrade && sudo reboot` 후 재확인.

---

### Step 2 — dwc2 overlay 로드 확인

```bash
lsmod | grep dwc2
```

**Expected output**

```
dwc2                  XXXXXX  0
```

(모듈명 `dwc2`가 한 줄 이상 나와야 한다. 의존 모듈 카운트가 0이어도 정상.)

**Troubleshooting:** 빈 출력이 나오면 `/boot/config.txt`에 `dtoverlay=dwc2`가 빠졌거나, `/boot/cmdline.txt`의 `rootwait` 직후에 `modules-load=dwc2`가 추가되지 않은 상태. `boot/config.txt.patch`와 `boot/cmdline.txt.patch`를 재적용하고 reboot. Pi의 "USB" 포트(데이터)와 "PWR" 포트(전원 전용)를 혼동한 것은 아닌지도 확인할 것 — 데이터 포트에서만 gadget 모드가 동작한다.

---

### Step 3 — libcomposite 로드 확인

```bash
sudo modprobe libcomposite
lsmod | grep libcomposite
```

**Expected output**

```
libcomposite           XXXXXX  3 usb_f_acm,usb_f_ecm,usb_f_rndis
```

의존 모듈 카운트는 시스템별로 다를 수 있다 (0 이상이면 OK).

**Troubleshooting:** `modprobe: FATAL: Module libcomposite not found` → 현재 부팅된 커널과 `raspberrypi-kernel-headers` 패키지 버전이 어긋난 경우가 많다. `sudo apt install --reinstall raspberrypi-kernel raspberrypi-kernel-headers` 후 reboot.

---

### Step 4 — ipod-gadget 모듈 3종 로드 확인

```bash
sudo /opt/bt2iap/scripts/load-gadget.sh
lsmod | grep -E 'g_ipod'
```

**Expected output** — 3개의 모듈이 모두 나와야 한다.

```
g_ipod_gadget          XXXXXX  0
g_ipod_hid             XXXXXX  1 g_ipod_gadget
g_ipod_audio           XXXXXX  1 g_ipod_gadget
```

로드 순서는 `load-gadget.sh` 내부에서 `g_ipod_audio.ko` → `g_ipod_hid.ko` → `g_ipod_gadget.ko` 순으로 `insmod`한다 (순서 중요, CLAUDE.md의 Planned build/run 섹션 참조).

**Troubleshooting:**
- `insmod: ERROR: could not insert module ...: Invalid module format` → 빌드 시점과 현재 커널이 다르다. `/opt/bt2iap/vendor/ipod-gadget/gadget/`에서 `make clean && make` 재실행.
- `Unknown symbol in module` → libcomposite가 선 로드되지 않은 상태. Step 3를 다시 통과시킬 것.
- 한 모듈이라도 빠진 채 진행하면 다음 Step의 `/dev/iap0`이 절대 생성되지 않는다. 반드시 3개 전부 확인.

---

### Step 5 — `/dev/iap0` 생성 확인

```bash
ls -l /dev/iap0
dmesg | grep -i iap | tail -20
```

**Expected output**

```
crw------- 1 root root 511, 0 <date> /dev/iap0
```

dmesg 말미에 `ipod iap: created character device iap0` 류의 라인이 나와야 한다.

**Troubleshooting:**
- 파일이 없다 → Step 4의 3개 모듈 중 `g_ipod_gadget`이 실제로는 실패 로드된 상태. `dmesg | tail -50`으로 실패 원인을 확인.
- dmesg에 `Authentication failed` / `Host rejected iPod` 류 메시지가 있다 → **Step 8로 점프. FM transmitter로 pivot하지 말 것.**
- 파일은 있는데 퍼미션이 특이하다 → udev 룰 충돌 가능. 일단 Step 6으로 진행.

---

### Step 6 — PC/Mac 열거 테스트 (차량 연결 전 사전 검증)

Pi와 Mac/PC를 Pi의 **데이터 USB 포트** (Pi Zero 2 W의 "USB" 레이블) ↔ Mac/PC의 USB-A 포트로 연결.

Mac 측에서 실행:

```bash
# macOS
system_profiler SPUSBDataType | grep -A 4 -iE 'apple|ipod'
```

또는 Linux 호스트에서 실행:

```bash
lsusb -v 2>/dev/null | grep -E 'idVendor|idProduct|iManufacturer|iProduct' | head -20
lsusb | grep -i apple
```

**Expected output** — Vendor `0x05ac` (Apple, Inc.) + Product string에 `iPod` 포함.

```
Bus 001 Device 00X: ID 05ac:1297 Apple, Inc. iPhone 4
```

(Product ID는 `scripts/load-gadget.sh`에서 지정한 값에 따라 달라진다. 중요한 것은 **Vendor가 05ac이고 Product 문자열에 "iPod"나 "iPhone"이 잡힌다**는 사실.)

**Troubleshooting:**
- PC에서 아예 디바이스가 보이지 않는다 → Pi의 USB 포트를 "PWR" 쪽에 꽂은 것 아닌지 확인 (PWR는 전원 전용이라 데이터가 안 나간다). 케이블도 데이터 지원 케이블인지 확인 (충전 전용 케이블 주의).
- Vendor가 05ac이 아니다 → Step 4의 `g_ipod_gadget` 로드가 불완전한 상태. Step 4부터 재시도.
- Vendor는 맞는데 Product 문자열이 이상하다 → 기본 product_id 그대로일 가능성. `scripts/product-id-loop.sh`로 후보 ID 순환 시도. 후보 전체 목록은 `/Users/2026editor/Documents/proj/bt2iap/docs/research-ipod-gadget.md` §2.1 참조.

---

### Step 7 — systemd unit healthy

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ipod-gadget.service
systemctl status ipod-gadget.service --no-pager
journalctl -u ipod-gadget.service --no-pager | tail -30
```

**Expected output**

```
● ipod-gadget.service - iPod USB Gadget Loader
     Loaded: loaded (/etc/systemd/system/ipod-gadget.service; enabled; ...)
     Active: active (exited) since ...
```

`Active: active (exited)` 또는 `active (running)` 둘 다 정상 (oneshot 유형이면 exited, forking 유형이면 running).

**Troubleshooting:**
- `Active: failed` → `journalctl -u ipod-gadget.service -xe`로 실패 원인 확인. 대부분은 `load-gadget.sh` 내부의 insmod 실패이므로 Step 4부터 수동 재현하여 원인을 좁힌다.
- `Loaded: bad-setting` → 유닛 파일 문법 오류. Mac 쪽에서 `make check-t1`의 systemd 유닛 linting 게이트에 걸렸어야 하므로, `systemd/ipod-gadget.service`를 다시 검사.
- **reboot 후에도 동일 상태를 재현할 수 있는지 반드시 확인.** 수동 `insmod`만 되고 `systemctl enable`이 안 되면 운전 중 문제 복구가 불가능하다.

---

### Step 8 — 실패 시 분기점 (auth error 계열)

Step 5-7 진행 중 dmesg에 **"Authentication failed"**, **"Host rejected iPod"**, **"iAP auth error"** 류 메시지가 출현하면:

```bash
dmesg | grep -iE 'auth|reject|iap|05ac' | tail -40
sudo journalctl -k --no-pager | grep -iE 'auth|reject|iap' | tail -40
```

결과를 캡처하고, **T3 iap-auth-deep-dive 단계로 이동**한다 (`/Users/2026editor/Documents/proj/bt2iap/docs/iap-auth-deep-dive.md`, T3 완료 후 생성될 파일).

**절대 금지:**

- **FM transmitter 우회 pivot 금지.** 사용자 정책 2026-04-19에 의해 명시적으로 거부됨 (`/Users/2026editor/Documents/proj/bt2iap/CLAUDE.md` §"Scope discipline" + 스펙 `/Users/2026editor/Documents/proj/bt2iap/.omc/specs/deep-interview-pre-pi-prep.md` §Non-Goals).
- Step 6에서 Vendor/Product가 어쨌든 보이기만 하면 Step 5의 auth error는 **차량 헤드유닛이 내뱉는 것이 아니라 Pi 쪽 initiator 인증일 가능성**도 있으니 dmesg 메시지 전문을 T3로 전달할 때 생략하지 말고 포함할 것.

**T3 진입 시 수행할 작업 순서 (요약, 상세는 T3 문서에서):**

1. `/Users/2026editor/Documents/proj/bt2iap/docs/research-ipod-gadget.md` §2.2의 Tier A → B → C → D 순으로 product_id 전수 소진.
2. MFi 인증 칩 브레이크아웃 feasibility 조사 (하드웨어 구매 없이 문서 단계까지).
3. `oandrew/ipod-gadget` 이슈/포크 스캔, 특히 #28 (Pi Zero 2W) / #34 (와이어링) / #36 (Cooper F56 caveats).
4. iAP 프로토콜 역공학 방향 노트 (최후 수단).

---

## 부록: 빠른 재부팅 체크리스트

Pi를 껐다 켠 후 이 순서로 한 번만 훑으면 T1 회귀 테스트가 끝난다.

```bash
uname -m                                        # aarch64 확인
lsmod | grep -E 'dwc2|libcomposite|g_ipod'      # 4~5줄 나오면 OK
ls /dev/iap0                                    # 파일 존재
systemctl is-active ipod-gadget.service         # active
```

네 줄이 모두 통과하면 T1 합격. T2 오디오 경로 검증으로 이동.
