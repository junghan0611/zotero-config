# zotero-config

**AI가 쿼리할 수 있는 지식 저장소로서의 재현 가능한 서지 워크플로우**

> Zotero를 AI 에이전트가 이해하고 참조할 수 있는 메타 지식 허브로 변환하세요.

[![English](https://img.shields.io/badge/English-README.md-blue)](README.md)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Work in Progress](https://img.shields.io/badge/status-WIP-yellow.svg)](https://github.com/junghan0611/zotero-config)

---

## 🎯 왜 이 프로젝트인가?

**문제**: AI 에이전트는 무엇이든 답할 수 있지만, 그것이 **당신의** 지식을 쌓아주지는 않습니다.

논문을 읽습니다. AI가 요약해줍니다. 좋습니다! 그런데 당신에게 남은 것은? 단절된 사실들. 개인 아카이브 없음. 대화 맥락 없음.

**해결책**: Zotero를 **쿼리 가능한 지식 저장소**로

- 📚 당신의 아카이브: 논문만이 아니라—영상, 팟캐스트, 카페, 삶의 순간들
- 🤖 AI 에이전트가 **당신의 라이브러리를 쿼리**합니다 (MCP 경유)
- 🔗 서지 노트가 당신과 에이전트 사이의 **공유 맥락**이 됩니다
- 📖 독서 워크플로우: **포착 → 쿼리 → 연결 → 출현**

**철학**: 인생은 한 권의 책. 모두가 저자다. 당신의 어쏠로지(anthology)를 만드세요.

---

## 얻을 수 있는 것

**인간을 위해:**
- ✅ 재현 가능한 Zotero 설정 (NixOS 준비, Git 동기화)
- ✅ 한국십진분류 citation key (`book-pkm2024`)
- ✅ Org-mode/LaTeX용 BibTeX 자동 내보내기
- ✅ 자기 완결형 워크스페이스 (분산된 설정 없음)

**AI 에이전트를 위해:**
- ✅ MCP 통합: 라이브러리에 대한 시맨틱 검색
- ✅ PDF 주석 쿼리: "이 논문에서 내가 하이라이트한 게 뭐지?"
- ✅ 맥락 인식 대화: "내가 읽은 관련 논문 찾아줘"
- ✅ 지식 고고학: "2년 전에 나는 무슨 생각을 하고 있었지?"

---

## 🏗 작동 방식

**간단한 흐름:**

```
당신 → Zotero → MCP 서버 → AI 에이전트
```

1. **당신이 포착**합니다: 논문/영상/노트를 Zotero에
2. **Better BibTeX**가 citation key를 생성합니다 (`book-pkm2024`)
3. **MCP 서버**가 라이브러리를 인덱싱합니다 (시맨틱 검색)
4. **AI 에이전트**가 대화 중 쿼리합니다

**대화 예시:**

> **당신**: "지식 그래프에 대해 연구하고 있어"
> **에이전트** (MCP로 Zotero 쿼리): "이 주제에 대한 논문이 3개 있네요. 2020년 논문 하나가 PKM 시스템과의 연결을 강조하고 있어요. 당신의 주석을 참조할까요?"

---

## 📚 기능

### 핵심 구성요소

- ✅ **한국십진분류(KDC)**
  - Citation key 형식: `book-title2024`, `blog-title2024`, `wiki-title`, ...
  - 타입별 접두사: `book`, `blog`, `wiki`, `film`, `doc`, `web`, `news`, `person`, `dict`, `art`
  - LaTeX/Org-mode 통합을 위한 재현 가능한 키

- ✅ **Better BibTeX 통합**
  - `.bib` 파일 자동 내보내기 (Git 추적)
  - Org-mode Quick Copy: `Ctrl+Shift+C` → citation key
  - 커스텀 postscript: `callnumber`, `datemodified`, `dateadded` 필드

- ✅ **MCP (Model Context Protocol) 지원**
  - 시맨틱 검색: 개념 기반 논문 발견
  - PDF 주석 추출 및 검색
  - 깊이 있는 쿼리를 위한 전문(full-text) 인덱싱
  - Claude Desktop, Cline 등과 통합

- ✅ **Attanger 플러그인**
  - 아이템 타입별 첨부파일 자동 정리
  - 소스 디렉토리 모니터링
  - 설정 가능한 파일 타입 필터

- ✅ **재현 가능한 설정**
  - NixOS/Home-Manager 호환
  - 자기 완결형 워크스페이스 구조
  - Git에서 버전 관리되는 플러그인 XPI 파일
  - 경로 변수가 있는 설정 템플릿

---

## 📂 디렉토리 구조

```
zotero-config/
├── plugins/               # Zotero 플러그인 (XPI 파일)
│   ├── better-bibtex@iris-advies.com.xpi
│   └── zoteroattanger@polygon.org.xpi
├── config/                # Better BibTeX 설정
│   └── betterbibtex-preferences-nixos.json
├── docs/                  # 문서
│   ├── MCP-INTEGRATION.md
│   ├── SETUP-GUIDE.md
│   └── DEWEY-CLASSIFICATION.md
├── scripts/               # 자동화 스크립트
│   ├── setup.sh
│   └── mcp-setup.sh
└── workspace/             # 로컬 워크스페이스 (추적 안 함)
    ├── data/              # Zotero 데이터베이스 (.gitignore)
    ├── files/             # 첨부파일 (.gitignore)
    ├── exports/           # 자동 내보낸 BibTeX
    └── incoming/          # Attanger 소스 (.gitignore)
```

---

## 🚀 빠른 시작

### 1. 저장소 클론

```bash
git clone https://github.com/junghan0611/zotero-config.git ~/zotero
cd ~/zotero
```

### 2. Zotero 설치

**NixOS/Home-Manager:**
```nix
home.packages = with pkgs; [ zotero ];
```

**Ubuntu/Debian:**
```bash
sudo apt install zotero
```

### 3. MCP 서버 설치 (선택사항이지만 권장)

```bash
# AI 에이전트 통합을 위해 54yyyu/zotero-mcp 설치
uv tool install "git+https://github.com/54yyyu/zotero-mcp.git"

# 로컬 Zotero 데이터베이스로 설정
zotero-mcp setup --local

# 또는 Zotero Web API 사용 (클라우드 동기화)
zotero-mcp setup --no-local \
  --api-key YOUR_API_KEY \
  --library-id YOUR_LIBRARY_ID

# 시맨틱 검색 데이터베이스 구축
zotero-mcp update-db --fulltext
```

### 4. Zotero 설정

```bash
# 설정 스크립트 실행 (작성 중)
./scripts/setup.sh

# 또는 수동으로:
# 1. plugins/에서 플러그인 설치
# 2. config/에서 Better BibTeX 설정 가져오기
# 3. 데이터 디렉토리를 workspace/data/로 설정
```

---

## 🤖 MCP 통합

### MCP란?

**Model Context Protocol (MCP)**는 AI 에이전트가 외부 데이터 소스에 접근할 수 있게 합니다. Zotero MCP로:

- 🔍 **시맨틱 검색**: 키워드가 아니라 개념으로 논문 찾기
- 📝 **주석 접근**: PDF 하이라이트와 노트 쿼리
- 🔗 **맥락 인식**: 에이전트가 대화 중 독서 기록 참조
- 📊 **메타 분석**: 전체 라이브러리에서 통찰 생성

### 지원하는 MCP 서버

| 서버 | 기능 | 최적 용도 |
|-----|------|-----------|
| **[54yyyu/zotero-mcp](https://github.com/54yyyu/zotero-mcp)** | 시맨틱 검색, PDF 주석, 전문 인덱싱 | **추천** - 가장 완전함 |
| [kaliaboi/mcp-zotero](https://github.com/kaliaboi/mcp-zotero) | 컬렉션 쿼리, 기본 검색 | 간단한 웹 API 통합 |
| [kujenga/zotero-mcp](https://pypi.org/project/zotero-mcp/) | Python 기반, Docker 지원 | Python 워크플로우 |

### 사용 예시

```python
# AI 에이전트가 Zotero 라이브러리를 쿼리
"2020년 이후 발표된 지식 그래프 관련 논문 찾아줘"
"PKM 시스템 논문에서 내 주석이 뭐였지?"
"이 개념을 Collection C3의 책들과 연결해줘"
```

자세한 설정은 [docs/MCP-INTEGRATION.md](docs/MCP-INTEGRATION.md) 참조.

---

## 📖 사용 사례

### AI 에이전트와 함께하는 독서 워크플로우

**이전 (전통적):**
1. 논문 읽기 → 수동 노트 → 단절된 지식

**이후 (에이전트 통합):**
1. **포착**: citation key와 함께 Zotero에 저장 (`book-pkm2024`)
2. **쿼리**: AI 에이전트에게 관련 논문 찾아달라고 요청
3. **연결**: 에이전트가 당신의 주석과 라이브러리 참조
4. **출현**: 대화 맥락에서 새로운 통찰

### 디지털 가드닝

- **Org-mode 통합**: 노트에 citation key 직접 삽입
- **Denote 링킹**: `[[book-title2024]]` 서지 항목으로 링크
- **Emacs 워크플로우**: Quick Copy → citation 삽입 → `.bib` 자동 업데이트

### 지식 고고학

AI 에이전트가 잊혀진 연결을 재발견하도록 돕습니다:
- "2년 전에 이 주제에 대해 뭘 읽었지?"
- "내 독서 기록에서 패턴을 찾아줘"
- "X에 대한 내 생각에 어떤 책들이 영향을 줬지?"

---

## 🔗 링크

- **디지털 가든**: [notes.junghanacs.com](https://notes.junghanacs.com)
- **Zotero 메타 노트**: [meta/20240320t110018](https://notes.junghanacs.com/meta/20240320t110018)
- **Bib 폴더**: [notes.junghanacs.com/bib/](https://notes.junghanacs.com/bib/)
- **Zotero 그룹 라이브러리**: [@junghanacs](https://www.zotero.org/groups/5570207/junghanacs/library)

---

## 🛠 상태

🚧 **작업 중** - Building in public!

**완료:**
- [x] 저장소 구조
- [x] 플러그인 백업 (Better BibTeX v7.0.50, Attanger v1.3.8)
- [x] 설정 템플릿
- [x] MCP 아키텍처 설계

**진행 중:**
- [ ] MCP 설치 스크립트
- [ ] 문서화 (MCP 통합, 설치 가이드)
- [ ] 한국십진분류 가이드
- [ ] NixOS Home-Manager 모듈

---

## 🤝 기여

개인 설정이지만, 자유롭게:
- 워크플로우 질문은 이슈로 남겨주세요
- Fork해서 자신만의 서지 시스템에 적용하세요
- MCP 통합 경험을 공유해주세요

---

## 📜 라이선스

MIT License - 자유롭게 사용하고 수정하세요!

---

**저자**: [@junghanacs](https://github.com/junghan0611)
**생성일**: 2025-10-11
**철학**: 인생은 한 권의 책 (Life is a book)
