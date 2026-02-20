# zotero-config

**Headless 서지 워크플로우: Zotero Cloud API에서 citar 호환 BibTeX까지**

> Zotero GUI 없음. Better BibTeX 플러그인 없음. API와 스크립트와 Emacs만.

[![English](https://img.shields.io/badge/English-README.md-blue)](README.md)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## 이 프로젝트가 하는 일

Zotero Cloud API로 전체 라이브러리를 가져와서, 타입별로 분리된 citar 호환 BibTeX 파일을 생성하고, 새 citation key를 Zotero Cloud에 역동기화합니다.

```
./run.sh bib full       # 전체 동기화: 5,893 아이템 → 7개 BibTeX 파일 (~90초)
./run.sh bib sync       # 증분 동기화 (변경분만, 수초)
./run.sh bib status     # 동기화 상태 확인
./run.sh starred        # GitHub starred → github-starred.bib
./run.sh save <url>     # URL 저장 → Translation Server → Zotero Cloud
./run.sh server start   # Translation Server 시작 (localhost:1969)
./run.sh build          # bibcli 빌드 (AI 에이전트용 검색 CLI)
```

---

## 파이프라인

```
run.sh bib full|sync
│
├── 1. Zotero Cloud API에서 아이템 가져오기 (JSON, 페이지네이션)
│   └── /users/{id}/items/top?format=json&limit=100
│
├── 2. Citation key 생성 (gen-bibtex.py)
│   ├── 기존 citationKey 있음 → 그대로 유지
│   ├── book + ISBN → DATA4LIBRARY API → KDC 분류번호
│   │   └── 예: "802.041-김74ㄴ" (KDC-저자기호)
│   └── 나머지 → BBT 스타일 규칙
│       └── 예: "web-perplexity", "blog-AiVampire26"
│
├── 3. 타입별 BibTeX 파일 생성
│   ├── Book.bib      (1,463 엔트리)  ← book
│   ├── Online.bib    (2,610 엔트리)  ← webpage, blogPost, forumPost
│   ├── Software.bib  (1,082 엔트리)  ← computerProgram
│   ├── Reference.bib   (365 엔트리)  ← encyclopediaArticle, dictionaryEntry
│   ├── Video.bib       (239 엔트리)  ← videoRecording, film, tvBroadcast
│   ├── Article.bib      (69 엔트리)  ← journalArticle
│   └── Misc.bib         (62 엔트리)  ← 나머지 전부
│
├── 4. 새 citationKey 역동기화 → Zotero Cloud API (PATCH)
│
└── 5. 상태 저장 (.sync/last-version, items.json)

run.sh starred
│
└── GitHub starred repos → github-starred.bib (2,140 엔트리)
    └── gh api --paginate user/starred → jq → @software{} 엔트리
```

---

## Citation Key 패턴

| 타입 | 영어 | 한국어 (KDC) |
|------|------|-------------|
| book | `HowTakeSmart17` | `802.041-김74ㄴ` |
| book | `CLRSIntroductionAlgorithms09` | `005-포14ㅋ` |
| webpage | `web-perplexity` | — |
| blogPost | `blog-AiVampire26` | — |
| software | `200okchorganice24` | — |

ISBN이 있는 한국 도서는 [정보나루(DATA4LIBRARY)](https://data4library.kr/) API로 KDC 분류번호 + 4자리 저자기호를 조회합니다.

---

## 디렉토리 구조

```
zotero-config/
├── run.sh                 # 메인 진입점
├── scripts/
│   ├── zotero-to-bib.sh   # Zotero API 페처 (bash + curl + jq)
│   ├── gen-bibtex.py       # BibTeX 엔진 (Python, citar 호환)
│   ├── writeback-keys.sh   # citationKey → Zotero Cloud (PATCH)
│   ├── gh-starred-to-bib.sh # GitHub starred → BibTeX (gh + jq)
│   ├── run.sh              # Translation Server 관리
│   └── zotero-save-url.sh  # Translation Server 경유 URL 저장
├── bibcli/                 # AI 에이전트용 BibTeX 검색 CLI (Go)
│   ├── main.go             # CLI: search/show/list/stats
│   ├── parser.go           # BibTeX 파서 (8,000 엔트리 18ms)
│   ├── search.go           # 대소문자 무관 다중필드 AND 검색
│   └── SKILL.md            # Claude Code 스킬 정의
├── output/                 # 생성된 BibTeX 파일 (~/org/resources/에서 symlink)
│   ├── Book.bib
│   ├── Online.bib
│   ├── Software.bib
│   ├── Reference.bib
│   ├── Video.bib
│   ├── Article.bib
│   ├── Misc.bib
│   └── github-starred.bib
├── config/                 # BBT 설정 (참조용)
├── plugins/                # Zotero 플러그인 XPI (아카이브)
└── .sync/                  # 동기화 상태 (gitignore)
    ├── items.json           # 캐시된 Zotero 아이템
    ├── last-version         # 증분 동기화용 API 버전
    └── new-keys.json        # 대기 중인 citationKey 역동기화
```

---

## 설정

### 필수 요건

- `curl`, `jq`, `python3` (pip 패키지 불필요)
- Zotero 계정 + API 접근
- (선택) [정보나루 API 키](https://data4library.kr/) — KDC 분류번호 조회용

### 환경변수

프로젝트 루트에 `.envrc` 생성:

```bash
export ZOTERO_API_KEY="your-key"
export ZOTERO_USER_ID="your-user-id"
export DATA4LIBRARY_API_KEY="your-key"  # 선택, KDC 조회용
```

### 첫 실행

```bash
git clone https://github.com/junghan0611/zotero-config.git
cd zotero-config
# .envrc에 API 키 설정
./run.sh bib full    # 전체 동기화 (~6000 아이템, ~90초)
```

### Emacs 통합

`output/` 의 BibTeX 파일을 `~/org/resources/`에 symlink:

```bash
ln -s /path/to/zotero-config/output/Book.bib ~/org/resources/Book.bib
# ... 각 .bib 파일마다 반복
```

citar 설정:

```elisp
(setq citar-bibliography
      '("~/org/resources/Book.bib"
        "~/org/resources/Online.bib"
        "~/org/resources/Software.bib"
        "~/org/resources/Reference.bib"
        "~/org/resources/Video.bib"
        "~/org/resources/Article.bib"
        "~/org/resources/Misc.bib"
        "~/org/resources/github-starred.bib"))
```

---

## bibcli — BibTeX 검색 CLI

AI 에이전트가 전체 서지 데이터(8,030 엔트리)를 검색/조회하는 Go CLI. JSON 전용 출력, 외부 의존성 없음, 정적 바이너리.

```bash
./run.sh build                           # 빌드 + ~/.local/bin 설치
bibcli search "emacs" --max 5            # 전문 검색
bibcli search "한국" --type Book          # 한글 + 타입 필터
bibcli show "165.84-박82ㅅ"               # citation key로 전체 조회
bibcli stats                              # 파일별 통계
```

상세: [bibcli/SKILL.md](bibcli/SKILL.md)

---

## Translation Server

GUI 없이 URL을 Zotero Cloud에 직접 저장:

```bash
./run.sh server start              # localhost:1969 시작
./run.sh save "https://example.com" # URL을 Zotero에 저장
./run.sh server stop
```

[Zotero Translation Server](https://github.com/zotero/translation-server) 사용 (`~/repos/3rd/translation-server`에 클론).

---

## 링크

- **디지털 가든**: [notes.junghanacs.com](https://notes.junghanacs.com)
- **Zotero 그룹 라이브러리**: [@junghanacs](https://www.zotero.org/groups/5570207/junghanacs/library)

---

**저자**: [@junghanacs](https://github.com/junghan0611)
**철학**: 인생은 한 권의 책. 모두가 저자다.
