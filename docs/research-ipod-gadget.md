# Upstream Research: `oandrew/ipod-gadget`

본 문서는 T1 체크포인트의 리서치 산출물이다. Pi 하드웨어 도착 전, `ipod-gadget`의 현재 상태와 Outlander MMCS가 기본 `product_id`를 거부할 경우 시도할 후보 전체 목록을 기록해 둔다. 이 표가 T1/T2에서 가장 자주 참조할 **튜닝 노브(tuning knob) 원전**이다.

- 상위 레포: [oandrew/ipod-gadget](https://github.com/oandrew/ipod-gadget)
- 상위 `apple-usb.ids` 파일: [doc/apple-usb.ids](https://github.com/oandrew/ipod-gadget/blob/master/doc/apple-usb.ids)
- 관련 클라이언트 레포: [oandrew/ipod](https://github.com/oandrew/ipod)
- 30핀 iAP 레퍼런스: [xtensa/PodEmu](https://github.com/xtensa/PodEmu)

---

## 1. 레포 현재 상태 (snapshot: 2026-04-19)

| 항목 | 값 |
|------|-----|
| 기본 브랜치 | `master` |
| 최근 push | 2025-08-15 |
| 메타 업데이트 | 2026-04-10 |
| Stars | 254 |
| Forks | 42 |
| Open Issues | 17 (issue 14개 + PR 3개 포함 카운트) |
| Open Pull Requests | 3 |
| License | MIT |
| 주 언어 | C (커널 모듈) + Go (클라이언트) |
| 토픽 | carplay, configfs, gadget, golang, iap, ipod, ipod-gadget, kernel, reverse-engineering, usb |

### 1.1 최근 커밋 5개

| SHA (short) | Date (UTC) | Subject |
|-------------|-----------|---------|
| `ece6b7b` | 2025-08-15 | Use hid_descriptor.rpt_desc on >= 6.12.34 |
| `fda808e` | 2025-03-18 | support USB_SPEED_FULL only |
| `6604c4f` | 2025-03-18 | fix compile errors/warnings |
| `bc1b10d` | 2025-03-18 | fix formatting |
| `8899102` | 2025-03-18 | remove unused code |

**해석:** 2025-03에 빌드 정리 + Full-Speed USB 고정 변경이 몰려 들어왔고, 2025-08에 커널 6.12.34 이상에서의 HID rpt_desc API 변경에 대응한 것이 마지막. 2017년 시작된 레포지만 최근 1년 안에 커널 헤더 ABI 변화에 맞춰 **핀포인트 수준으로 유지보수**가 이어지고 있다. 활발한 feature 개발 레포는 아니지만 "죽은 레포"는 아니라고 본다.

### 1.2 README 첫 단락 (원문)

> ipod-gadget simulates an iPod USB device to stream digital audio to iPod compatible devices/docks. It speaks iAP(iPod Accessory Protocol) and starts an audio streaming session. Tested on Raspberry Pi Zero, Beaglebone Black and Nexus 5 (mainline linux kernel) with Onkyo HT-R391 receiver as the host device (more host devices need to be tested). Should work on any device that runs Linux 4.x (compiled with usb gadget configfs) and has a USB port that supports peripheral mode.

README 말미의 중요 한 줄:

> NOTE: currently it works only if the host device doesn't authenticate the iPod (typically only iPod authenticates the host device which is fine).

즉 상위 작성자 본인이 **"호스트가 iPod를 인증하면 동작 보장 안 된다"** 라고 명시. 이는 `/Users/2026editor/Documents/proj/bt2iap/CLAUDE.md`에 적힌 "MFi auth가 loose할 것이다"라는 가정과 그대로 맞물린다. 우리 과제가 운이 좋으면 동작하는 경계선에 앉아 있다는 점을 잊지 말 것.

---

## 2. 후보 `product_id` 전체 목록 (`doc/apple-usb.ids` 파싱)

Vendor ID는 `0x05ac` (Apple, Inc.) 고정. 아래 `Product ID`는 `insmod g_ipod_gadget.ko product_id=0x<hex>` 형태로 주입.

기본 전략: **Outlander MMCS(2007-2012)는 iPod 세대가 `1260`-`1267` 범위(Classic/Nano 2~7세대) 또는 iPhone 계열 (`1292`-`12a0` 초기 iPhone) 안에 있을 가능성이 가장 높다**. `product-id-loop.sh`에서 순환할 때 아래 표의 **우선순위 컬럼**을 가이드로 쓸 것.

### 2.1 후보 전체 테이블

| Product ID | Device Name / Description | Notes |
|------------|---------------------------|-------|
| `0x1201` | 3G iPod | 1순위 후보 아님 — 2003년식 초기형, iAP 구버전 가능성 |
| `0x1202` | iPod 2G | 1순위 후보 아님 — 동일 |
| `0x1203` | iPod 4.Gen Grayscale 40G | 후보 — 구세대 iPod Classic 계열 |
| `0x1204` | iPod [Photo] | 후보 |
| `0x1205` | iPod Mini 1.Gen/2.Gen | 후보 |
| `0x1206` | iPod '06' | 후보 — 연식 표기상 Outlander 초기형과 유사 시대 |
| `0x1207` | iPod '07' | **우선 후보** — Outlander 2007 MY와 시대 매칭 |
| `0x1208` | iPod '08' | **우선 후보** — Outlander 2008 MY 시대 매칭 |
| `0x1209` | iPod Video | 후보 |
| `0x120a` | iPod Nano | 후보 |
| `0x1223` | iPod Classic/Nano 3.Gen (DFU mode) | **제외 권장** — DFU 모드는 펌웨어 업데이트용이라 오디오 스트리밍 안 됨 |
| `0x1224` | iPod Nano 3.Gen (DFU mode) | 제외 권장 — DFU |
| `0x1225` | iPod Nano 4.Gen (DFU mode) | 제외 권장 — DFU |
| `0x1227` | Mobile Device (DFU Mode) | 제외 권장 — DFU |
| `0x1231` | iPod Nano 5.Gen (DFU mode) | 제외 권장 — DFU |
| `0x1240` | iPod Nano 2.Gen (DFU mode) | 제외 권장 — DFU |
| `0x1242` | iPod Nano 3.Gen (WTF mode) | 제외 권장 — WTF/복구 모드 |
| `0x1243` | iPod Nano 4.Gen (WTF mode) | 제외 권장 — WTF |
| `0x1245` | iPod Classic 3.Gen (WTF mode) | 제외 권장 — WTF |
| `0x1246` | iPod Nano 5.Gen (WTF mode) | 제외 권장 — WTF |
| `0x1255` | iPod Nano 4.Gen (DFU mode) | 제외 권장 — DFU |
| `0x1260` | iPod Nano 2.Gen | **1순위** — 2006~2007 출시, Outlander 2007 시대 |
| `0x1261` | iPod Classic | **1순위** — 2007 출시, Outlander 출시 시기와 정확히 매칭 |
| `0x1262` | iPod Nano 3.Gen | **1순위** — 2007 출시 |
| `0x1263` | iPod Nano 4.Gen | **1순위** — 2008 |
| `0x1265` | iPod Nano 5.Gen | **1순위** — 2009 |
| `0x1266` | iPod Nano 6.Gen | 2순위 — 2010 |
| `0x1267` | iPod Nano 7.Gen | 2순위 — 2012 (Outlander 최종 MY 범위) |
| `0x1281` | Apple Mobile Device [Recovery Mode] | 제외 권장 — 복구 모드 |
| `0x1290` | iPhone | 3순위 — 2007 1세대 iPhone |
| `0x1291` | iPod Touch 1.Gen | 3순위 — 2007 |
| `0x1292` | iPhone 3G | 3순위 — 2008 |
| `0x1293` | iPod Touch 2.Gen | 3순위 — 2008 |
| `0x1294` | iPhone 3GS | 3순위 — 2009 |
| `0x1296` | iPod Touch 3.Gen (8GB) | 3순위 — 2009 |
| `0x1297` | iPhone 4 | **기본값 후보** — README 예시에서 언급된 ID (`product_id=0x1297`) |
| `0x1299` | iPod Touch 3.Gen | 3순위 — 2009 |
| `0x129a` | iPad | 4순위 — iPad를 iPod로 인식하는 헤드유닛은 드묾 |
| `0x129c` | iPhone 4(CDMA) | 3순위 |
| `0x129e` | iPod Touch 4.Gen | 3순위 — 2010 |
| `0x129f` | iPad 2 | 4순위 |
| `0x12a0` | iPhone 4S | 3순위 — 2011 (Outlander 2011~2012 MY 매칭) |
| `0x12a2` | iPad 2 (3G; 64GB) | 4순위 |
| `0x12a3` | iPad 2 (CDMA) | 4순위 |
| `0x12a4` | iPad 3 (wifi) | 4순위 |
| `0x12a5` | iPad 3 (CDMA) | 4순위 |
| `0x12a6` | iPad 3 (3G, 16 GB) | 4순위 |
| `0x12a8` | iPhone 5/5C/5S/6 | 4순위 — 2012 이후, Lightning 전환 세대 |
| `0x12a9` | iPad 2 | 4순위 |
| `0x12aa` | iPod Touch 5.Gen [A1421] | 4순위 |
| `0x12ab` | iPad 4/Mini 1 | 4순위 |
| `0x1300` | iPod Shuffle | 5순위 — Shuffle 계열은 오디오만 지원, 디스크 인식 여부 불명 |
| `0x1301` | iPod Shuffle 2.Gen | 5순위 |
| `0x1302` | iPod Shuffle 3.Gen | 5순위 |
| `0x1303` | iPod Shuffle 4.Gen | 5순위 |

총 **53개**의 Apple USB product_id 후보가 `apple-usb.ids`에 등재되어 있다. 이 중 DFU/WTF/Recovery 모드 ID(9개)를 제외하면 실제 시도 가치가 있는 후보는 **44개**.

### 2.2 시도 순서 권장 (product-id-loop 진행 순서)

1. **Tier A (우선):** `0x1261` → `0x1260` → `0x1262` → `0x1263` → `0x1265` — iPod Classic / Nano 2-5세대 (Outlander 출시 시기와 디바이스 매칭)
2. **Tier B:** `0x1266` → `0x1267` → `0x1207` → `0x1208` → `0x1209` → `0x120a` — Nano 6-7세대 및 일반 iPod 연식 표기
3. **Tier C:** `0x1297` (README 예시) → `0x12a0` → `0x1294` → `0x1292` → `0x1290` → `0x1291` — iPhone/iPod Touch 3~4세대
4. **Tier D:** 나머지 iPad/Shuffle ID — 가능성 낮음. Tier A-C 전부 실패 시 최후 시도.

---

## 3. 상위 레포 caveats / known-issues 요약

Open issues 14개 + 최근 commit 메시지에서 도출한 주의사항 5개:

- **커널 6.12.34+ HID 구조 변경 대응 (2025-08 commit `ece6b7b`).** Pi OS Lite 64-bit의 커널 버전에 따라 최신 `master`만 정상 빌드된다. `raspberrypi-kernel-headers`로 설치되는 커널 헤더 버전을 빌드 전에 반드시 확인하고, 오래된 Pi OS 이미지를 쓰는 경우 `apt full-upgrade` 후 커널 헤더를 재설치할 것.
- **USB SPEED FULL 고정 변경 (2025-03 commit `fda808e`).** High-Speed 협상이 문제를 일으킨 과거 이슈에 대응해 Full-Speed (12Mbps)로 고정됐다. iAP/HID + UAC1만 쓰는 워크로드라 대역폭은 충분하지만, 헤드유닛이 High-Speed만 허용하는 구형 장치라면 연결 실패가 뜰 수 있다.
- **특정 차량/리시버에서 동작 실패 보고 다수.** Open issues에 "Volvo v70 2015 판독 불가" (#24), "2011 Nissan Murano 파일 읽기 불가" (#11), "2015 TLX 동작 안 함" (#33), "Pi Zero 2W에서 동작 안 함" (#28), "Cooper F56 주의사항" (#36) 등 차량별 사례가 쌓여 있다. **동일 차량 리포트는 없으나, "Pi Zero 2 W에서 문제" (#28)는 우리와 직접 연관**되므로 T3 진입 전에 읽어둘 것.
- **"디바이스 인식 안 됨" / "UDC 할당 실패" 계열 이슈가 반복 등장.** #22/#26 등이 대표 사례. dwc2 overlay가 정상 로드되지 않으면 configfs가 UDC를 못 찾는다. T1 verification의 `lsmod | grep dwc2` 단계를 건너뛰지 말 것.
- **DKMS/자동설치 PR은 3년째 오픈 (PR #8, PR #30).** 상위 레포는 유지보수는 하되 기능 PR 병합에 소극적이다. 우리가 upstream fork를 떠서 수정해야 하는 상황이 되면 PR이 들어갈 가능성은 낮다고 가정하고, **fork + 로컬 패치 운용**을 전제로 할 것.

---

## 4. 관련 프로젝트

- **[oandrew/ipod](https://github.com/oandrew/ipod)** — Go로 작성된 iAP 클라이언트 단독 레포. `/dev/iap0` 문자 디바이스를 열어 iAP 패킷을 읽고 쓰며, 인증 핸드셰이크와 오디오 스트리밍 활성화를 담당한다 (`go build ./cmd/ipod` 한 줄로 빌드).
- **[xtensa/PodEmu](https://github.com/xtensa/PodEmu)** — 30-pin 독 커넥터 기반 Android 앱 형태의 iPod 에뮬레이터. USB-A 경로인 Outlander에는 **직접 사용 불가**지만, iAP 메시지 명세 (스티어링휠/메타데이터)의 구현 레퍼런스로 T4 확장 리서치 때 활용한다.

---

## 5. T1 단계에서 이 문서가 의미하는 것

- `scripts/product-id-loop.sh`의 후보 배열은 **§2.2의 Tier A → B → C 순**으로 하드코딩한다.
- `scripts/bootstrap.sh`는 `ipod-gadget` 레포를 `master` 브랜치에서 클론하되, **커널 헤더 버전 확인 로직**을 로그에 남기도록 한다 (§3 첫 번째 caveat).
- T3 진입 전 참고 링크: `https://github.com/oandrew/ipod-gadget/issues/28` (Pi Zero 2W 실패 케이스).
