# iAP Auth Deep-Dive Runbook (T3)

`docs/triage.md`의 failure mode #1 또는 #2에서 product_id 소진만으로 해결이 안 될 때 진입하는 **심층 복구 runbook**이다. 4 stage로 구성되며, **각 stage의 실패 criterion이 명확하게 다음 stage의 트리거**가 되도록 설계되어 있다.

- 트리거 경로: `docs/triage.md` §1 or §2 → 본 문서 Stage 1 시작.
- 원전 정책: `CLAUDE.md` §"Scope discipline" — **FM transmitter pivot은 명시적 거부**(사용자 정책 2026-04-19). 본 문서의 어떤 stage에서도 FM transmitter는 fallback이 아니다.
- 상위 레퍼런스:
  - `docs/research-ipod-gadget.md` (product_id tiering, upstream caveats)
  - `docs/triage.md` (본 문서를 호출하는 상위 runbook)
  - `scripts/product-id-loop.sh` (Stage 1의 실행 도구)
  - 업스트림: [oandrew/ipod-gadget](https://github.com/oandrew/ipod-gadget), [oandrew/ipod](https://github.com/oandrew/ipod), [xtensa/PodEmu](https://github.com/xtensa/PodEmu)

Stage 진행 규칙:

| Stage | 목표 | 소요 상수 | 실패 criterion → 다음 stage |
|-------|------|-----------|-----------------------------|
| 1 | product_id 전수 소진 | 후보 44개 × ~1~3분/후보 | 전수 소진에도 재생 불가 → Stage 2 |
| 2 | MFi chip add-on feasibility **검토** (구매/구현 아님) | 문서 작업 + 공급처 조사 | kernel-side 통합 가능성이 없거나 현실적 난이도가 불가 수준 → Stage 3 |
| 3 | upstream issues / forks 스캔 및 패치 후보 선별 | 이슈/PR/포크 grep + 빌드 검증 | 적용 가능한 패치가 없음 → Stage 4 |
| 4 | iAP 프로토콜 역공학 (end-of-line) | Wireshark usbmon + 로직 분석 | **해결 실패 시 프로젝트 iAP 경로 종결.** FM transmitter로 fallback하지 않음. |

---

## Stage 1 — product_id 전수 소진

### 목표

업스트림 `doc/apple-usb.ids`에 등재된 **53개 Apple USB product_id** 중 DFU/WTF/Recovery 모드(9개)를 제외한 **44개 유효 후보**를 Outlander MMCS에 모두 시험하여, 재생까지 성공하는 ID가 존재하는지 여부를 확정한다.

### 도구와 데이터 원전

- 실행 스크립트: `/opt/bt2iap/scripts/product-id-loop.sh` (레포 경로: `/Users/2026editor/Documents/proj/bt2iap/scripts/product-id-loop.sh`)
- 후보 원전: `docs/research-ipod-gadget.md` §2.1 (전체 테이블, 53개) / §2.2 (우선순위 Tier A~D)
- 후보 parsing: 스크립트가 `/opt/bt2iap/docs/research-ipod-gadget.md`에서 markdown 테이블의 1열 hex 값을 추출. 테이블 미발견 시 fallback hardcoded list(`0x1297 0x1267 0x129a 0x129c 0x1261 0x126a 0x1260`)로 수행.

### Tier 우선순위 (§2.2 요약)

```
Tier A (최우선): 0x1261 0x1260 0x1262 0x1263 0x1265
Tier B:        0x1266 0x1267 0x1207 0x1208 0x1209 0x120a
Tier C:        0x1297 0x12a0 0x1294 0x1292 0x1290 0x1291
Tier D:        나머지 iPhone/iPad/Shuffle 후보 (최후 시도)
```

A → B → C → D 순서를 지키는 이유는 Outlander 출시 시기(2007~2012 MY)와 가장 잘 매칭되는 iPod Classic / Nano 2~5세대가 Tier A에 모여있기 때문이다.

### 실행 절차 — interactive mode

기본(dry-run) 모드는 "manual inspection required" 로그만 찍고 넘어가므로 실제 탐색에는 **interactive 모드**가 필요하다.

```bash
# Pi에서 실행. MMCS UI를 보면서 각 후보마다 y/n/quit로 응답.
sudo BT2IAP_INTERACTIVE=1 /opt/bt2iap/scripts/product-id-loop.sh
```

interactive 모드에서 스크립트가 각 후보에 대해 하는 일:

1. 기존 iPod gadget stack을 unload.
2. `load-gadget.sh --product-id=<id>` 로 재로드.
3. 5초 대기 후 `/dev/iap0` 존재 여부 로그.
4. **프롬프트: "Did MMCS recognize the device? (y/n/quit)"**
   - `y` / `Y` / `yes` → 이 ID로 성공, 스크립트 종료 코드 0.
   - `n` 또는 기타 → 다음 후보로 진행.
   - `q` / `quit` → 사용자 중단, 종료 코드 130.

### 성공 criterion (Stage 1 합격선)

다음 **둘 중 하나**에 해당하면 Stage 1 성공으로 간주한다.

1. **재생까지 성공** — 스마트폰 → Pi (BT A2DP) → MMCS 스피커로 소리가 실제로 나온다. 가장 확실한 성공.
2. **최소한 enumeration 이후 단계까지 진입** — MMCS가 "iPod"로 인식한 뒤 곧바로 사라지지 않고 트랙 리스트 로딩 UI까지 진행한다. 소리는 아직 없더라도 auth 장벽은 일단 넘은 상태로 본다. 이 경우 Stage 2로 즉시 넘어갈 필요는 없고, `docs/triage.md` §4 (오디오 경로 failure mode #4) 점검 루틴으로 먼저 돌아간다 — 경로 끊김 가능성이 더 높다.

### 실패 criterion (Stage 2 트리거)

- **44개 후보 전부에 대해 `n` 응답** → Stage 1 실패 확정. Stage 2로 진입.
- 중간에 특정 후보에서 MMCS UI가 잠깐 iPod으로 잡히지만 즉시 사라지는 패턴이 반복 → auth 계열 문제 가능성이 크므로 Stage 2 진입을 서두른다. 이 경우 해당 "잠깐 잡히는" product_id를 기록해 두면 Stage 2의 kernel 드라이버 레벨 디버깅에서 기준점이 된다.

### 운영 팁

- 운전 중 탐색하지 말 것. 주정차 상태 또는 벤치 테스트(차량 전원 ON, 주차 상태)에서만 interactive loop를 돌린다.
- 각 후보별 dmesg 패턴을 기록해두면 Stage 3 (upstream 이슈 스캔) 및 Stage 4 (역공학) 진입 시 필터링 단서가 된다. `docs/runbook-log-$(date +%Y%m%d).md` 류의 로컬 노트 파일을 권장(레포에 커밋하지 말 것 — 현장 메모는 로컬에 한정).

---

## Stage 2 — MFi chip add-on feasibility 검토

### MFi란 무엇인가, 왜 필요할 수 있나

**MFi** (Made for iPod/iPhone/iPad)는 Apple이 주변기기 제조사에게 라이선스하는 하드웨어 인증 체계다. Apple Authentication Coprocessor(이른바 "MFi chip")는 I2C로 연결되는 작은 보안 IC로, 호스트(iPod 자체 또는 Lightning 액세서리)가 iAP 세션 시작 시 이 칩에 시도(challenge)를 보내고 응답(response)으로 카운터사인을 얻어 진위를 증명한다.

`oandrew/ipod-gadget` README는 "currently it works only if the host device doesn't authenticate the iPod"라고 명시한다. 즉, **Outlander MMCS가 iPod를 인증하는 쪽**이라면 (우리가 보기에 #17 Mitsubishi 이슈가 그런 케이스로 읽힌다) ipod-gadget 소프트웨어만으로는 인증에 응답할 수 없고, 외부 MFi chip + 커널/드라이버 통합이 필요할 수 있다.

**주의: T3는 feasibility 검토(문서 단계)까지다.** 사용자 정책 및 `.omc/specs/deep-interview-pre-pi-prep.md` §Non-Goals에 "MFi 인증 칩 **구현** — T3에서 feasibility 검토는 하지만 실제 회로/드라이버는 구현 보류"로 명시되어 있다. 본 Stage는 "실제로 해낼 수 있는가 / 얼마나 어려운가 / 얼마나 드는가"의 답을 문서로 확정하는 것이 목적이다.

### 조달 옵션 (feasibility — URL은 실시간 확인 필요)

hobbyist가 MFi chip을 확보하는 경로는 이론상 3가지지만 실제로 조달이 쉬운 쪽은 후자 2개에 가깝다.

| Channel | 현실성 | 비고 |
|---------|--------|------|
| Apple MFi 공식 프로그램 | 사실상 불가 | 법인 등록 + NDA + 심사 통과 필요. 개인 hobbyist 대상이 아니다. |
| MFi chip breakout board (Adafruit / 서드파티 리셀러) | 제한적 | 공식 재판매 경로 없음. 서드파티 재고가 간헐적으로 등장(search: "MFi chip breakout adafruit"). 정품 여부는 개별 확인 필요. |
| AliExpress / Taobao "MFi-less" 변형 칩 | 접근성 높음 / 품질 편차 큼 | "iAP authentication chip", "MFi 인증 칩 복제" 등의 키워드로 검색(search: "MFi authentication IC aliexpress"). Lightning 케이블에 쓰이는 복제 IC와 30-pin 시대 MFi IC는 형상·인터페이스가 다르므로 구매 전 iPod-gadget 스택과 호환 가능한 **I2C MFi coprocessor** 인지 스펙 확인 필수. |

구체 URL을 본 문서에서 단정하지 않는 이유는, hobbyist 시장에서 해당 부품 가용성이 수시로 바뀌기 때문이다. 독자는 검색 키워드를 시작점으로 삼아 현 시점의 공급처를 확인한다.

### 하드웨어 요구 (회로 수준)

MFi coprocessor chip의 공개된 인터페이스는 대체로 아래와 같다(제너레이션마다 다르지만 공통점 위주):

- **I2C 버스**: Pi의 GPIO 중 I2C1(`GPIO2=SDA`, `GPIO3=SCL`)을 사용. 3.3V logic.
- **전원**: 3.3V VCC, GND.
- **리셋 라인**: 일부 세대에서 RESET/SHUTDOWN 핀이 별도. GPIO 하나 추가 배정 필요.
- **풀업 저항**: SDA/SCL에 각각 4.7kΩ pull-up (Pi는 내부 pull-up이 약해 외부 추가 권장).

Pi Zero 2 W의 GPIO 헤더에 breakout을 직결하면 회로 자체는 단순하지만, **커널 드라이버 측에서 이 I2C 디바이스를 iAP 인증 요청 flow에 끼워 넣는 통합**이 본 Stage의 핵심 난제다.

### 소프트웨어 통합 요구 (커널 드라이버 수준)

현재 `oandrew/ipod-gadget`의 `g_ipod_gadget.ko`는 iAP 메시지 파서 + configfs 기반 gadget 등록만 수행하며, **외부 MFi coprocessor를 호출하는 훅이 없다**. 따라서 실제 통합에 들어간다면 최소 아래 작업이 필요하다:

1. `gadget/ipod.c` (또는 인증 flow가 있는 파일)에서 iAP 인증 challenge 수신 지점을 식별.
2. 해당 지점에서 I2C 슬레이브(MFi chip)로 challenge 전달 → response 수신 → iAP reply에 포함시키는 콜백 추가.
3. I2C 통신은 user-space daemon에 위임하거나 (`/dev/i2c-1` 열어서 처리), 커널 내부에서 `i2c_client` API로 처리.
4. kernel build + 재시험.

현재 upstream 코드 경로에 이 훅이 없다는 것은 Stage 3 (upstream scan)에서도 확인할 포인트다 — 만약 누군가 이미 같은 작업을 한 fork가 있다면 상당한 시간을 아낄 수 있다.

### Feasibility 체크리스트

| 항목 | 상태 | 확인 방법 |
|------|------|-----------|
| MFi chip 단품 구매 가능 여부 | TBD — 개별 확인 | search: "MFi authentication IC", "Apple coprocessor breakout" |
| Pi Zero 2 W의 I2C1 헤더 접근 | OK (GPIO2/3) | Pi 40-pin 핀맵 확인, 이미 다른 GPIO 사용 중인지 점검 |
| 3.3V 전원 및 pull-up 저항 확보 | 쉬움 | 일반 전자공작 부품 |
| 커널 드라이버에 인증 훅 포함 여부 (upstream) | **없음** (현재) | `oandrew/ipod-gadget` 소스 grep: `i2c`, `mfi`, `auth` 검색 |
| 커널 드라이버에 인증 훅 포함 여부 (fork) | TBD | Stage 3로 이월 — `gh api /repos/oandrew/ipod-gadget/forks` 로 전수 스캔 |
| 작업 난이도 추정 | 커널 C + I2C 프로토콜 + iAP challenge/response 포맷 이해 필요 | 역량 평가 |

### 상위 이슈 참조

upstream `oandrew/ipod-gadget` 이슈 트래커에서 MFi 인증 chip 통합을 **정식 키워드**로 명시한 issue는 현재 기준(2026-04-19 확인) 제목 레벨로는 눈에 띄지 않는다. 그러나 아래 이슈들은 auth/MFi 관련 논의가 본문에 등장할 가능성이 높아 Stage 3에서 먼저 들여다볼 가치가 있다:

- [#17 Mitsubishi detects iPod, but doesn't play audio](https://github.com/oandrew/ipod-gadget/issues/17) — 우리 차종과 가장 가까운 케이스.
- [#15 Car Display Shows Unsupported](https://github.com/oandrew/ipod-gadget/issues/15) — 인식/재생 단계에서 멈춤.
- [#24 Car display shows unreadable device (Volvo v70 2015)](https://github.com/oandrew/ipod-gadget/issues/24) — 다른 차종이지만 패턴 유사.
- [#33 Cannot get it to work with 2015 TLX](https://github.com/oandrew/ipod-gadget/issues/33) — 신형 head unit 사례.

이들 이슈 본문에 "MFi" 또는 "auth chip" 언급이 있는지 여부는 Stage 3에서 상세 grep으로 확인.

### 비용 및 공수 추정

실제 구현까지 간다고 가정할 때의 추정치(문서상 feasibility 숫자, 구현은 보류):

| 항목 | 추정 |
|------|------|
| 부품비 (MFi chip breakout + 케이블 + 저항 등) | ₩30,000 ~ ₩80,000 (공급처에 따라 편차 큼) |
| 커널 드라이버 수정 공수 | 경험자 1~2주, 초심자 3~6주 |
| 검증 공수 (벤치 + 차량 시험 + 회귀) | 별도 1~2주 |

hobbyist가 혼자 수행하기엔 만만한 작업이 아니며, Stage 3에서 이미 동일 작업을 수행한 fork/patch가 발견되면 공수가 크게 줄어든다. 따라서 **Stage 2 feasibility 검토가 끝나면 반드시 Stage 3로 내려가서 upstream 쪽 기존 작업물 유무부터 확인한다** — Stage 2 결론이 "문서상 가능" 이더라도 실제 착수 전에 Stage 3를 거쳐야 한다.

### Stage 2 출구 조건

- **Stage 2 feasibility 긍정 (단품 조달 가능 + 커널 통합 경로 식별 가능)** → 즉시 구매/구현에 들어가지 않고 **Stage 3 우선**. upstream 기 작업이 있으면 그쪽을 먼저 검증.
- **Stage 2 feasibility 부정 (공급 완전 불가 또는 커널 통합 경로 없음)** → Stage 3로 이월하되, Stage 3에서도 돌파구가 없으면 Stage 4 (역공학)로 이동.

---

## Stage 3 — upstream ipod-gadget 스캔 (issues + forks)

### 목표

`oandrew/ipod-gadget` 레포 자체 및 **42개 존재하는 fork**(2026-04-19 기준, `docs/research-ipod-gadget.md` §1)에서 auth/MFi/특정 차량 대응 목적으로 작성된 패치, 이슈 해결 로그, 닫힌 PR 본문 등을 전수 조사한다. upstream은 활동이 sparse하지만 커뮤니티 fork 쪽에 누군가의 땀이 있을 가능성을 무시하지 않는다.

### 진입 커맨드

```bash
# auth/MFi 관련 이슈 검색 (state=all 이어야 닫힌 것도 포함)
gh issue list -R oandrew/ipod-gadget --state all --search "auth" --limit 100
gh issue list -R oandrew/ipod-gadget --state all --search "MFi" --limit 100
gh issue list -R oandrew/ipod-gadget --state all --search "authentication" --limit 100

# Mitsubishi 및 유사 차종 관련 이슈
gh issue list -R oandrew/ipod-gadget --state all --search "Mitsubishi" --limit 100
gh issue list -R oandrew/ipod-gadget --state all --search "Outlander" --limit 100

# 전체 PR 목록 (auth 관련 닫힌 PR이 중요)
gh pr list -R oandrew/ipod-gadget --state all --limit 100

# Fork 전수 목록 (활동 있는 fork 선별용)
gh api /repos/oandrew/ipod-gadget/forks?per_page=100 \
  --jq '.[] | {name:.full_name, pushed:.pushed_at, fork:.fork}' \
  | sort -k2
```

### 현재(2026-04-19 스냅샷 기준) 직접 관련 이슈 목록

`gh api /repos/oandrew/ipod-gadget/issues?state=all&per_page=50` 응답에서 auth/재생/차량 호환성 관점으로 뽑은 목록 (본 문서 작성 시점 기준):

| 번호 | 제목 | 상태 | 비고 |
|------|------|------|------|
| [#17](https://github.com/oandrew/ipod-gadget/issues/17) | Mitsubishi detects iPod, but doesn't play audio | closed | **우리 차종과 동일 벤더.** 본문 상세 읽기 필수. |
| [#33](https://github.com/oandrew/ipod-gadget/issues/33) | Cannot get it to work with 2015 TLX | open | 신형 head unit, 동일 계열 실패 사례. |
| [#24](https://github.com/oandrew/ipod-gadget/issues/24) | Car display shows unreadable device (Volvo v70 2015) | open | enumeration 단계 실패. |
| [#15](https://github.com/oandrew/ipod-gadget/issues/15) | Car Display Shows Unsupported | open | 동 계열. |
| [#11](https://github.com/oandrew/ipod-gadget/issues/11) | 2011 Nissan Murano "Reading file..." | open | Outlander와 MY 겹침. |
| [#28](https://github.com/oandrew/ipod-gadget/issues/28) | Unable to get things to work on a Pi Zero 2W | open | **우리 HW와 동일.** |
| [#36](https://github.com/oandrew/ipod-gadget/issues/36) | Cooper F56 Pitfalls and Caveats | open | 최신 차량 팁 정리 이슈. |
| [#34](https://github.com/oandrew/ipod-gadget/issues/34) | How exactly are you supposed to wire the Pi up to the car? | open | 차량-Pi 배선 가이드. 전원 분리 확인 용도. |
| [#32](https://github.com/oandrew/ipod-gadget/issues/32) | Build error on Pi Zero 2 W on Raspbian 12 (bookworm) | closed | 빌드 이슈 — Pi Zero 2 W + bookworm 조합. |
| [#29](https://github.com/oandrew/ipod-gadget/issues/29) | [Fix?] Build fails with ... error ... for Linux 6.9.10 | closed | 커널 6.9 빌드 수정. |
| [#19](https://github.com/oandrew/ipod-gadget/issues/19) | All looks good, but can't stream sound | closed | 스트리밍 실패 사례. |
| [#18](https://github.com/oandrew/ipod-gadget/issues/18) | 0x64 "RequestApplicationLaunch" error | closed | iAP 메시지 오류 디버깅 샘플. |
| [#30](https://github.com/oandrew/ipod-gadget/issues/30) | Added DKMS and auto-install script | open PR | 편의 PR. |

진입 우선순위 (읽기 순서 추천):

1. **#17 (Mitsubishi)** — 본문 + 해결/종결 방식 확인. 동일 벤더 사례가 유일하게 존재하는 데이터 포인트다.
2. **#28 (Pi Zero 2W)** — 우리 HW 환경과 직결.
3. **#15, #24, #33** — enumeration 실패 패턴 공통점 찾기.
4. **#36 (Cooper F56)** — 최신 차량 대응 팁이 문서화된 이슈.
5. **#18 (RequestApplicationLaunch)** — iAP 메시지 레벨 디버깅이 필요하면 참고.

### Fork 스캔 전략

```bash
# 가장 최근에 push된 fork만 상위 10개 추출 (활성 fork 우선)
gh api /repos/oandrew/ipod-gadget/forks?per_page=100 \
  --jq '[.[] | {name:.full_name, pushed_at, description}] | sort_by(.pushed_at) | reverse | .[0:10]'

# 특정 fork에서 upstream 대비 차이 확인
FORK="someuser/ipod-gadget"
gh api "/repos/${FORK}/compare/master...master" --jq '{ahead: .ahead_by, behind: .behind_by}'
```

활성 fork 상위 10개에 대해 `gadget/` 디렉토리의 diff를 훑어 **auth / MFi / product_id 관련 커밋**이 있는지 확인한다. 있다면 해당 커밋 단위로 cherry-pick 후보로 올린다.

### 적용 가능한 upstream/fork 패치의 채택 기준

패치를 우리 빌드에 넣기 전에 다음 3가지를 반드시 확인:

1. **(a) 빌드 호환성**: Pi Zero 2 W의 현재 커널(6.12+)에서 추가 수정 없이 빌드되는가? 안 되면 `research-ipod-gadget.md` §3의 2025-08 HID 구조 변경 대응과 충돌 가능성이 있으므로 재작업이 필요할 수 있다.
2. **(b) product_id 파라미터 보존**: 현 `scripts/product-id-loop.sh`와 `load-gadget.sh`가 `product_id=` insmod 파라미터를 그대로 사용한다. 패치가 이 인터페이스를 깨뜨리면 Stage 1의 탐색 인프라를 재작업해야 한다.
3. **(c) 라이선스 호환**: upstream은 MIT. fork도 거의 MIT일 것이나, 극소수 fork가 다른 라이선스로 바뀌었을 수 있으므로 LICENSE 파일 확인.

### Stage 3 출구 조건

- **적용 가능한 패치 발견** → 로컬 fork에 cherry-pick → 빌드 → Pi에서 Stage 1 재실행(새 빌드로). 재시도 후에도 실패면 Stage 4.
- **적용 가능한 패치 없음** → Stage 4로 이동.
- **fork에 MFi chip 통합 코드가 완성되어 있음** → Stage 2의 구매 판단으로 역주행(feasibility → 실제 구현/구매). 이 경우에도 프로젝트 본 T3 범위에서는 "문서화 + 체크리스트"까지만 수행하고 실제 구매는 사용자 승인 후.

---

## Stage 4 — iAP 프로토콜 역공학 (last resort)

### 목표

실제로 **동일 MMCS + 실제 iPhone(CLAUDE.md에 의하면 이미 iPod으로 인식되는 개체)** 사이의 USB 트래픽을 캡처해, 우리 Pi gadget이 내보내는 트래픽과 차이(diff)를 좁혀가며 MMCS가 수용하는 정확한 wire format을 재구성한다.

### 선행 조건 (절대 서두르지 말 것)

- Stage 1 (product_id 전수 소진) 실패 확정.
- Stage 2 (MFi feasibility) 검토 결과가 문서화되어 있음.
- Stage 3 (upstream/fork 스캔) 결과 적용 가능한 패치 없음을 확정.

**Stage 4를 Stage 1~3보다 먼저 시작하는 것은 명시 금지.** 이 단계는 공수가 크고 장비가 필요하며, iAP 명세가 완전 공개되지 않은 영역이므로 역공학 자체도 완성 보장이 없다. 앞 단계의 결과가 Stage 4의 탐색 영역을 줄여준다.

### 참고 레퍼런스 프로젝트

- [`xtensa/PodEmu`](https://github.com/xtensa/PodEmu) — 30-pin dock 커넥터 시대의 iAP 구현 (Android 앱). **USB-A 경로인 우리에게 직접 실행 대상은 아니지만**, iAP 메시지 프레이밍·명령 코드·페이로드 해석의 실체 레퍼런스로 가치가 크다. Stage 4에서는 PodEmu의 메시지 정의 코드(`ipod/*.java` 등)를 펼쳐 둔 상태로 wire 캡처를 해석한다.
- [`oandrew/ipod-gadget`](https://github.com/oandrew/ipod-gadget) — 커널 쪽 iAP 파서 소스.
- [`oandrew/ipod`](https://github.com/oandrew/ipod) — Go 클라이언트 측 iAP 핸들러.

### 도구 체인

| Tool | 용도 | 참고 |
|------|------|------|
| **Wireshark + usbmon** | Linux 호스트(Pi 또는 별도 PC) 쪽에서 iAP USB traffic 캡처 | `modprobe usbmon` → Wireshark에서 `usbmonX` 인터페이스 선택 |
| **tshark (CLI)** | 장시간 캡처를 pcap으로 떨구기 | `tshark -i usbmon0 -w /tmp/iap.pcap` |
| **Saleae Logic Analyzer (8+ channel)** | USB D+/D- 직접 캡처 + decode | USB 1.1 Full-Speed(12Mbps)이므로 엔트리 급 Saleae로 충분. iAP 페이로드는 USB interrupt/bulk transfer 레벨에서 관찰. |
| **실제 iPhone** | "known-good" 세션의 비교 기준 | CLAUDE.md 명시: 이 head unit이 이미 iPhone을 iPod으로 인식하므로 **비교 기준선이 확보된 셈**. |
| **USB MITM 하드웨어 (옵션)** | 중간자 캡처용 USB 스니퍼 (e.g., LogicPort, Beagle USB 480) | 고가. hobbyist에게는 Saleae로 대체 가능. |

### 표준 역공학 절차

1. **known-good 세션 캡처 (iPhone ↔ MMCS)**
   - Pi와 별개 환경. Linux 노트북 + USB isolator + MMCS 연결.
   - 또는 Linux 기반 SBC(BeagleBone/Pi 등)에 usbmon 켜고 iPhone을 이 SBC의 USB-A 포트를 통해 MMCS에 pass-through. (MITM setup)
   - 대안: 하드웨어 USB 스니퍼를 MMCS USB-A와 iPhone 사이에 인라인 삽입.
   - `tshark -i usbmonX -w iphone-mmcs-known-good.pcap` 로 최소 5분 세션 캡처 (enum + 재생 시작).
2. **우리 gadget 세션 캡처 (Pi ↔ MMCS)**
   - 동일 방식으로 우리 Pi gadget과 MMCS 사이 트래픽을 `pi-mmcs-candidate.pcap` 로 캡처.
   - Stage 1에서 "잠깐 iPod으로 잡혔다가 사라지는" 특정 product_id를 사용하는 것이 좋다 — 진입 깊이가 깊을수록 diff가 유의미하다.
3. **diff**
   - Wireshark로 양쪽 pcap의 iAP 메시지 sequence를 나란히 열고:
     - enumeration descriptor 차이 (string descriptor 내 vendor/product 이름, 기기 클래스 등)
     - 초기 iAP 핸드셰이크 메시지(lingo 0x00 General) 차이
     - 인증 관련 lingo (예: lingo 0xea Authentication, 또는 IDPS/IDL 관련 메시지) 차이
   - PodEmu 소스의 `lingo` enum 및 메시지 핸들러를 참조해 식별되지 않는 바이트 시퀀스의 의미를 유추.
4. **우리 gadget에 격차만큼 패치**
   - 식별한 누락 메시지/잘못된 응답을 `g_ipod_gadget.ko` 또는 Go 클라이언트 (`/cmd/ipod`) 쪽에 추가/수정.
   - 빌드 후 재캡처 → 다시 diff → 수렴까지 iterate.
5. **수렴 criterion**
   - 우리 pcap이 known-good pcap과 **enum + auth 구간까지** 동일한 시퀀스를 출력하고, MMCS UI에서 재생까지 이어지면 역공학 성공.

### 위험 및 현실적인 한계

- 이 stage는 **공수 산정이 사실상 불가능**하다(iAP 일부 lingo가 문서화되지 않음). 몇 주 ~ 몇 달.
- iAP에 포함된 암호학적 인증(MFi auth challenge)은 wire만 봐서는 풀 수 없는 one-way 구조로 설계되어 있을 수 있다. 이 경우 Stage 4 내부에서 Stage 2(MFi chip 실제 구현)로 역주행해야 한다.
- 사용자 정책상 **Stage 4가 iAP 기반 복구 경로의 end-of-line**이다. Stage 4 실패 시:
  - FM transmitter fallback은 **여전히 선택지가 아니다** (2026-04-19 정책).
  - 대안은 "프로젝트 종결 후 별도 의사결정 루틴" — 본 문서의 범위를 벗어난다.

### Stage 4 명시 non-goal

- Stage 1~3을 skip 하고 바로 Stage 4로 진입하는 것.
- MFi chip을 준비하지 않은 상태에서 auth challenge의 암호학 부분을 깨뜨리려 시도하는 것 (성공 확률 극히 낮음, 시간 낭비).
- 상용 iAP 라이선스 코드를 획득하려 시도하는 것 (라이선스 위반 위험).

---

## Final note — runbook log 관리 및 stage 간 연결

모든 stage는 다음 stage에 **데이터**를 넘겨준다:

- Stage 1 → Stage 2: 시험한 product_id와 해당 dmesg 패턴 로그.
- Stage 2 → Stage 3: MFi chip feasibility 판단 결과 + 커널 통합 경로의 부재/존재 여부.
- Stage 3 → Stage 4: 채택 불가 판정된 patch 목록 + upstream 이슈 중 iAP 메시지 세부를 다룬 스레드 링크.
- Stage 4 → (end): 수렴하지 못한 wire-diff 증거 일체.

현장 operator는 별도의 runbook log 파일을 하나 유지하기를 권장한다. 예:

```bash
touch ~/bt2iap-runbook-$(date +%Y%m%d).md   # Pi 상에 로컬 보관
```

해당 파일은 **레포에 커밋하지 않는다** — 개인 메모 + 하드웨어별 세부가 섞여 있어 저장소 history에 적절치 않다. 필요한 학습 산출물만 본 문서(`iap-auth-deep-dive.md`) 또는 `research-ipod-gadget.md`로 흡수한다.

### 정책 재확인 (2026-04-19 고정, 재재확인)

- **FM transmitter로의 우회는 본 프로젝트의 모든 stage에서 선택지가 아니다.** `CLAUDE.md` §"Scope discipline" + `.omc/specs/deep-interview-pre-pi-prep.md` §Non-Goals에 명문화된 내용이다.
- Stage 4 실패 시의 후속 결정은 사용자 개입 사안이며, 본 runbook은 Stage 4까지가 커버 범위다.

### 본 문서의 버전과 진입 경로

- 진입 상위: `docs/triage.md` §1 (auth error) 또는 §2 (재생 불가 + product_id 소진 요건).
- 진입 도구: `scripts/product-id-loop.sh` (스크립트 내부에서 "Next step: consult /opt/bt2iap/docs/iap-auth-deep-dive.md" 로 본 문서를 참조한다).
- 상위 레포 snapshot 기준: 2026-04-19 (`docs/research-ipod-gadget.md` §1 참조).
