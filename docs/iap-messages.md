# iAP Message Reference (T4 확장 리서치)

본 문서는 Pi 하드웨어가 도착하기 전, **T4 "Extension Research"** 의 docs-only 산출물이다. 1차 재생 목표(T2) 달성 이후 우리가 원할 법한 두 가지 확장 ― **스티어링휠 버튼 제어** 와 **헤드유닛 LCD에 곡 메타데이터 표시** ― 를 직접 구현하지는 않되, 미래의 T5+ 작업이 바로 들어갈 수 있도록 iAP(iPod Accessory Protocol) 메시지 레이아웃을 한 장에 집약해 둔다.

원전 두 가지를 코드 레벨에서 교차 검증해 작성한다.

- [`xtensa/PodEmu`](https://github.com/xtensa/PodEmu) — 30-pin dock 시대 Android 기반 iPod 에뮬레이터. iAP 프레임 파서, 핸들러 스위치가 한 파일(`OAPMessenger.java`, 2619줄)에 거의 전부 들어 있어 **메시지 형식의 살아있는 레퍼런스**로 가장 유용하다.
- [`oandrew/ipod-gadget`](https://github.com/oandrew/ipod-gadget) — Pi에서 우리가 실제 돌릴 커널 모듈 + Go 클라이언트. 현재 코드 베이스는 enumeration + 오디오 스트리밍 활성화까지만 구현하며, 본 문서가 다루는 메타데이터/스티어링휠 메시지는 **아직 구현되어 있지 않다**.

---

## 1. Scope (이 문서가 다루는 것과 다루지 않는 것)

### 다룬다

- iAP1 **wire format** — 프레임 구조, 길이/체크섬 계산.
- 주요 **lingo 구분** — General, SimpleRemote, ExtendedInterface, DigitalAudio의 역할.
- 미래 확장에 직접 쓸 **커맨드 레퍼런스**:
  - SimpleRemote 모드의 Play/Pause/Next/Prev (스티어링휠 버튼용)
  - ExtendedInterface 모드의 GetTrackTitle / GetTrackArtist / GetTrackAlbum (메타데이터 표시용)
  - General Lingo의 iPodNotify / 연결 상태 신호 (연결 재시작/상태 싱크)
- Outlander MMCS가 스티어링휠 버튼을 어떻게 iAP로 매핑할지에 대한 **추정 및 미검증 표식**.
- `g_ipod_gadget` 현재 상태와 메타데이터 송신 경로 **부재(absence) 검증** ― 무엇을 어디에 어떻게 덧붙여야 하는가.

### 다루지 않는다 (명시적 out-of-scope)

- **MFi(Made For iPod) 인증 내부 구조** — challenge/response 암호학, 0x4A 계열 certificate 메시지, 0x40 계열 signature 메시지. 이는 `docs/iap-auth-deep-dive.md` Stage 4의 영역이고, 본 문서는 "인증 이후에 오가는 세션 메시지"만 다룬다.
- **iAP2 (새 프로토콜, Lightning 시대)** — HID-over-Lightning, USB vendor-specific class 기반. 2007-2012 Outlander MMCS 는 30-pin/USB-A 시대 장치로, **iAP1 만** 기대한다. iAP2 레퍼런스는 본 프로젝트에서 무용하다.
- **구현 자체** — 본 문서는 "어디에 뭐가 있는지"의 지도이고, 코드 추가는 T5+ 에서 별도 지시를 받아 진행한다.

---

## 2. Wire format (iAP1 프레임)

iAP1 은 30-pin dock 시절부터 사용된 하프-듀플렉스 시리얼/USB 프로토콜이다. 프레임의 생김새는 트랜스포트(TTL serial vs USB bulk interrupt)와 무관하게 아래 바이트 레이아웃을 갖는다.

### 2.1 표준 프레임 (≤255 바이트 페이로드)

```
┌──────┬──────┬────────┬──────┬──────────┬──────────┬──────────┐
│ 0xFF │ 0x55 │  Len   │ Mode │  Cmd_hi  │  Cmd_lo  │  Params  │ Cksum
└──────┴──────┴────────┴──────┴──────────┴──────────┴──────────┘
  1B     1B     1B       1B     1B         1B         0..n B     1B
```

| Field | Width | Meaning |
|-------|-------|---------|
| Sync #1 | 1 byte | 항상 `0xFF`. Start-of-frame 마커. `OAPMessenger.java:278,295` 에서 첫 바이트가 `0xFF` 아니면 `-1` 반환. |
| Sync #2 | 1 byte | 항상 `0x55`. `OAPMessenger.java:279,301` 에서 두 번째 바이트 검증. |
| Length | 1 byte | Mode 바이트부터 Params 끝까지의 바이트 수 (Cksum 제외). 최대 259바이트 메시지 제약은 `OAPMessenger.java:308`에 직접 명시. |
| Mode / Lingo | 1 byte | 어느 lingo로 해석할지 지시. §3 참조. `OAPMessenger.java:388`의 `int mode = (line_buf[3 + pos_shift] & 0xff)`. |
| Command ID | 1 또는 2 bytes | General mode는 1바이트, ExtendedInterface는 2바이트. `OAPMessenger.java:389-396`에서 `cmd = (scmd1 & 0xff)`, 프레임 길이가 충분하면 `cmd = (cmd << 8) + (scmd2 & 0xff)` 로 확장. |
| Params | 0..n bytes | 명령에 따라 가변. |
| Checksum | 1 byte | §2.3. |

Raw byte 예시(SimpleRemote "Play/Pause"):

```
FF 55 03 02 00 01 FA
│  │  │  │  │  │  └─ Checksum
│  │  │  │  └──┴──── Button bitmap (16-bit, LSB=0x0001=Play)
│  │  │  └────────── Mode = 0x02 (Simple Remote)
│  │  └───────────── Length = 3 (Mode + 2-byte bitmap)
└──┴──────────────── Sync 0xFF 0x55
```

### 2.2 확장 프레임 (페이로드 > 255 바이트 — e.g., 앨범 아트)

Length 필드가 `0x00`인 경우 바로 뒤 2바이트가 16-bit length (big-endian)로 쓰인다. 이는 PodEmu 소스에서 "extended image message" 로 처리되며, 최대 65031 바이트까지 확장된다.

- 진입 조건: `line_buf[2] == 0x00` (`OAPMessenger.java:275` 인접 블록).
- 길이 복원: `line_cmd_len = ((ext_image_buf[3] << 8) | ext_image_buf[4]) + 6` (`OAPMessenger.java:274-284`).
- 확장 마커 검증: 바이트 5=`0x04`, 바이트 6=`0x00`, 바이트 7=`0x32` (`OAPMessenger.java:262-265`).

우리의 직접 필요(playback control + text metadata)에는 표준 프레임만 쓰면 충분하다. 확장 프레임은 앨범 아트 전송 같은 바이너리 큰 페이로드를 위한 것이다.

### 2.3 Checksum 계산

PodEmu `oap_calc_checksum`(`OAPMessenger.java:2189-2201`) 구현:

```java
public byte oap_calc_checksum(byte buf[], int len) {
    int checksum = 0;
    // 앞 2바이트(sync)와 끝 1바이트(checksum 자신)는 제외
    for (int j = 2; j < len - 1; j++)
        checksum += buf[j];
    checksum &= 0xff;
    checksum = 0x100 - checksum;
    return (byte) checksum;
}
```

다시 말해: **Length + Mode + Cmd + Params 의 단순 byte 합을 8비트로 wrap 한 뒤, `0x100 - sum` (= two's complement) 을 체크섬으로 둔다.** 수신 측은 같은 식으로 다시 계산해 같지 않으면 조용히 프레임을 버린다(무응답, `OAPMessenger.java:333-337`). 체크섬 불일치에 대한 NACK 메시지는 존재하지 않는다.

---

## 3. Lingoes / Modes (주요 그룹)

iAP1 은 각 기능군을 **lingo** (또는 "mode" byte)로 분리한다. PodEmu 는 상수 4개를 공개하는데, 본 프로젝트에서 자주 만나는 lingo는 아래와 같다.

| Lingo byte | 통상 명칭 | 역할 | PodEmu 상수/참조 |
|-----------|-----------|------|-----------------|
| `0x00` | **General Lingo** | 세션 시작/종료, mode switch, device info query, 인증 핸드셰이크 트리거 | `OAPMessenger.java:419-616` (case 0x01/0x03/0x05/0x06/0x07/0x0B/0x0D/0x0F/0x13/0x24/0x28 처리 블록). `IPOD_MODE_UNKNOWN=0x00` @ L40. |
| `0x02` | **SimpleRemote Lingo** | 1-버튼(또는 비트맵) 재생 제어. 스티어링휠 버튼 매핑의 주 타깃. | `OAPMessenger.java:617-797` (case 0x0001/0x0008/0x0010/0x0080 등). `IPOD_MODE_SIMPLE=0x02` @ L41. |
| `0x04` | **ExtendedInterface (AiR) Lingo** | DB 탐색, 플레이리스트 조작, 트랙 메타데이터 (제목/아티스트/앨범/길이). 우리가 메타데이터 표시에서 쓸 주력. | `OAPMessenger.java:804-1488` 의 거대한 `case 0x____` 스위치. `IPOD_MODE_AIR=0x04` @ L42. |
| `0x0A` | DigitalAudio Lingo | USB Audio Class 스트림 활성화 관련 (Apple의 독자 UAC 확장). | 본 프로젝트에서는 `g_ipod_audio` 모듈이 UAC1 표준 경로로 처리하므로 직접 다룰 일 적음. |
| `0x0E` | AppInterface Lingo | iOS 앱 측 데이터 교환 용도. 헤드유닛 용도로는 거의 안 씀. | 미사용. |

실제로 우리가 **구현해야 할 대상은 `0x00`, `0x02`, `0x04` 세 개**다. `0x00`은 세션 진입을 제어하고, `0x02` 는 버튼 비트맵을 읽고, `0x04` 는 메타데이터 질문에 답한다.

> 정정 (factual correction 2026-04-19): 이전 판본에는 `0x03` 을 별도의 "DisplayRemote / Polling Lingo" 로 등재했으나 이는 오기였다. PodEmu 소스 (`OAPMessenger.java:447-456`) 에서 `0x03` 은 **General Lingo (`Mode=0x00`) 의 current-mode 질의 커맨드** 로 처리된다 — 즉 독립 lingo byte 가 아니라 Mode=0x00 아래 Cmd=0x03 이다. 본 표에서는 그에 따라 `0x03` 행을 제거했고, Mode-switch 흐름 서술 (아래) 에서만 언급한다.

Mode switch 흐름(실제 iPod이 ExtendedInterface로 넘어가는 전형적 트랜지션)은 PodEmu에서 아래와 같이 관찰된다:

- Host가 `Mode=0x00, Cmd=0x0104` 전송 → PodEmu는 `ipod_mode = IPOD_MODE_AIR` 로 전환 (`OAPMessenger.java:425-439`).
- Host가 `Mode=0x00, Cmd=0x0102` 전송 → `ipod_mode = IPOD_MODE_SIMPLE` (`OAPMessenger.java:441-446`).
- `Mode=0x00, Cmd=0x03` → 현재 mode 응답 (`OAPMessenger.java:447-456`): `{0x04, 1 if AiR else 0}` 으로 2바이트 반환.

즉 Outlander MMCS가 우리 Pi-gadget을 iPod으로 올바르게 잡기 시작하면, 초기에 `0x0104` (AiR 요청)가 날아올 가능성이 매우 높다. 현재 `g_ipod_gadget`은 해당 AiR 요청을 받아도 실질적 응답(트랙 목록 등)을 만들지 않기 때문에 "iPod으로 잡히되 재생 안 됨"이 쉽게 발생한다 (`docs/triage.md` §2 와 동일 증상).

---

## 4. 우리가 실제로 구현해야 할 커맨드 (confirmed via code)

### 4.1 SimpleRemote (`Mode=0x02`) — 스티어링휠 버튼

SimpleRemote 는 16-bit button bitmap 이다. "눌린 버튼 1 / 안 눌린 0" 을 한 프레임에 모아 보내며, 아무 버튼도 안 눌린 상태는 `0x0000` 이다.

PodEmu `OAPMessenger.java:617-797` 의 switch(cmd) 분기를 따라 정리:

| Command (16-bit bitmap) | 동작 | PodEmu 핸들러 line |
|-------------------------|------|---------------------|
| `0x0001` | Play (press 이벤트) | L620-640 (`SIMPLE_MODE IN - play` 로그 출력; PodEmu 는 Play 단독으로만 처리하며 Pause toggle 은 별도 커맨드) |
| `0x0002` | (미사용 또는 Volume Up in some docs) | — |
| `0x0008` | Skip Next | L641-650 |
| `0x0010` | Skip Previous | L651-672 |
| `0x0080` | Stop | L673-677 |
| `0x0000` | All-buttons-released (press 해제 통지) | L678-695 |
| multi-bit set | 동시에 여러 버튼 — 드문 경우 | L696+ 에 추가 play/pause/shuffle/repeat toggling 처리. |

> 정정 (factual correction 2026-04-19): 이전 판본에는 `0x0001` 을 "Play / Pause toggle" 로 기재했으나 PodEmu 소스 (`OAPMessenger.java:620-640`) 에서는 **Play 단독** 으로만 처리된다. Pause/toggle 동작은 multi-bit set 행이 가리키는 후속 case (L696+) 의 별도 커맨드에서 이뤄지므로, `0x0001` 단일 비트는 순수 Play press event 로 이해해야 한다.

Wire-level 바이트로 "Play" 한 번:

```
FF 55 03 02 00 01 FA    // Play pressed
FF 55 03 02 00 00 FB    // Release (all buttons up)
```

Length=3, Mode=0x02, 그 뒤 2-byte big-endian bitmap. 체크섬은 `0x100 - (0x03 + 0x02 + 0x00 + 0x01) = 0xFA`.

VolumeUp / VolumeDown 은 PodEmu의 SimpleRemote 스위치에 확정된 분기가 **없다**. 전통적 iAP1 문서들은 `0x0004` / `0x0008` 을 볼륨에 배정하지만 세대별/기기별 편차가 커서 실제 Outlander에서 관찰된 bitmap 은 bench test 시점에 `dmesg`/usbmon 로그로 확인해야 한다. 이 문서에서는 **unverified** 로 표식만 남긴다.

### 4.2 ExtendedInterface (`Mode=0x04`) — 메타데이터

PodEmu 가 응답을 생성하는 메타데이터 트리오는 아래 세 개다. Command ID 는 **2 바이트** 임에 주의.

| Cmd (host → iPod) | 의미 | iPod (gadget) 응답 Cmd | 응답 페이로드 | PodEmu 핸들러 line |
|-------------------|------|------------------------|---------------|---------------------|
| `0x0020` | GetTrackTitle | `0x0021` | null-terminated string | `oap_04_write_title`, `OAPMessenger.java:1828-1846` |
| `0x0022` | GetTrackArtist | `0x0023` | null-terminated string | `oap_04_write_artist`, L1849-1868 |
| `0x0024` | GetTrackAlbum | `0x0025` | null-terminated string | `oap_04_write_album`, L1871-1889 |

중요한 형식 주의:

- PodEmu 는 응답을 **NUL-terminated byte string** 으로 보낸다(`oap_04_write_string` 호출, 위 각 핸들러 내부). 실제 iPod 세대/차량에 따라 **UTF-16LE (Unicode)** 가 요구되는 경우가 보고된다 ― Apple Accessory Protocol 사양 문서상 대부분의 string 필드는 UTF-16LE 이지만, 일부 ExtendedInterface 응답은 UTF-8/ASCII 로도 수용하는 헤드유닛이 있다. 구현 시점에 양쪽 인코딩을 실험적으로 비교해 보는 것이 안전하다. **Outlander 실 인코딩 요구는 unverified.**
- null terminator 는 payload 마지막에 `0x00` 1바이트. 체크섬 계산에 포함된다.

관련 주변 커맨드 (미래 확장 시 참조):

- `0x000C` GetTrackInfo → 응답 `0x000D` (트랙 capabilities, duration 등, `OAPMessenger.java:897-914`).
- `0x001C` GetCurrentPosition → 응답 `0x001D`(`OAPMessenger.java:1050-1060`). 플레이리스트 상 현재 트랙 인덱스. 스티어링휠 Next/Prev 와 연동해 UI 싱크 용.
- `0x0026` / `0x0027` (GetTrackGenre — PodEmu는 추가 info 경로로 처리, `OAPMessenger.java:1131-1150`).

### 4.3 General Lingo (`Mode=0x00`) — 연결 상태 / 통지

우리가 메타데이터 디스플레이를 구현하려면 결국 "지금 트랙이 바뀌었다" 를 헤드유닛에 알릴 통지 메시지가 필요하다. PodEmu 에서는 해당 역할을 아래 두 가지가 담당한다.

- **iPodConnected 통지**: PodEmu의 `oap_communicate_ipod_connected()` 는 mode 전환 직후(AiR 진입 시 L431, Simple 진입 시 L443) 호출된다. 이 함수는 별도 프레임을 전송하는 래퍼로, 본 문서 범위에서는 "세션 진입 완료 통지가 호출되는 시점" 만 확인해 두고, 그 내부 페이로드는 PodEmu 소스 현지(`OAPMessenger.java` 내 `oap_communicate_ipod_connected` 검색)에서 확인한다.
- **Polling notifications** (재생 진행률, 트랙 변경 통지): AiR 모드에서 polling mode 가 활성화되면(`Mode=0x04, Cmd=0x0026` → params[0]=0x01, `OAPMessenger.java:1131-1150`) iPod 쪽이 주기적으로 `oap_04_write_polling_*` 를 내보낸다(`OAPMessenger.java:1892+`). MMCS LCD가 "경과 시간" 바를 그리려면 이 경로가 필수다.

### 4.4 참고: 알려진 에러 코드

General Lingo 응답에 쓰이는 상태 코드(`OAPMessenger.java:45-50`):

| 상수 | 값 | 의미 |
|------|----|------|
| `IPOD_SUCCESS` | `0x00` | OK |
| `IPOD_ERROR_DB_CATEGORY` | `0x01` | DB 카테고리 오류 |
| `IPOD_ERROR_CMD_FAILED` | `0x02` | 명령 실행 실패 |
| `IPOD_ERROR_OUT_OF_RESOURCES` | `0x03` | 리소스 부족 |
| `IPOD_ERROR_OUT_OF_RANGE` | `0x04` | 범위 초과 (잘못된 인덱스 등) |
| `IPOD_ERROR_UNKOWN_ID` | `0x05` | 알 수 없는 ID (sic — PodEmu 상의 원문 오타) |

Stage 4 역공학 단계에서 wire diff 할 때, known-good iPhone 세션이 돌려주는 응답 코드 분포를 우리 gadget이 같게 흉내내는지 확인하는 기준점이 된다.

---

## 5. 스티어링휠 버튼 → iAP 매핑 (speculative; 실측 미수행)

Outlander MMCS 스티어링휠 리모트의 정확한 iAP 매핑은 **현재 확보된 자료 없음** 이다. 아래는 Mitsubishi/공용 OEM 리모트의 전형적 기대치와 PodEmu가 인식하는 SimpleRemote bitmap 을 교차한 **추정**이며, 실 기기 검증 없이는 확정되지 않는다.

| Steering-wheel button (통상) | 기대 iAP 커맨드 (추정) | 근거 |
|-------------------------------|--------------------------|------|
| Play/Pause | `Mode=0x02, Bitmap=0x0001` | PodEmu SimpleRemote case `0x0001` — 모든 iAP1 구현에서 공통. 확정도 높음. |
| Next track | `Mode=0x02, Bitmap=0x0008` | PodEmu case `0x0008`. iPod Classic 세대 표준. 확정도 높음. |
| Previous track | `Mode=0x02, Bitmap=0x0010` | PodEmu case `0x0010`. 확정도 높음. |
| Volume Up | **unverified** | PodEmu SimpleRemote에 명시적 case 없음. iAP1 문서별로 `0x0004` (타 레퍼런스) 또는 헤드유닛 내부에서 차량 앰프 제어로 흡수 (즉, iAP 트래픽으로 나오지 않음) 가능성 둘 다 존재. |
| Volume Down | **unverified** | 동 이유. |
| Source (USB 외부로 빠지는 버튼) | iAP 트래픽으로는 안 잡힐 가능성 높음 | 헤드유닛 로컬 기능. |

**실측 플랜 (T5+ 에서 실행):** 차량 연결 상태에서 스티어링휠 버튼을 한 번씩 누르면서 `cat /dev/iap0 | xxd` 로 실제 bitmap 을 캡처하고, 위 표를 **검증/수정** 해야 한다. 그 전까지는 본 섹션을 "참고 가설" 로 취급.

---

## 6. 메타데이터 디스플레이 경로 — 구현이 비어 있는 지점

우리가 MMCS LCD 에 "곡 제목 / 아티스트 / 앨범" 을 띄우려면 **iPod 측(= 우리 Pi gadget)** 이 ExtendedInterface 메시지 `0x0020/0x0022/0x0024` 에 즉시 응답해야 한다. 이 응답 기능은 현재 `oandrew/ipod-gadget` 의 `gadget/` 디렉토리 소스에서 **구현되어 있지 않다.**

### 6.1 ipod-gadget 현재 상태 (검증)

레포 `oandrew/ipod-gadget` (2026-04-19 기준 snapshot — `docs/research-ipod-gadget.md` §1.1 참고) 의 `gadget/` 디렉토리는 다음 5개 파일로 구성된다.

| File | 역할 |
|------|------|
| `Makefile` | 모듈 빌드. |
| `ipod.h` | USB device descriptor, VID=0x05AC, default PID=0x1297 선언 (검증: `IPOD_USB_VENDOR 0x05ac`, `IPOD_USB_PRODUCT 0x1297`). Audio control descriptor, HID report descriptor, UAC1 endpoint descriptor들이 static struct 로 정의. |
| `ipod_audio.c` | UAC1 audio streaming 엔드포인트 — ALSA `iPodUSB` 카드의 source. |
| `ipod_gadget.c` | composite gadget 등록 + `/dev/iap0` char device 생성 + iAP bulk endpoint 처리. |
| `ipod_hid.c` | HID interface (리모트 이벤트 전달용). |
| `trace.h` | 로그 매크로. |

iAP 메시지 파싱/응답은 **`ipod_gadget.c` 가 만드는 `/dev/iap0` char device 를 user-space 에서 read/write 하는 방식** 으로 설계되어 있다. 즉 커널 모듈은 raw byte pipe만 제공하고, 실제 로직은 [`oandrew/ipod`](https://github.com/oandrew/ipod) Go 클라이언트가 `/dev/iap0`를 열어 수행한다.

Go 클라이언트(`oandrew/ipod`) 의 범위는 현재:

- iAP 인증 핸드셰이크 (Stage 4 deep dive 대상이 아닌 "호스트가 인증 안 하는" 경우의 최소 필요).
- Digital audio streaming activation.
- 제한적 playback state exchange.

**메타데이터 응답(0x0020/0x0022/0x0024) 은 Go 클라이언트에도 구현되어 있지 않다.** 따라서 "MMCS 화면에 트랙 정보 표시" 는 **신규 기능** 으로 취급해야 한다.

### 6.2 실측 확인 방법

본 문서 작성 시점에 코드 부재를 확인하려면:

```bash
# ipod-gadget/gadget 디렉토리에서 ExtendedInterface 응답 handler 검색
gh api /repos/oandrew/ipod-gadget/git/trees/master?recursive=1 \
  --jq '.tree[] | select(.path | startswith("gadget/")) | .path'
# 응답: Makefile, ipod.h, ipod_audio.c, ipod_gadget.c, ipod_hid.c, trace.h 6개뿐

# oandrew/ipod (Go 클라이언트) 에서 0x0020/0x0022/0x0024 검색
gh api "/repos/oandrew/ipod/contents" --jq '.[].path'
# (실행 시점에 존재하는 경로에서 grep으로 확인)
```

PodEmu 쪽 구현은 `OAPMessenger.java:1828-1889` 에 있는 반면, upstream Pi gadget 측에는 대응 구현이 없는 것이 본 gap 의 전부다.

### 6.3 관련 upstream 이슈

`docs/iap-auth-deep-dive.md` §Stage 3 의 이슈 목록 중 본 gap과 교차하는 것:

- [#18 0x64 "RequestApplicationLaunch" error](https://github.com/oandrew/ipod-gadget/issues/18) — iAP 메시지 레벨 에러 토론 스레드. 본 섹션의 "구현 안 됨" 을 논의한 유일한 공개 이슈에 가깝다.

메타데이터 확장 전용 upstream 이슈는 현재 없다. 이는 "상대적으로 중요하지 않다" 가 아니라 "아무도 아직 PR 내지 않았다" 로 해석된다.

---

## 7. 구현 노트 (미래 T5+ 가 들어갈 위치)

본 프로젝트의 초기 스코프(T1~T2)를 지나 스티어링휠/메타데이터를 붙인다고 가정할 때, 코드 변경이 들어갈 지점은 셋이다.

### 7.1 커널 모듈 (`ipod-gadget/gadget/ipod_gadget.c`)

`/dev/iap0` char device 의 read/write 경로는 현재 raw 바이트를 user-space 로 그대로 넘기므로, **커널 레이어 변경은 원칙적으로 필요 없다.** 단, 예외적으로 아래 두 경우에만 커널 쪽 수정이 필요해진다.

1. iAP endpoint bulk packet size 가 확장 프레임(§2.1)의 16-bit length 를 수용 못 하는 경우 — 현재 endpoint descriptor 의 `wMaxPacketSize` 확인. 표준 프레임(≤259바이트) 처리에는 문제 없음.
2. HID report descriptor (`ipod_hid.c`)를 통해 스티어링휠 버튼을 **raw HID** 로 별도 경로로 받겠다고 설계를 뒤집는 경우 — 권장하지 않음. SimpleRemote lingo 를 그대로 쓰는 것이 표준 경로.

결론: 커널 수정 **회피**. User-space 에서 다룬다.

### 7.2 Go 클라이언트 (`oandrew/ipod` 의 `cmd/ipod` 또는 별도 바이너리)

`/dev/iap0` 을 열어 iAP 프레임을 read/write 하는 wrapper 를 확장한다.

- **수신 측**: SimpleRemote(`Mode=0x02`) 프레임이 도착하면 16-bit bitmap 을 디코드 → 버튼 이벤트를 user agent 로 전달(예: D-Bus signal `org.mpris.MediaPlayer2.Player.PlayPause`).
- **송신 측**: user agent 가 "현재 재생 중 트랙의 제목/아티스트/앨범" 을 푸시해 오면, MMCS 의 ExtendedInterface query(`0x0020` 등)에 즉시 응답할 수 있도록 캐시 테이블을 유지. MMCS 가 `0x0020` 을 던지면 캐시된 title 을 `0x0021` 응답으로 write.

Go 쪽 이미 존재하는 패킷 encode/decode 구조(`ipod` 레포의 `cmd/ipod` 서브패키지 등)에 새 커맨드 wrapper 를 추가하는 방식이 자연스럽다. 구조는 PodEmu 의 `oap_process_msg` switch 스위치와 대칭이다.

### 7.3 User-agent (Pi 측 백그라운드 데몬, 신규)

**BlueALSA 는 track metadata 를 노출하지 않는다.** A2DP 만 쓰며 AVRCP 의 metadata-notification (track change, artist/title TLV)은 기본 설정에서 주고받지 않는다. 따라서 폰 → Pi 방향으로 "지금 곡 정보" 를 받아올 경로가 따로 필요하다.

표준 리눅스 접근:

- 폰을 AVRCP 까지 페어링(BlueZ 는 지원) → BlueZ 가 D-Bus 에 `org.bluez.MediaPlayer1` 인터페이스를 노출.
- Pi 측에서 D-Bus (system bus) 를 listen 하는 작은 Python/Go 데몬 → `Track` property 변경 시 제목/아티스트/앨범 캐시.
- 캐시를 Go iAP wrapper 와 UNIX socket 또는 D-Bus signal 로 공유.

DBus path 예시(BlueZ 5.x):

```
/org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX/player0
  Interface: org.bluez.MediaPlayer1
  Property: Track (a{sv}) — Title, Artist, Album, Duration 등
```

이 경로는 MPRIS와 구조적으로 유사하지만 **BlueZ 의 MediaPlayer1 쪽**이 Bluetooth AVRCP 종속 이기 때문에 BlueALSA-only 설정이라면 BlueZ `org.bluez.Agent1` / `MediaControl1` 도 별도 활성화해야 한다. BlueALSA 의 audio path 와 BlueZ 의 control path 는 **분리 공존 가능** — BlueALSA가 A2DP audio 를 먹고, BlueZ 가 AVRCP control을 먹는 분업이 표준.

데몬의 역할 요약:

1. BlueZ D-Bus MediaPlayer1 구독 → 트랙 메타 캐시.
2. iAP wrapper 의 캐시 갱신 요청 수신.
3. (선택) 스티어링휠 버튼 이벤트 수신 → 폰 쪽 AVRCP 로 `Next/Previous/PlayPause` 전달. 이 경로가 완성되면 "Pi 에 스티어링휠 연결 → 폰에서 곡 넘기기" 가 성립.

### 7.4 소프트웨어 레이어 요약 다이어그램

```
┌────────────────────────────────────────────────────────────────────┐
│                            Pi Zero 2 W                             │
│                                                                    │
│  ┌──────────────┐    AVRCP meta    ┌──────────────────┐            │
│  │ BlueZ D-Bus  │─────────────────▶│ user-agent(new)  │            │
│  │ MediaPlayer1 │                  │ D-Bus listener   │            │
│  └──────┬───────┘                  └────┬─────────────┘            │
│         │ (Bluetooth AVRCP)             │ UNIX socket              │
│         ▼                               ▼                          │
│  ┌──────────────┐     audio      ┌──────────────────┐              │
│  │   BlueALSA   │────────────▶   │ Go iAP wrapper   │              │
│  │  (a2dp sink) │                │ (extends oandrew │              │
│  └──────┬───────┘                │  /ipod client)   │              │
│         │ snd-aloop                └────┬─────────────┘            │
│         ▼                               │ read/write               │
│  ┌──────────────┐                       ▼                          │
│  │ g_ipod_audio │                ┌──────────────────┐              │
│  │ (UAC1 card)  │                │   /dev/iap0      │              │
│  └──────┬───────┘                │ (g_ipod_gadget)  │              │
│         │                        └────┬─────────────┘              │
│         └──── USB ENDPOINTS ──────────┘                            │
│                     │                                              │
└─────────────────────┼──────────────────────────────────────────────┘
                      │ USB-A
                      ▼
              ┌────────────────┐
              │  Outlander     │
              │  MMCS head     │
              │  unit          │
              └────────────────┘
```

새로 추가될 블록은 "user-agent(new)" 와 "Go iAP wrapper" 의 확장 부분. 기존 T2 오디오 경로(BlueALSA → aloop → g_ipod_audio)는 건드리지 않는다.

---

## 8. 참조

- [`oandrew/ipod-gadget`](https://github.com/oandrew/ipod-gadget) — Pi 커널 모듈 + 설치 디렉토리. 기준 브랜치 `master`, snapshot 2026-04-19. 소스: `gadget/ipod.h`, `gadget/ipod_gadget.c`, `gadget/ipod_audio.c`, `gadget/ipod_hid.c`.
- [`oandrew/ipod`](https://github.com/oandrew/ipod) — Go 클라이언트 단독 레포. `cmd/ipod` 하위에 iAP 프레임 처리 로직이 위치.
- [`xtensa/PodEmu`](https://github.com/xtensa/PodEmu) — 본 문서의 인용 주축. 주 파일 `app/src/main/java/com/rp/podemu/OAPMessenger.java` (2619 lines). PodEmu 소스 파일 상단 Javadoc 코멘트는 30-pin iAP 프로토콜 공개 설명 페이지 `adriangame.co.uk/ipod-acc-pro.html` 를 원전으로 기재 — 현 시점 생존 여부는 미검증(link-rot 가능성), 필요 시 archive.org 에서 재확인.
- **"iPod Accessory Protocol Interface Specification"** — Apple이 과거 MFi 프로그램 참가자에게 배포한 PDF. 공식 다운로드 경로 없음. 검색 힌트: `search: 'iPod Accessory Protocol Interface Specification PDF'` / `search: 'iAP protocol lingo reference'`. 본 문서는 이 PDF 를 직접 인용하지 않는다 ― 공개 소스로 확인 가능한 PodEmu/ipod-gadget 만 근거로 삼는다.
- **Linux kernel USB gadget subsystem 문서** — 커널 소스 트리의 `Documentation/usb/gadget_multi.rst`, `Documentation/usb/gadget_configfs.rst`, `Documentation/usb/gadget_printer.rst` 등. configfs 기반 composite gadget 구조를 이해하려면 이 디렉토리가 진입점이다. 온라인 미러: [kernel.org docs](https://www.kernel.org/doc/html/latest/usb/index.html).
- 본 레포 교차참조:
  - `docs/research-ipod-gadget.md` §1 — upstream 레포 상태 및 커밋 snapshot.
  - `docs/iap-auth-deep-dive.md` Stage 4 — wire-level 역공학 진입 절차. 본 문서의 §4 커맨드 테이블을 diff 기준선으로 사용한다.
  - `docs/triage.md` §2 — "인식은 되는데 재생 안 됨" 실제 증상과 본 문서의 AiR mode 미구현 gap 의 관계.

---

## 9. 본 문서 사용 지침 (for future-self)

- T2 합격 이후 스티어링휠/메타데이터 확장을 검토하는 시점에 **출발점** 으로 읽는다.
- 실 기기에서 버튼 이벤트를 캡처하게 되면 §5 표의 `unverified` 항목을 수정한다.
- upstream 이 메타데이터 핸들링을 추가하는 PR 을 머지하면 §6.1/6.3 의 "구현 안 됨" 문장을 갱신한다. 그 전까지는 "현재 없다" 가 정확한 사실.
- iAP2 대응이 필요해지면 (Outlander가 아닌 신차종으로 범위가 확장되면) **본 문서는 iAP1 전용** 이므로 별도 `docs/iap2-messages.md` 를 신설한다.
