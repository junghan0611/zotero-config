---
name: zotero-config
description: "zotero-config 오퍼레이터 면 — Zotero Cloud는 캡처 금고, 로컬 BibTeX(~/org/resources)가 메타 서지 SSOT. 폰/브라우저로 담은 유튜브·블로그·웹을 에이전트가 읽으려면 먼저 bib sync. 책은 yes24→Connector→손질→도서관 감각의 KDC 키까지 사람 의식; dateAdded/dateModified는 성스러움. 웹·영상은 담는 대로 pull. sync 본선은 네트워크 없는 렌더. BBT/GUI/MCP 없음. 코드는 얇게, 디테일은 이 스킬과 bibcli. 트리거: 'zotero-config', 'bib sync', 'bibcli', '서지', 'citation key', 'Zotero 담았어', '방금 저장', 'citar', 'Book.bib', 'writeback', 'KDC', '십진분류', 'translation server'."
user_invocable: true
---

# zotero-config — 메타 서지 운영 면

Repo: `~/repos/gh/zotero-config`.  
전역 읽기 CLI 스킬: `bibcli` (`agent-config/skills/bibcli` — 바이너리 + 검색 면).  
이 스킬은 **이 리포 오퍼레이터 핸드북**이다. `AGENTS.md`가 명령 표라면, 여기는
에이전트가 다시 물어보지 말아야 할 **경계와 반사신경**이다.

## 0. 한 줄 교리 (SSOT)

```text
Zotero Cloud  = 캡처 금고 (phone / browser Connector / save URL)
local *.bib   = 메타 서지 SSOT  (output/ → ~/org/resources/, citar + bibcli)
org notes     = 읽기·해석·인용 소비 층  (#+reference: / #+print_bibliography:)
```

- **bibcli가 보여주는 것**만이 “서지로 인정된 것”이다. Zotero에만 있고 sync 안 된
  항목은 아직 SSOT에 없다.
- YouTube 별표 목록, 브라우저 북마크, 임의 스크랩 API는 **경계를 넘는 일** —
  bibcli/이 리포의 일이 아니다. 가치 있는 것만 Zotero에 담기고, 담긴 것만 pull한다.
- Zotero에 역할을 더 얹을수록 손 수정이 는다. **BBT·GUI 플러그인·citation-key
  플러그인은 제거된 상태**가 정답이다. 키 생성 폴백은 `gen-bibtex.py` 한곳
  (네트워크 없음). 책 KDC 키는 **사람이 Zotero에 심는다**.

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
| **Book** | 십진분류(KDC 감각)·저자·역자·citation key를 수년 단위로 가꾼 유니크 장서 | 매일 안 넣음. 손 큐레이션 의식 | 자동 대량 생성·함부로 writeback·sync 중 KDC API **금지**. `bibcli lookup`/data4library는 **후보 보조**. 사람이 확정 |
| **Online / Video / Software / …** | 유튜브·블로그·웹·레포 등 흘러드는 캡처 | 담는 대로 가져오면 되는 편리 저장소 | 폰/브라우저 캡처 언급 시 **먼저 `bib sync`**, 그다음 bibcli |

코드 레벨은 얇고 견고하게. 디테일·예외·수선 절차는 스킬(이 문서 + bibcli)에 둔다.

## 1b. 책 유입 의식 (사람 손 — 코드가 대체하지 않음)

GLG가 책을 메타서지에 넣는 실제 절차. 에이전트는 이 의식을 **자동화로 대체하지
말고**, 보조·리마인드·후보 제시만 한다.

1. **찾기** — 주로 yes24.com 등 웹에서 책을 찾는다.
2. **캡처** — Firefox Zotero Connector로 Zotero Cloud 금고에 담는다.  
   이 시점의 항목은 아직 “내 스타일”이 아니다.
3. **손질 (Zotero에서)** — title, author, translator, date, shorttitle, abstract.  
   커넥터가 채운 값은 대략일 뿐; **내 스타일로** 고친다.
4. **citation key (십진분류 감각)**  
   - 주로 [수원시도서관 모바일](https://mob.suwonlib.go.kr/) 등에서 책 이름으로
     검색해 청구기호/분류를 **대략** 확인한다.
   - 완벽한 KDC 전문가 절차를 고집하지 않는다.
   - 바라는 것은 메타서지에 **분류 축 하나**를 더 심는 것.
   - 형식 예: `843.5-조68ㅍ2` (`@book{843.5-조68ㅍ2, ...}`).
5. **보조 (원할 때만)** — 에이전트 또는 `bibcli lookup <isbn|제목>`이
   data4library 후보를 보여 준다 → **사람이 키를 Zotero에 기입**.
6. **pull** — `./run.sh bib sync` → 로컬 `Book.bib` / `~/org/resources/`.
7. **writeback** — “Cloud 항목에 키를 핀하고 싶다”고 **명시할 때만**.  
   루틴 sync의 부작용으로 돌리지 않는다.

### 성스러운 필드 — `dateAdded` / `dateModified`

- 시간축에서 **이 책이 언제 서지에 들어왔는가**는 매우 귀한 정보다.
- 책 내용은 다시 찾을 수 있다. 모델도 안다.
- 되돌릴 수 없는 것은: **힣이 그 시점에 그 주제를 만났다**는 맥락.
- 어설픈 enrich / 일괄 PATCH / 재생성 파이프라인이 이 필드를 잃거나 덮으면
  **대형 사고**다.
- 에이전트 금지: dateAdded/dateModified를 잃을 수 있는 일괄 수정,
  “편하자”는 책 메타 자동 재작성, 검증 없는 Cloud mutation.

### sync 본선과 KDC

```text
bib sync / gen-bibtex.py  = 네트워크 없는 렌더
  · 기존 citationKey → 그대로
  · 없음 → book-/web-… 로컬 폴백만
bibcli lookup             = 원할 때 KDC/서지 후보 (data4library)
./run.sh enrich           = 명시적·위험 구역 (book- 보강; 함부로 금지)
./run.sh bib writeback    = 명시적 키 핀 only
```

**금지:** sync가 data4library에 의존해 멈추거나,  thrashing으로 키를 바꿔 쓰기.

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
bibcli search "구별되는 단어들" --dir ~/org/resources --max 10
# 또는 URL 조각 exact
bibcli search "youtube.com/watch?v=…" --dir ~/org/resources --max 5
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
| `bib sync` / `bib full` | 읽기만 | 일상 pull. 기본 반사. **KDC API 없음** |
| `save` / Connector | 항목 생성 | URL 유입 유일한 일상 쓰기 경로 |
| `bibcli lookup` | 없음 | KDC/서지 **후보**. 쓰는 손 아님 |
| `./run.sh enrich` | PATCH 가능 | **명시 요청만**. dateAdded 위험 구역. 기본 제안 금지 |
| `bib writeback` | citationKey PATCH | **명시 요청만**. 책 키 핀 등. 루틴 sync 부작용 금지 |
| `.bib` 손편집 | — | **금지**. 다음 full에 덮임. 수선은 Zotero 항목 수정 후 sync |

책 키·메타 수선: **Zotero에서 사람이 고치고** sync.  
에이전트는 후보·체크리스트·diff 확인. 확정 기입은 사람(또는 명시 위임).

## 5. 경계 밖 (하지 마라)

- YouTube/브라우저 별표·재생목록 직접 수집
- MCP 서버로 Zotero 붙이기 (CLI + 스킬이 면)
- PDF fulltext·annotation 파이프를 이 리포에 얹기 (읽기 층은 org)
- live Zotero API를 bibcli 매검색마다 호출 (SSOT는 로컬 bib)
- BBT/GUI 플러그인 재도입
- 책 키 대량 자동 생성·자동 writeback
- **sync 본선에 data4library/KDC 재도입**
- dateAdded/dateModified를 위험에 넣는 일괄 enrich
- `github-starred` 갱신을 “방금 웹 담은 거”와 혼동 (별도 `./run.sh starred`)

## 6. 스킬 이원화

| 스킬 | 자리 | 역할 |
|------|------|------|
| **zotero-config** (이 문서) | `zotero-config/.claude/skills/` | 교리·책 의식·성스러운 필드·sync 반사·mutation·run.sh |
| **bibcli** | `agent-config/skills/bibcli/` | 전역 검색 CLI, JSON, save 원샷, `lookup` 보조, `--dir ~/org/resources` |

어느 리포/세션에서든 서지를 찾으면 bibcli 스킬.  
이 리포 안을 만지거나 “Zotero에 담았는데” / 책 KDC 맥락이면 **이 스킬을 먼저**.

## 7. 빠른 명령

```bash
cd ~/repos/gh/zotero-config
./run.sh bib sync              # 일상 pull (read-only, network-free render)
./run.sh bib status            # last-version / 상태
./run.sh bib full              # 삭제 반영 포함 재빌드
./run.sh save --sync --json URL
./run.sh server status || ./run.sh server start
./run.sh build                 # bibcli 바이너리
bibcli lookup ISBN|제목        # KDC 후보 only (DATA4LIBRARY_API_KEY)
./run.sh bib writeback         # 명시적 키 핀 only
./run.sh enrich …              # 명시적·위험 — 기본 경로 아님
```

환경: `.envrc` — `ZOTERO_API_KEY`, `ZOTERO_USER_ID`,  
(선택) `DATA4LIBRARY_API_KEY` — **lookup/enrich 전용**, sync 불필요.  
상태: `.sync/` (gitignored) — `items.json`, `last-version`, `new-keys.json`.

## 8. 문서 라우팅

| 맥락 | 문서 |
|------|------|
| 운영 반사·책 의식·경계 (지금 읽는 것) | `.claude/skills/zotero-config/SKILL.md` |
| 명령·파이프라인 SSOT | `AGENTS.md` |
| 사람용 개요 | `README.md` |
| 전역 검색 스킬 | `agent-config/skills/bibcli/SKILL.md` |
| 설계 이력 | `docs/plans/` |
