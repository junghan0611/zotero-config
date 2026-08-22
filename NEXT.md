# NEXT — zotero-config

> Disposable handoff. Steward public face: **`denote:20260304T105300`** (§zotero-config).
> After meaningful ops/doctrine change → update that botlog (히스토리 ± 현재 보고).
> Do not mint llmlog/new botlog for routine progress — that room + this file only.

# RAIL — 현재 좌표

- [x] **1. 다기기 diff 원인 관측** — cache 순서와 생성 시각이 BibTeX 출력으로 새고 있음을 확인
- [x] **2. 결정론 + 공유 출력면 구현** — 완전 byte-identical 렌더, `~/sync/org/resources/bib` 직접 출력
- [x] **3. 실컷오버** — Cloud 6,225건 full sync와 no-op sync, GitHub starred 2,420건까지 8개 live BibTeX로 확인
- [ ] **4. 어느 기기·하네스에서든 URL → 인용** ← CURRENT: org 담당자/OpenClaw가 같은 bibcli 입수 레일을 소비하도록 연결

현재 좌표: 1–3 완료 → 4 인터페이스 연결 대기

# NOW

- Current: live SSOT은 `$ZOTERO_BIB_DIR` (기본 `~/sync/org/resources/bib`)의 8개 BibTeX다. Zotero Cloud가 캡처 권위이고 각 기기의 `.sync/`는 사적 cache다. Git은 일상 등록·인용 경로 밖이다.
- Next: OpenClaw/org 담당자에 `save → 스타일·키 판단 → pin --sync → bibcli show` 한 세션 레일을 연결한다. 어느 기기에서도 자기 local `zotero-config`와 Cloud 자격으로 완료하고 Syncthing은 완성된 bib만 공유한다.
- Verify: `bibcli stats`는 8개 파일을 읽고, `save/pin --sync` 뒤 새 key가 `~/sync/org/resources/bib`에서 보이며, second sync는 byte·mtime 무변경이다.
- Blocker: 없음.
- Read: `agent-config/skills/bibcli/SKILL.md`, `.claude/skills/zotero-config/SKILL.md`, `scripts/zotero-to-bib.sh`, `scripts/lib-install.sh`, `tests/`.
- Do not touch: `.sync/`를 Git/Syncthing으로 공유하지 말 것; `dateAdded`/`dateModified`를 PATCH하거나 BibTeX에서 제거하지 말 것; KDC/data4library를 sync 본선에 넣지 말 것; 생성 시각을 shared `.bib`에 넣지 말 것; repo `output/`을 다시 만들지 말 것.

## RECENT (2026-08-22)

- **경로**: 모든 진입점(run.sh / zotero-to-bib / sanitize / starred / pin-item / bibcli)이
  `$ZOTERO_BIB_DIR`, 기본 `~/sync/org/resources/bib`를 본다. 옛 `~/org/resources` 잔재 없음.
  `output/` 복사 단계·publish/untrack 서사·`untrack-output.sh` 모두 제거.
- **결정론**: `(citationKey, Zotero item key)` 정렬 → 그 뒤 중복 접미사. 비식별화는
  **정렬 전에** (`scripts/sanitize_bib.py` = 규칙 SSOT). `% Updated:` 생성 시각 헤더
  **완전 제거** → 비교가 순수 바이트 동일성. `github-starred.bib`도 키 정렬 + 시각 헤더 없음.
- **설치**: staging → 바이트 비교 → 같은 파일시스템 rename. 렌더러와 Syncthing 데몬이
  같은 사용자로 돌므로 unix group은 의미 있는 불변식이 아니다 — group 계약/경고/복구
  스크립트(`fix-bib-perms.sh`)와 setgid·sudo 안내는 모두 제거했다.
- **커서 안전성**(컷오버 중단이 드러낸 사고): 옛 fetch 루프가 **페이지마다** `last-version`
  을 먼저 썼다 → 캐시 6223 그대로인데 커서만 35790. 재시도 시 44~63 페이지를 영원히
  건너뛴다. 이제 `fetch_items` 는 디스크에 아무것도 쓰지 않고,
  캐시 커밋(temp+rename) → 삭제 반영 → **그 다음에야** `commit_version`. 깨진 응답/중단이면
  옛 쌍이 그대로. 삭제 조회(`/deleted?since=`)가 실패·깨지면 `prune_deleted` 가 비정상
  종료하고 `do_sync` 는 커서를 커밋하지 않는다 (옛 코드는 warn 후 통과시켜, 그 삭제들을
  영영 못 보게 만들었다). 페이지는 파일로 모아 끝에서 한 번 합친다(옛 per-page jq concat 은 quadratic).
- **동시 실행 사고 + 단일 쓰기 락**: 두 개의 `bib full` 이 겹쳐 돌았고, 뒤엣것이 앞엣것의
  **활성** fetch staging 을 `rm -rf` 로 지워 앞엣것이 26페이지부터 잃고 `Fetched 0 items`
  로 끝났다 (캐시·커서는 0건 가드 덕에 무사). 원인은 내가 넣었던 블랭킷
  `rm -rf $SYNC_DIR/.fetch.*`. 이제 `.sync/.lock` 에 배타적 non-blocking `flock` 을 걸고
  (`full`/`sync`/`writeback`; `status` 는 무관), 잔여물 청소는 **60분 이상 된 것만** 한다.
  보유자 pid 가 죽었으면 강제로 깨지 않고 최대 10초 대기 후 획득.
- **starred 경로 구조적 결함**(렌더러와 같은 종류): jq 가 **raw 키로 정렬**한 뒤
  래퍼가 키를 치환해 최종 바이트에 역전이 생길 수 있었다. 이제 프로그램을
  `scripts/gh-starred.jq` 로 분리하고 `sanitize_bib.py --jq-filter` 가 주는 규칙을
  `sort_by` 전에 키에, 그리고 엔트리 본문에 적용한다. 규칙 하드코딩 없음.
  설치도 Zotero 렌더러와 같은 규율로 통일했다 (`scripts/lib-install.sh` 공유):
  bib 디렉터리 안 숨김 staging → 바이트 비교 → rename. 응답이 그대로면 재작성 없음
  (옛 코드는 매 실행마다 목적지에 직접 써서 mtime 을 흔들었다).
  테스트 시드 `GH_STARRED_INPUT` 으로 GitHub 없이 스크립트를 끝까지 검증한다.
- **BIBCLI_DIR 폐기**: 셸에 남은 낡은 `BIBCLI_DIR` 이 `--dir` 없는 bibcli 에게 폐기된
  8,361건을 먹였다. 이제 `--dir > ZOTERO_BIB_DIR > 기본값` 이고 `BIBCLI_DIR` 은 무시한다.
- **테스트**: `render-determinism.sh` 28, `bib-dir-and-install.sh` 20, `sync-cursor.sh` 25, `sync-lock.sh` 18, `starred-determinism.sh` 18,
  `render-determinism-live-cache.sh`. 전부 mktemp/mock 안에서만 돈다 (네트워크 없음).
- **Git**: 추적 중인 `output/*.bib`와 index는 이번 세션에서 손대지 않았다. 커밋/푸시 없음.

## LEDGER / SSOT

| Surface | Path |
|---------|------|
| Code | `~/repos/gh/zotero-config/` |
| Operator skill | `.claude/skills/zotero-config/SKILL.md` |
| Org intake skill | `agent-config` → `bibcli` skill (parent가 갱신) |
| Live bib SSOT | `$ZOTERO_BIB_DIR` = `~/sync/org/resources/bib/*.bib` — Syncthing 공유 |
| Device-local cache | `.sync/` — gitignored, 기기별 사적, 공유 금지 |
| Steward botlog | **`denote:20260304T105300`** — update intermittently when posture shifts |

## DO NOT

- New botlog/llmlog per session for this repo
- Reintroduce KDC API into `bib sync`
- Touch `dateAdded` via bulk enrich
- Leave URL capture without citeable key in the same session (org work)
- Put Git (pull/push/commit) back on the daily bibliography path
- Emit a generation timestamp into any shared `.bib`
