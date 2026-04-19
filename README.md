# bt2iap

*한국어* · [English](README.en.md)

Bluetooth-to-iAP 브릿지: 라즈베리파이 Zero 2 W가 iPod인 척 USB로 연결돼서, 폰 A2DP 오디오를 2007-2012 미쓰비시 아웃랜더 MMCS 헤드유닛으로 넘겨주는 장치.

## 아키텍처

```
[Phone] --BT A2DP--> [Pi Zero 2 W] --USB iAP--> [Outlander USB-A]
                                                         |
                                        MMCS가 iPod으로 인식
```

Pi는 `ipod-gadget` 커널 모듈을 통해 USB gadget mode(`dwc2`)로 Apple iPod처럼 보인다. 오디오는 Bluetooth A2DP(BlueALSA)로 수신되어, ALSA loopback을 거쳐 `g_ipod_audio.ko`가 노출하는 `iPodUSB` ALSA 카드로 전달된다.

## 현재 상태

T1(gadget boot) / T2(audio path) / T3(iAP deep recovery runbook) / T4(extension research) — 네 tier 전부 완료. Pi Zero 2 W 하드웨어 도착 대기 중.

## 하드웨어

- **Pi:** Raspberry Pi Zero 2 W, Raspberry Pi OS Lite 64-bit, 헤드리스 (Imager로 Wi-Fi + SSH 사전 설정)
- **차량:** 미쓰비시 아웃랜더 2007-2012, MMCS 헤드유닛, USB-A 포트 (iPod 전용, iAP 프로토콜)
- **전원 주의:** 차량 USB-A는 1A 미만이다. Pi 전원은 2A+ 시가잭 USB 차저에서 공급하고, 헤드유닛에서는 데이터 라인만 연결할 것.

## 레포 구조

```
bt2iap/
|-- scripts/       # Pi에서 돌리는 자동화 (bootstrap, gadget load, product_id 루프,
|                  #   audio bridge, verify-audio, collect-diagnostics)
|-- systemd/       # /etc/systemd/system/에 설치되는 unit 파일 (+ drop-in override)
|-- boot/          # /boot/config.txt · /boot/cmdline.txt 패치
|-- bluetooth/     # BlueZ 설정 패치 + 페어링 에이전트 스크립트
|-- alsa/          # ALSA 라우팅 설정 (A2DP sink -> loopback -> iPodUSB)
|-- docs/          # 리서치 노트, 검증 체크리스트, 오디오 토폴로지 다이어그램,
|                  #   triage 매트릭스 (triage.md), iAP auth deep-dive (iap-auth-deep-dive.md),
|                  #   iAP 메시지 프로토콜 레퍼런스 (iap-messages.md),
|                  #   심층 디버깅 툴 카탈로그 (advanced-iap-tools.md)
|-- Makefile       # Mac 쪽 품질 게이트 (check-t1, check-t2, check-t3, check-t4)
`-- CLAUDE.md      # AI 어시스턴트용 프로젝트 컨텍스트
```

## T1 설치 (Pi에서)

```bash
# 1. 레포를 Pi의 /opt/bt2iap 아래에 clone
sudo git clone https://github.com/twinn1013/bt2iap /opt/bt2iap
cd /opt/bt2iap

# 2. bootstrap 실행 (의존성 설치, 모듈 빌드, 서비스 enable까지)
sudo ./scripts/bootstrap.sh

# 3. 재부팅
sudo reboot

# 4. 부팅 후 검증
sudo ./scripts/load-gadget.sh                           # T1 gadget 수동 sanity 체크
systemctl is-active ipod-gadget.service ipod-session.service
```

`bootstrap.sh`가 해주는 일: `apt` 의존성 (`build-essential`, `raspberrypi-kernel-headers`, `golang`, `bluez`, `bluez-tools`, `bluealsa`) 설치, `oandrew/ipod-gadget` 클론 + 커널 모듈 빌드, `oandrew/ipod` Go 클라이언트 빌드, `ipod-gadget`(커널 로더)과 `ipod-session`(userspace iAP 핸들러) systemd 유닛 **둘 다** 설치 후 `systemctl enable --now`로 기동. 실제로 iAP 세션이 활성화되려면 Go 클라이언트가 `/dev/iap0`을 여는 시점이 필요하기 때문에 두 유닛 모두 필수.

부팅 패치 (`boot/config.txt.patch`, `boot/cmdline.txt.patch`)는 재부팅 전에 반드시 적용되어야 `dwc2` gadget mode가 켜진다:

- `/boot/firmware/config.txt`(Bookworm 기준; pre-Bookworm은 `/boot/config.txt`)에 `dtoverlay=dwc2`
- `/boot/firmware/cmdline.txt`(Bookworm 기준; pre-Bookworm은 `/boot/cmdline.txt`)의 `rootwait` 직후에 `modules-load=dwc2` 삽입

`bootstrap.sh`가 Bookworm (현 Pi OS)의 `/boot/firmware/`인지 Bullseye 이전의 `/boot/`인지 자동 감지해서 존재하는 쪽을 패치한다. 둘 다 없으면 명시적으로 에러 + 종료.

### 동작하는 PRODUCT_ID 영속화

`scripts/product-id-loop.sh`로 아웃랜더 헤드유닛이 수락하는 `product_id`를 찾으면, 재부팅 후에도 유지되도록 `/etc/default/bt2iap`에 기록:

```bash
# 루프가 0x1261에서 성공했다고 가정:
sudo sed -i 's/^#\?PRODUCT_ID=.*/PRODUCT_ID=0x1261/' /etc/default/bt2iap
sudo systemctl restart ipod-gadget.service
```

`systemd/ipod-gadget.service`는 이 파일을 `EnvironmentFile=-/etc/default/bt2iap`으로 읽는다 (`-` 접두사는 "파일 없으면 조용히 넘어감" — 파일 없을 때는 모듈 빌트인 기본 `product_id` 사용).

## T1 검증

전체 체크리스트는 `docs/verification-t1.md`. 빠른 inline 점검 3종:

```bash
# 1. /dev/iap0 생성 확인
dmesg | grep iap

# 2. 커널 모듈 로드 확인
lsmod | grep ipod

# 3. ALSA 카드 존재 확인
aplay -l | grep iPodUSB
```

Pi를 차량이 아닌 일반 PC에 꽂으면 호스트의 USB 디바이스 목록에 "Apple iPod"로 열거되어야 한다.

## T2 설치 (Pi에서)

`scripts/bootstrap.sh`가 T2 설치까지 end-to-end로 처리한다. T1 이후에 별도 실행이 필요 없음 — 동일한 `sudo ./scripts/bootstrap.sh` 한 번으로 T2 산출물(BlueZ 패치, BlueALSA override, `asound.conf`, `audio-bridge`/`audio-loopback`/`pair-agent`/`ipod-session` 서비스, `modules-load.d/bt2iap.conf`)까지 설치 + systemd reload + `--now` enable까지 해준다.

설치 후 오디오 체인 검증:

```bash
sudo /opt/bt2iap/scripts/verify-audio.sh
```

수동 복사 레퍼런스 (점검 / 부분 재배포용 — bootstrap이 아래를 전부 자동으로 함):

```bash
# BlueZ config 패치 (sentinel 없으면만 append하는 멱등 방식).
# 반드시 pure-INI payload(.patch.block)를 쓸 것. Markdown .patch 문서 파일을 cat하면 안 됨.
sudo bash -c '
  block=bluetooth/main.conf.patch.block
  target=/etc/bluetooth/main.conf
  if ! grep -qF "# --- begin bt2iap ---" "$target"; then
    cat "$block" >> "$target"
  fi
'

# BlueALSA 서비스 drop-in
sudo install -D -m 0644 systemd/bluealsa.service.d/override.conf \
        /etc/systemd/system/bluealsa.service.d/override.conf

# ALSA 라우팅 설정
sudo install -D -m 0644 alsa/asound.conf /etc/asound.conf

# snd-aloop + libcomposite용 modules-load.d
sudo install -D -m 0644 modules-load.d/bt2iap.conf /etc/modules-load.d/bt2iap.conf

# T2 systemd 유닛 (audio-bridge = 1단 bridge, audio-loopback = 2단 bridge)
sudo install -m 0644 systemd/audio-bridge.service /etc/systemd/system/audio-bridge.service
sudo install -m 0644 systemd/audio-loopback.service /etc/systemd/system/audio-loopback.service
sudo install -m 0644 systemd/pair-agent.service /etc/systemd/system/pair-agent.service
sudo install -m 0644 systemd/ipod-session.service /etc/systemd/system/ipod-session.service

sudo systemctl daemon-reload
sudo systemctl enable --now bluealsa.service audio-bridge.service \
    audio-loopback.service pair-agent.service ipod-session.service
```

**두 번째 bridge(`audio-loopback.service`)가 왜 필요한지:** `asound.conf`는 `default` PCM → `aloop_playback`(loopback write 쪽)을 연결하는데, 반대쪽 capture를 읽어서 `iPodUSB`에 써주는 `alsaloop`가 없으면 오디오가 커널 loopback 버퍼 안에서 그대로 막혀버린다. 과거 리뷰에서 C1(critical)로 지적된 부분. 이 유닛은 `Requires=audio-bridge.service` + `After=audio-bridge.service`로 순서를 잡는다.

## T2 검증

전체 시그널 경로 다이어그램은 `docs/audio-topology.md`:

```
Phone --BT A2DP--> BlueALSA --> ALSA loopback (snd-aloop) --> g_ipod_audio --> USB (iPodUSB card)
```

Pi에서 각 stage가 살아있는지 확인:

```bash
sudo /opt/bt2iap/scripts/verify-audio.sh
```

스크립트는 10개 검사를 순서대로 실행한다:
1. `snd_aloop` 모듈 로드 (`lsmod | grep snd_aloop`)
2. `Loopback` 카드가 `/proc/asound/cards`에 등장
3. `iPodUSB` 카드가 `/proc/asound/cards`에 등장 (T1 `g_ipod_audio.ko` 의존)
4. `aplay -l`에 Loopback + iPodUSB 둘 다 나열
5. `/etc/asound.conf` 존재 + 비어있지 않음
6. `bluealsa.service` active
7. `bluetooth.service` active
8. `audio-bridge.service` active
9. Bluetooth 컨트롤러 전원 (`bluetoothctl show | grep "Powered: yes"`)
10. End-to-end 프로브: 1초 무음을 `default` PCM으로 전체 체인에 흘려서 ALSA 에러 없이 통과

전부 통과 시 exit 0, 하나라도 실패 시 exit 1. 추가 진단 덤프는 `--verbose`.

## T3 운영자 runbook

### 실패 triage

`docs/triage.md`가 4개 failure mode를 증상 / 확인 커맨드 / 조치 매트릭스로 다룬다:

1. 헤드유닛이 `dmesg`에 인증 에러를 던진다
2. MMCS가 디바이스는 보지만 재생이 안 된다
3. Pi가 차에서 부팅 루프
4. 오디오 경로 문제

**정책 (2026-04-19):** FM transmitter 우회(fallback)는 명시적으로 거부. 프로젝트는 iAP 완주를 목표로 한다. triage 문서가 이 정책을 반영해서 auth 실패는 FM pivot이 아니라 심층 iAP 복구 경로로 보낸다.

### 심층 auth 복구

`docs/iap-auth-deep-dive.md`는 auth 실패 시 4단계 에스컬레이션을 정리:

1. `oandrew/ipod-gadget`의 `doc/apple-usb.ids`에서 `product_id` 후보 소진
2. MFi 인증 칩 추가 feasibility (회로 + 드라이버 변경점)
3. 업스트림 `oandrew/ipod-gadget` 이슈/포크에서 알려진 auth-handshake 픽스 스캔
4. iAP 프로토콜 리버스 엔지니어링 방향 노트

### 진단 번들

버그 리포트나 장애 에스컬레이션 시, Pi에서 진단 번들 수집:

```bash
sudo /opt/bt2iap/scripts/collect-diagnostics.sh
```

수집 항목: `uname`, `os-release`, `lsmod`, `lsusb`, ALSA 카드 상태, BlueZ/BlueALSA 서비스 상태, 서비스별 `journalctl` tail, 필터된 `dmesg` — 전부 하나의 `.tar.gz`로 패킹. Bluetooth MAC은 부분 마스킹(OUI만 남기고 뒤는 X 처리). 공유 전에 Wi-Fi SSID는 직접 확인할 것.

로컬에서 뜯어보려면 `--no-tar`로 디렉토리만 풀어두기:

```bash
sudo /opt/bt2iap/scripts/collect-diagnostics.sh --no-tar
```

## T4 확장 리서치

T2가 동작하기 시작한 다음에 스티어링휠 버튼 지원, 트랙 메타데이터 표시, 또는 심층 프로토콜 분석용 하드웨어 캡처 툴을 추가하려 할 때 참고할 포워드 노트. T4는 docs-only — 스크립트/하드웨어 구매 없음.

- `docs/iap-messages.md` — iAP 메시지 프로토콜 레퍼런스: wire format, lingo, 재생/메타데이터 커맨드. 기본 오디오 재생 이상의 lingo 핸들러를 구현할 때 참조.
- `docs/advanced-iap-tools.md` — 심층 디버깅 툴 카탈로그: USB 분석기 (usbmon, Saleae), MFi 칩 브레이크아웃 옵션, 포크 빌드 환경 대안. T3 에스컬레이션이 전부 실패했을 때만 손댈 것.

## 개발자 품질 게이트 (Mac에서)

```bash
brew install shellcheck make
make check        # check-t1 → check-t2 → check-t3 → check-t4 순차 실행
make check-t1     # T1 게이트만
make check-t2     # T2 게이트만
make check-t3     # T3 게이트만
make check-t4     # T4 게이트만
```

`make check-t1` 항목:
1. `scripts/` 전체 파일에 `shellcheck -x`
2. systemd 유닛 헤더 검증 (`systemd/ipod-gadget.service`에 `[Unit]`, `[Service]`, `[Install]` 존재)
3. 부팅 패치 내용 확인 (`dtoverlay=dwc2` 및 `modules-load=dwc2`)
4. 문서 존재 확인 (`docs/research-ipod-gadget.md`, `docs/verification-t1.md` 비어있지 않음)

`make check-t2` 항목:
1. `bluetooth/*.sh` + `scripts/*.sh` 전체에 `shellcheck -x`
2. systemd 유닛 헤더 검증 (`systemd/audio-bridge.service` + `systemd/pair-agent.service`의 `[Unit]/[Service]/[Install]`; `systemd/bluealsa.service.d/override.conf`의 `[Service]`)
3. ALSA 설정 sanity (`alsa/asound.conf`에 `pcm.*` 또는 `type` directive 존재)
4. 문서 존재 확인 (`docs/audio-topology.md` 비어있지 않음)
5. BlueZ 패치 payload 확인 (`bluetooth/main.conf.patch.block`에 sentinel + `[General]`/`[Policy]`)

`make check-t3` 항목:
1. `scripts/` 전체에 `shellcheck -x` (`collect-diagnostics.sh` 포함)
2. T3 문서 존재 확인 (`docs/triage.md`, `docs/iap-auth-deep-dive.md` 비어있지 않음)
3. 교차 참조 sanity: `docs/triage.md`가 `iap-auth-deep-dive.md` 문자열 포함 (에스컬레이션 링크 존재 확인)
4. FM transmitter 거부 컨텍스트: `docs/triage.md`에 `FM transmitter`가 등장하면 반드시 3줄 이내에 거부 키워드(`rejected`, `거부`, `명시적`, `policy`, `금지`) 동반
5. `scripts/collect-diagnostics.sh` 존재 + 실행 권한

`make check-t4` 항목:
1. `scripts/` 전체에 `shellcheck -x` (T3 이후 추가된 스크립트까지 포함)
2. T4 문서 존재 확인 (`docs/iap-messages.md`, `docs/advanced-iap-tools.md` 비어있지 않음)
3. 내용 sanity: `docs/iap-messages.md`는 `iAP` + `lingo` 둘 다 언급
4. 내용 sanity: `docs/advanced-iap-tools.md`는 `usbmon` 또는 `Saleae` 중 하나 이상 언급 (캡처 툴 레퍼런스)

## 실패 triage 요약

상세한 triage 순서와 복구 단계는 `CLAUDE.md`의 "Known failure modes" 섹션.

우선순위:

1. `dmesg`에 헤드유닛 인증 에러 — `ipod-gadget` 레포의 `doc/apple-usb.ids`에서 `product_id` 후보 소진 → MFi 인증 칩 옵션 조사 → 업스트림 이슈/포크 스캔 → iAP 리버스 엔지니어링.
2. MMCS가 디바이스는 보지만 재생 안 됨 — `scripts/product-id-loop.sh`로 `product_id` 순환 시도.
3. Pi가 차에서 부팅 루프 — 전원 문제. 2A+ 시가잭 차저 사용.
4. 오디오 경로 문제 — PulseAudio/PipeWire 말고 BlueALSA로 디버깅.

**정책:** FM transmitter fallback 명시적 거부. iAP 완주.

## 업스트림 및 크레딧

- [oandrew/ipod-gadget](https://github.com/oandrew/ipod-gadget) — 커널 모듈 (`g_ipod_audio.ko`, `g_ipod_hid.ko`, `g_ipod_gadget.ko`) + Go 클라이언트. iAP gadget 동작의 ground truth.
- [oandrew/ipod](https://github.com/oandrew/ipod) — Go iAP 클라이언트 라이브러리
- [xtensa/PodEmu](https://github.com/xtensa/PodEmu) — 30-pin iPod dock 레퍼런스. USB-A에서는 직접 사용 불가, T4에서 iAP 메시지 레퍼런스로 참조.

## 프로젝트 상태 요약

### 완료 (하드웨어 도착 전)

- T1: gadget boot 최소 세트 (scripts, boot patches, systemd unit, docs) — push됨
- T2: 오디오 경로 완성 (BlueZ, BlueALSA, ALSA loopback, audio-bridge, pair-agent) — push됨 (스펙 합격선)
- T3: iAP 심층 복구 runbook (triage.md, iap-auth-deep-dive.md, collect-diagnostics.sh) — push됨
- T4: 확장 리서치 (iap-messages.md, advanced-iap-tools.md) — push됨

### Pi 하드웨어 필요한 일

- Raspberry Pi Zero 2 W에서 실제로 `sudo ./scripts/bootstrap.sh` 실행
- 차량에 설치해서 폰과 페어링 테스트, MMCS가 gadget을 iPod로 인식하는지 확인
- 기본 `product_id`가 안 먹으면 `scripts/product-id-loop.sh` 실행
- 오디오 설치 후 `scripts/verify-audio.sh` 실행
- auth 막히면 `docs/iap-auth-deep-dive.md` 단계 에스컬레이션

모든 문서 + 자동화 산출물은 준비 완료. 다음 게이트는 하드웨어 도착.

## 라이선스

License: TBD
