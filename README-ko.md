# zotero-config

**힣's Bibliographical Knowleable Archivalential Repositorological World-wide Toilet**

> 서지노트: 삶의 흔적을 담다

재현 가능한 Zotero 설정 with **한국십진분류체계** 워크플로우

> **English**: [README.md](README.md)

---

## 🌟 철학

지나치는 삶의 흔적들을 한 곳에 담는다.

조테로에는 책 뿐만 아니라 어제 본 영상, 오늘 나를 감동하게 한 음악, 어제 다녀온 멋진 까페도 포함된다. 모든 것을 노트로 만들 필요는 없다. 때가 되면 노트가 되는 것 뿐이다.

어쩌다보니 도서는 **한국십진분류(KDC)**로 정리한다. 인생은 한 권의 책. 하나의 서지노트에 한 사람의 인생이 담기곤 한다.

**#모두가저자다 #인생은한권의책 #어쏠로지(Anthology)**

---

## 📚 주요 기능

- ✅ **십진분류체계(Dewey Decimal Classification)**: Citation Key 자동 생성
  - `book-*` (도서), `blog-*` (블로그), `wiki-*` (백과사전)
  - `film-*` (영상), `doc-*` (문서), `web-*` (웹페이지)
  - `news-*` (뉴스), `person-*` (인터뷰), `dict-*` (사전), `art-*` (예술)
- ✅ **Better BibTeX**: LaTeX/Org-mode 완벽 통합
- ✅ **Auto Export**: BibTeX 파일 자동 내보내기 (Git 추적)
- ✅ **Attanger**: 첨부파일 자동 정리
- ✅ **Reproducible**: NixOS/Home-Manager 지원

---

## 📂 디렉토리 구조

```
zotero-config/
├── plugins/           # Zotero 플러그인 (XPI 파일)
│   ├── better-bibtex@iris-advies.com.xpi
│   └── zoteroattanger@polygon.org.xpi
├── config/            # Better BibTeX 설정
│   └── betterbibtex-preferences-nixos.json
├── docs/              # 문서 (설치 가이드, 워크플로우)
├── scripts/           # 자동화 스크립트
└── workspace/         # 작업 디렉토리 (로컬 전용)
    ├── data/          # Zotero 데이터 (.gitignore)
    ├── files/         # 첨부파일 (.gitignore)
    ├── exports/       # BibTeX 자동 내보내기
    └── incoming/      # Attanger 대기 파일 (.gitignore)
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

### 3. 설정 (작성 중)

```bash
./scripts/setup.sh
```

---

## 📖 문서

- [SETUP-GUIDE-ko.md](docs/SETUP-GUIDE-ko.md) - 설치 및 설정 가이드 (작성 중)
- [DEWEY-CLASSIFICATION-ko.md](docs/DEWEY-CLASSIFICATION-ko.md) - 십진분류 시스템 (작성 중)
- [MIGRATION-GUIDE-ko.md](docs/MIGRATION-GUIDE-ko.md) - NixOS 마이그레이션 (작성 중)

---

## 🔗 링크

- **디지털 가든**: [notes.junghanacs.com](https://notes.junghanacs.com)
- **Zotero 메타 노트**: [meta/20240320t110018](https://notes.junghanacs.com/meta/20240320t110018)
- **Bib 폴더**: [notes.junghanacs.com/bib/](https://notes.junghanacs.com/bib/)
- **Zotero 그룹**: [@junghanacs](https://www.zotero.org/groups/5570207/junghanacs/library)

---

## 🛠 상태

🚧 **작업 중** - Building in public!

- [x] 저장소 구조
- [x] 플러그인 백업 (Better BibTeX, Attanger)
- [x] 설정 템플릿
- [ ] 설치 스크립트
- [ ] 문서화
- [ ] NixOS 통합

---

## 📜 라이선스

MIT License - 자유롭게 사용하고 수정하세요!

---

**저자**: [@junghanacs](https://github.com/junghan0611)
**생성일**: 2025-10-11
