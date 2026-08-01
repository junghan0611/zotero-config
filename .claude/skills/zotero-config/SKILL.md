---
name: zotero-config
description: "zotero-config 오퍼레이터 면 — Zotero Cloud는 캡처 금고, 로컬 BibTeX(~/org/resources)가 메타 서지 SSOT. 폰/브라우저로 담은 유튜브·블로그·웹을 에이전트가 읽으려면 먼저 bib sync. 책은 KDC·저자·역자까지 손으로 아끼고, 웹·영상은 담는 대로 pull. BBT/GUI/MCP 없음. 코드는 얇게, 디테일은 이 스킬과 bibcli 스킬. 트리거: 'zotero-config', 'bib sync', 'bibcli', '서지', 'citation key', 'Zotero 담았어', '방금 저장', 'citar', 'Book.bib', 'writeback', 'translation server'."
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
  플러그인은 제거된 상태**가 정답이다. 키 생성은 `gen-bibtex.py` 한곳.

## 1. 두 갈래 유입 (책이 특별하다)

| 갈래 | 무엇인가 | 태도 | 에이전트 |
|---|---|---|---|
| **Book** | 십진분류(KDC)·저자·역자·citation key를 수년 단위로 가꾼 유니크 장서 | 매일 안 넣음. 조심스럽게 손 큐레이션 | 자동 대량 생성·함부로 writeback 금지. `lookup`/data4library는 **교정 보조**(에이전트가 API로 후보를 찾아 사람이 판단). 완전 자동 목표 아님 |
| **Online / Video / Software / …** | 유튜브·블로그·웹·레포 등 흘러드는 캡처 | 담는 대로 가져오면 되는 편리 저장소 | 폰/브라우저 캡처 언급 시 **먼저 `bib sync`**, 그다음 bibcli |

코드 레벨은 얇고 견고하게. 디테일·예외·수선 절차는 스킬(이 문서 + bibcli)에 둔다.

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
| 3 | 금고 → SSOT 갱신 | `./run.sh bib sync` | Cloud read-only |

시나리오 1인데 **방금 외부 캡처**가 섞여 있으면 → 먼저 3, 그다음 1.

## 4. Mutation boundary

| 동작 | Cloud | 언제 |
|------|-------|------|
| `bib sync` / `bib full` | 읽기만 | 일상 pull. 기본 반사 |
| `save` / Connector | 항목 생성 | URL 유입 유일한 쓰기 경로(일상) |
| `bib writeback` | citationKey PATCH | **명시 요청만**. 책 KDC 키 핀 등. 루틴 sync 부작용 금지 |
| `.bib` 손편집 | — | **금지**. 다음 full에 덮임. 수선은 Zotero 항목 수정 후 sync |

책 키·메타 수선: Zotero에서 사람(또는 에이전트 보조)이 고치고 sync.  
`lookup`은 Zotero에 안 쓴다 — 후보 JSON만.

## 5. 경계 밖 (하지 마라)

- YouTube/브라우저 별표·재생목록 직접 수집
- MCP 서버로 Zotero 붙이기 (CLI + 스킬이 면)
- PDF fulltext·annotation 파이프를 이 리포에 얹기 (읽기 층은 org)
- live Zotero API를 bibcli 매검색마다 호출 (SSOT는 로컬 bib)
- BBT/GUI 플러그인 재도입
- 책 키 대량 자동 생성·자동 writeback
- `github-starred` 갱신을 “방금 웹 담은 거”와 혼동 (별도 `./run.sh starred`)

## 6. 스킬 이원화

| 스킬 | 자리 | 역할 |
|------|------|------|
| **zotero-config** (이 문서) | `zotero-config/.claude/skills/` | 교리·sync 반사·mutation·책/웹 갈래·run.sh |
| **bibcli** | `agent-config/skills/bibcli/` | 전역 검색 CLI 사용법, JSON 출력, save 원샷, `--dir ~/org/resources` |

어느 리포/세션에서든 서지를 찾으면 bibcli 스킬.  
이 리포 안을 만지거나 “Zotero에 담았는데” 맥락이면 **이 스킬을 먼저** 떠올린다.

## 7. 빠른 명령

```bash
cd ~/repos/gh/zotero-config
./run.sh bib sync              # 일상 pull (read-only)
./run.sh bib status            # last-version / 상태
./run.sh bib full              # 삭제 반영 포함 재빌드
./run.sh save --sync --json URL
./run.sh server status || ./run.sh server start
./run.sh build                 # bibcli 바이너리
./run.sh bib writeback         # 명시적 키 핀 only
```

환경: `.envrc` — `ZOTERO_API_KEY`, `ZOTERO_USER_ID`, (선택) `DATA4LIBRARY_API_KEY`.  
상태: `.sync/` (gitignored) — `items.json`, `last-version`, `new-keys.json`.

## 8. 문서 라우팅

| 맥락 | 문서 |
|------|------|
| 운영 반사·경계 (지금 읽는 것) | `.claude/skills/zotero-config/SKILL.md` |
| 명령·파이프라인 SSOT | `AGENTS.md` |
| 사람용 개요 | `README.md` |
| 전역 검색 스킬 | `agent-config/skills/bibcli/SKILL.md` |
| 설계 이력 | `docs/plans/` |
