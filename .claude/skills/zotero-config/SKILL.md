---
name: zotero-config
description: "zotero-config 오퍼레이터 면 — Zotero Cloud 캡처 금고, 로컬 BibTeX SSOT. URL 한 장이면 save→에이전트 스타일·KDC 키 판단→pin --sync 로 같은 세션에 인용 가능 키 확정(시점 분리 금지). dateAdded 성스러움. sync 렌더는 네트워크 없음. org 에이전트 일상은 bibcli 스킬. 트리거: zotero-config, bib sync, save, pin, citation key, KDC, yes24, 담아줘, Book.bib, writeback, translation server."
user_invocable: true
---

# zotero-config — 메타 서지 운영 면

Repo: `~/repos/gh/zotero-config`.  
전역 읽기 CLI 스킬: `bibcli` (`agent-config/skills/bibcli` — 바이너리 + 검색 면).  
이 스킬은 **이 리포 오퍼레이터 핸드북**이다. `AGENTS.md`가 명령 표라면, 여기는
에이전트가 다시 물어보지 말아야 할 **경계와 반사신경**이다.

**공개 담당자 문서:** `denote:20260304T105300`
(`§zotero-config: 캡처 금고와 메타 서지의 얇은 손`).  
교리·경계·pin/컬렉션이 의미 있게 바뀌면 **그 방을 갱신** (히스토리 + 필요 시 현재 보고).
새 botlog/llmlog 기본 금지. 세션 핸드오프는 리포 `NEXT.md`.

## 0. 한 줄 교리 (SSOT)

```text
Zotero Cloud  = 캡처 금고 (phone / browser Connector / save URL)
~/sync/org/resources/bib/*.bib = 메타 서지 SSOT — 렌더가 **여기에 직접** 내려앉는다
org notes     = 읽기·해석·인용 소비 층  (#+reference: / #+print_bibliography:)
```

### 기기 대칭 — 중앙 쓰기 주체가 없다

어느 기기의 org 담당자든 그 자리에서 `save` / `pin` / `bib sync` 를 돌린다.
Zotero Cloud가 캡처 권위, 각 기기의 `.sync/`는 그 기기의 사적 캐시,
Syncthing이 나르는 것은 **live bib 디렉터리 하나뿐**이다.

- 출력면: `$ZOTERO_BIB_DIR` (기본 `~/sync/org/resources/bib`). 렌더러와 bibcli가
  **같은 한 개의 환경변수**를 본다. `BIBCLI_DIR`은 폐기·무시 (셸 프로필에 남은
  낡은 값이 `--dir` 없는 bibcli에 폐기된 목록을 먹이던 사고가 있었다).
- 일상 서지 등록에 git 명령은 등장하지 않는다.
- repo `output/`은 이 리포가 관리하는 대상이 아니다.
- `.sync/`는 Git에도 Syncthing에도 올리지 않는다 — 공유해야 할 산출물은 이미
  렌더된 `.bib`다.

- **bibcli가 보여주는 것**만이 “서지로 인정된 것”이다. Zotero에만 있고 sync 안 된
  항목은 아직 SSOT에 없다.
- YouTube 별표 목록, 브라우저 북마크, 임의 스크랩 API는 **경계를 넘는 일** —
  bibcli/이 리포의 일이 아니다. 가치 있는 것만 Zotero에 담기고, 담긴 것만 pull한다.
- Zotero에 역할을 더 얹을수록 손 수정이 는다. **BBT·GUI 플러그인·citation-key
  플러그인은 제거된 상태**가 정답이다. sync 렌더 폴백은 `gen-bibtex.py`(네트워크 없음).
  책 KDC 키는 **에이전트/사람의 판단**으로 `pin` 할 때 심는다 — data4library 필수가 아니다.

### 이 리포의 정체성

공개하는 것은 “이 책 읽어라”가 아니다.  
공개하는 것은 **서지 목록 전체**와 그 목록을 **가꾸는 과정**이다.

- 다른 사람에게 개별 책 추천 가치는 거의 없다.
- 따라 할 필요도 없다.
- 그래도 이 과정을 공개하는 것 자체가 의미의 추천이다.
- 그래서 유연해야 하는 판단(십진분류의 ‘대략’, 역자 표기, shorttitle 취향)을
  코드 본선에 깊게 박지 않는다. **의식은 스킬에, 렌더는 얇은 코드에.**

## 1. 두 갈래 유입 (책이 특별하다)

| 갈래 | 무엇인가 | 태도 | 에이전트 |
|---|---|---|---|
| **Book** | 십진분류(KDC 감각)·저자·역자·citation key를 가꾼 장서 | 신중히, 그러나 **한 세션에 키까지 확정** | sync 중 KDC API 금지. 에이전트가 스타일+KDC 판단 후 `pin --sync`. 대량 자동·dateAdded 위험 금지 |
| **Online / Video / Software / …** | 유튜브·블로그·웹·레포 캡처 | 한 세션에 키+분류 | `save --json` → 가벼운 스타일·키 → `pin --sync` (Category 자동). 폰 캡처만 된 것은 `bib sync` |

코드는 얇게. 판단·수선 절차는 스킬(이 문서 + **전역 bibcli 스킬**)에.

## 1b. URL → 인용 가능 키 (한 세션 — 시점 분리 금지)

org 담당 에이전트가 “서지 없다”고 멈추지 않게 하는 **기본 레일**.
담기만 하고 키를 다음으로 미루지 않는다. `book-…` 폴백을 최종 키로 남기지 않는다.

```text
[1] save     Translation Server → Zotero Cloud (날것)
[2] style    에이전트 판단: title/author/translator/date/shorttitle/abstract/ISBN…
[3] classify 에이전트 판단: KDC 감각 citationKey (API 필수 아님)
             중복 검사: bibcli show KEY 가 없어야 함
[4] pin      ./run.sh pin --sync --json '{zoteroKey, citationKey, …}'
[5] cite     org 노트에 #+reference: KEY 즉시
```

```bash
cd ~/repos/gh/zotero-config
./run.sh server status || ./run.sh server start
./run.sh save --json "URL"
# → saved[].zoteroKey  (citationKey 는 아직 폴백/없음일 수 있음)

# 에이전트가 스타일 + 유일 키 결정 후:
./run.sh pin --sync --json '{
  "zoteroKey": "…",
  "citationKey": "001.3-김74ㅁ",
  "title": "말하지 않고 말하기",
  "creators": [{"creatorType":"author","name":"김정운"}],
  "date": "2026-05-11",
  "publisher": "21세기북스",
  "ISBN": "9791173579721",
  "language": "ko",
  "abstractNote": "…",
  "url": "URL"
}'
# → { citationKey, synced:true }  dateAdded 불변 검증 포함
bibcli show "001.3-김74ㅁ"
```

### 스타일 규칙 (yes24 등)

- title: `제목 | 저자 | 출판사 - 예스24` → **제목만**
- creators: `lastName=저, firstName=김정운` → `{"name":"김정운"}` (역자는 translator)
- date / ISBN / publisher: 페이지·메타에서 채움 (비어 있으면 에이전트가 회수)
- abstract: 군더더기 정리, 내 문체로 짧게
- citationKey: 기존 장서 패턴 참고 (`bibcli search` 동저자/동주제).
  형식 `분류-저자기호` 예: `001.3-김74ㅁ`, `843.5-조68ㅍ2`.
  **완벽한 KDC 불필요** — 분류 축 하나 + **SSOT 유일**이 핵심.
- `bibcli lookup`은 선택 보조. 타임아웃·실패해도 에이전트 판단으로 진행.

### 사람 손 경로 (여전함)

브라우저 Connector로 담은 뒤 Zotero GUI에서 손질해도 된다.
에이전트 레일은 **대체 레일** — org 작업 중 URL만 있을 때 특히.

### pin 계약

- whitelist PATCH only (`scripts/pin-item.py`)
- **dateAdded 절대 불변** (변경 시 실패)
- citationKey 로컬 SSOT 중복 시 거부 (같은 항목 재핀은 허용)
- **Zotero 컬렉션 자동 분류** (로컬 type-split bib의 역방향, Unfiled 탈출):
  - 책: citationKey `0…9` 시작 → `Book` + `N00-…` (`001.3-…` → **000-정보**)
  - 비책: itemType → Category 리프 (`videoRecording`→Video, `blogPost`→BlogPost,
    `webpage`→@Web, `computerProgram`→Software, `encyclopediaArticle`→Wikipedia …)
  - 매핑 SSOT: `scripts/pin-item.py` (Book 섹션 키는 enrich-books와 동일)
  - 제어: `fileUnder: "Video"` / `collections: ["…"]` / `noCollections: true`
- `--sync`로 pull까지 한 방에 → Emacs/citar/org 즉시
- **일상 입수 스킬은 bibcli** (유튜브·책·블로그 URL 원샷). 이 문서는 리포/경계 SSOT.

### 성스러운 필드 — `dateAdded` / `dateModified`

- 시간축에서 **이 책이 언제 서지에 들어왔는가**는 매우 귀한 정보다.
- 책 내용은 다시 찾을 수 있다. 모델도 안다.
- 되돌릴 수 없는 것은: **힣이 그 시점에 그 주제를 만났다**는 맥락.
- 어설픈 enrich / 일괄 PATCH / 재생성 파이프라인이 이 필드를 잃거나 덮으면
  **대형 사고**다.
- 에이전트 금지: dateAdded/dateModified를 잃을 수 있는 일괄 수정,
  “편하자”는 책 메타 자동 재작성, 검증 없는 Cloud mutation.

### 결정론 계약 (같은 라이브러리 → 같은 바이트)

렌더 결과는 Zotero 항목의 **집합**에만 의존한다. 기기별 `.sync/items.json`의
배열 순서, `last-version`, 돌린 시각 — 어느 것도 바이트에 새지 않는다.
어느 기기든, 몇 번을 다시 돌리든 **완전히 byte-identical**.

- 모든 항목을 `(citationKey, Zotero item key)`로 정렬한 **뒤에** 중복 접미사
  (`-1`/`-2`)를 매긴다. 그래서 접미사까지 결정론적이다.
- 비식별화(`sanitize_bib.py`)도 **정렬 전에** 돈다. 규칙이 fallback 키 안의
  식별자를 바꾸기 때문에, 정렬 뒤에 sanitize 하면 최종 바이트에 역전이 남는다
  (실측: `web-tbdhnygokweol` 이 `web-gordonnovakjr` 보다 위에 있었다).
- **생성 시각 헤더가 아예 없다** (`% Updated:` 제거). 비교는 순수 바이트 동일성이고,
  같으면 실파일을 건드리지 않는다 → Syncthing에 no-op 전파가 없다.
- `github-starred.bib`도 **같은 규칙원**에서 온다: `sanitize_bib.py --jq-filter` 가
  주는 필터를 jq 가 `sort_by` **전에** 키에 적용하고, 엔트리 본문에도 적용한다.
  셸에 규칙을 하드코딩하지 않아 두 렌더러가 갈라질 수 없다. 생성 시각 없음.
- Zotero의 `dateAdded`/`dateModified`는 BibTeX `dateadded`/`datemodified`로
  남는다. 이건 렌더 메타데이터가 아니라 **내용**이다.
- 설치는 `$BIB_DIR` 안 staging → 바이트 비교 → 같은 파일시스템 rename
  (`scripts/lib-install.sh` 를 두 렌더러가 공유). citar/bibcli의 glob이 반쯤 쓰인
  파일을 보지 않고, staging 잔여물도 남지 않는다. `github-starred.bib` 도 같은 경로라
  응답이 그대로면 파일과 mtime을 건드리지 않는다.

검증 (네트워크·Cloud 없음, 실사용 bib 디렉터리 안 건드림 — 전부 mktemp 안에서):

```bash
./tests/render-determinism.sh             # fixture 계약 테스트
./tests/render-determinism-live-cache.sh  # 이 기기 실제 캐시로 재확인
./tests/bib-dir-and-install.sh            # 출력면 경로 + staged install
./tests/sync-cursor.sh                    # 커서 안전성 (mock curl)
```

### 커서 계약 — `.sync/last-version`은 캐시보다 앞서지 않는다

`last-version`은 **커서**다. 다음 증분 sync가 그 이후 항목만 요청하므로,
커서가 캐시(`items.json`)보다 앞서면 그 사이 페이지를 영원히 건너뛴다.

실측 사고: `bib full`이 페이지 44/63에서 kill 됐는데 옛 루프가 **페이지마다**
커서를 먼저 써서, 캐시는 6223(옛것) 그대로인데 커서만 35790으로 튀었다.

```text
전 페이지 fetch → 캐시 커밋(temp+rename) → 삭제 반영 → 그 다음에야 커서 커밋
```

삭제 반영도 이 순서의 일부다. `/deleted?since=` 는 **옛 커서**를 실은 요청에만
삭제를 보여주므로, 그 요청이 실패하거나 깨지면 `prune_deleted` 가 비정상 종료하고
`do_sync` 는 커서를 커밋하지 않는다. 경고만 하고 넘기면 그 삭제들을 영영 못 본다.

중단·타임아웃·깨진 응답이 마지막 단계 전에 오면 옛 (캐시, 커서) 쌍이 그대로 남는다.

### 단일 쓰기 락 — 동시에 두 sync 를 돌리지 않는다

`pin --sync`, `save --sync`, 손으로 돌린 `bib full`, OpenClaw 봇이 동시에 `.sync` 를
건드릴 수 있다. **실측 사고**: 두 번째 `bib full` 이 첫 번째의 **활성** fetch staging 을
지워서, 첫 번째가 26페이지부터 조용히 잃고 `Fetched 0 items total` 로 끝났다.

- `full`/`sync`/`writeback` 은 배타적 non-blocking `flock` 을 먼저 잡고,
  못 잡으면 보유자 pid 와 함께 정직하게 거부한다. `status` 는 읽기 전용이라 무관.
- 락은 fd 에 걸려 프로세스가 죽으면 커널이 해제한다. 보유자 pid 가 이미 없으면
  남을 강제로 깨지 않고 최대 10초만 기다린다.
- staging 잔여물 청소는 **60분 이상 된 것만**. 사고를 만든 블랭킷 `rm -rf` 는 제거했다.

검증: `./tests/sync-lock.sh`
남은 비대칭은 의도적이고 무해하다 — 캐시가 커서보다 새로우면 다음 sync가 superset을
다시 받고 upsert 병합이 흡수한다.

### sync 본선과 키

```text
bib sync / gen-bibtex.py  = 네트워크 없는 렌더
  · 기존 citationKey → 그대로
  · 없음 → book-/web-… 로컬 폴백만 (최종 키 아님)
./run.sh pin --sync       = 스타일+키 확정 (에이전트 판단 후)
bibcli lookup             = 선택 후보 (data4library)
./run.sh enrich           = 레거시 위험 구역 — 기본 경로 아님
./run.sh bib writeback    = new-keys.json 일괄 핀 (레거시; pin 선호)
```

**금지:** sync가 data4library에 의존. **금지:** 담기만 하고 키 확정을 다음 세션으로 미루기.

## 2. 핵심 반사신경 — 캡처 뒤 sync (묻지 마라)

GLG는 휴대폰·브라우저에서 Zotero로 유튜브/블로그/웹을 담는다.  
로컬 bib는 그때 자동으로 안 바뀐다. **에이전트가 pull 해야 SSOT가 갱신된다.**

다음이면 **사용자가 `sync 해줘`라고 말하기 전에** 실행한다:

```bash
cd ~/repos/gh/zotero-config && ./run.sh bib sync
```

트리거 예:
- “방금 Zotero에 담았어 / 폰으로 저장했어 / 브라우저 커넥터로 넣었어”
- “아까 그 유튜브·블로그 서지 찾아봐”
- “최근에 넣은 거 bibcli로 읽어”
- 노트에 URL만 있고 로컬 bib에 아직 키가 없을 때 (에이전트 유입은 `save --sync --json`)

그 다음:

```bash
bibcli search "구별되는 단어들" --max 10
# 또는 URL 조각 exact
bibcli search "youtube.com/watch?v=…" --max 5
```

**금지:** sync 없이 “bib에 없는데요”로 끝맺기.  
**금지:** sync 할 때마다 사용자에게 허가 구하기 (read-only pull이다).

`bib sync` / `bib full`은 Zotero Cloud에 **쓰지 않는다**. 금고 → 로컬 렌더만.

## 3. 세 접근 시나리오 (명령 표)

| # | 필요 | 명령 | 네트워크 |
|---|------|------|----------|
| 1 | 이미 SSOT에 있는 것 인용 | `bibcli search` → `show` | 없음 |
| 2 | 새 URL을 지금 인용 | `./run.sh server status \|\| ./run.sh server start` → `./run.sh save --sync --json <url>` | Translation Server + Cloud |
| 3 | 금고 → SSOT 갱신 | `./run.sh bib sync` | Cloud read-only (렌더는 로컬 only) |

시나리오 1인데 **방금 외부 캡처**가 섞여 있으면 → 먼저 3, 그다음 1.

## 4. Mutation boundary

| 동작 | Cloud | 언제 |
|------|-------|------|
| `bib sync` / `bib full` | 읽기만 | 일상 pull. **KDC API 없음** |
| `save` / Connector | 항목 생성 | URL 캡처 |
| `pin --sync` | whitelist PATCH | 스타일+citationKey 확정. dateAdded 불변. org 원샷 |
| `bibcli lookup` | 없음 | 선택 후보 |
| `./run.sh enrich` | PATCH | 레거시 위험 — 기본 금지 |
| `bib writeback` | citationKey only | 레거시 일괄; 단건은 `pin` |
| `.bib` 손편집 | — | **금지** |

## 5. 경계 밖 (하지 마라)

- YouTube/브라우저 별표·재생목록 직접 수집
- MCP 서버로 Zotero 붙이기 (CLI + 스킬이 면)
- PDF fulltext·annotation 파이프를 이 리포에 얹기 (읽기 층은 org)
- live Zotero API를 bibcli 매검색마다 호출 (SSOT는 로컬 bib)
- BBT/GUI 플러그인 재도입
- `.sync/`를 Git이나 Syncthing으로 공유 (기기별 사적 캐시다)
- 일상 서지 등록 경로에 git pull/push/커밋을 끌어들이기
- 렌더 산출물에 생성 시각을 다시 넣기 (결정론이 깨진다)
- 캐시 커밋 **전에** `last-version`을 쓰기 (페이지 건너뜀 사고)
- `.sync` 를 락 없이 동시에 두 프로세스가 쓰기 (서로의 staging 을 지운다)
- `BIBCLI_DIR`을 다시 살리기 (출력면 환경변수는 `ZOTERO_BIB_DIR` 하나다)
- 책 키 대량 자동 생성·자동 writeback
- **sync 본선에 data4library/KDC 재도입**
- dateAdded/dateModified를 위험에 넣는 일괄 enrich
- `github-starred` 갱신을 “방금 웹 담은 거”와 혼동 (별도 `./run.sh starred`)

## 6. 스킬 이원화

| 스킬 | 자리 | 역할 |
|------|------|------|
| **zotero-config** (이 문서) | `zotero-config/.claude/skills/` | 교리·책 의식·성스러운 필드·sync 반사·mutation·run.sh |
| **bibcli** | `agent-config/skills/bibcli/` | 전역 검색 CLI, JSON, save 원샷, `lookup` 보조, `--dir $ZOTERO_BIB_DIR` |

어느 리포/세션에서든 서지를 찾으면 bibcli 스킬.  
이 리포 안을 만지거나 “Zotero에 담았는데” / 책 KDC 맥락이면 **이 스킬을 먼저**.

## 7. 빠른 명령

```bash
cd ~/repos/gh/zotero-config
./run.sh bib sync              # 일상 pull (read-only, network-free render)
./run.sh bib status
./run.sh bib full
./run.sh server status || ./run.sh server start
./run.sh save --json URL       # 캡처 (날것)
./run.sh pin --sync --json '…' # 스타일+키 확정 + SSOT 반영
./run.sh save --sync --json URL  # 웹/영상 등 폴백 키로 충분한 경우
./run.sh build
bibcli lookup ISBN|제목          # 선택 보조
./tests/render-determinism.sh    # 결정론 계약 검증
./tests/bib-dir-and-install.sh   # 출력면 경로 + staged install
./tests/sync-cursor.sh           # 커서 안전성 (mock curl)
./tests/sync-lock.sh             # 단일 쓰기 락 (동시 실행 거부)
./tests/starred-determinism.sh   # starred 정렬·비식별화 (합성 입력)
```

환경: `.envrc` — `ZOTERO_API_KEY`, `ZOTERO_USER_ID`,  
(선택) `DATA4LIBRARY_API_KEY` — **lookup/enrich 전용**, sync 불필요.  
출력면: `$ZOTERO_BIB_DIR` (기본 `~/sync/org/resources/bib`, Syncthing 공유).
상태: `.sync/` (gitignored, **기기별**) — `items.json`, `last-version`, `new-keys.json`.

## 8. 문서 라우팅

| 맥락 | 문서 |
|------|------|
| 운영 반사·책 의식·경계 (지금 읽는 것) | `.claude/skills/zotero-config/SKILL.md` |
| 명령·파이프라인 SSOT | `AGENTS.md` |
| 사람용 개요 | `README.md` |
| 전역 검색·URL 원샷 스킬 | `agent-config/skills/bibcli/SKILL.md` |
| **공개 담당자 얼굴** | `denote:20260304T105300` (간헐 갱신) |
| 세션 핸드오프 | `NEXT.md` |
| 설계 이력 | `docs/plans/` |
