# zotero-config

Reproducible Zotero configuration with **Korean Dewey Decimal Classification** workflow.

> **한글 문서**: [README-ko.md](README-ko.md)

---

## 🌟 Philosophy

Capture traces of life through bibliographic notes.

Not just books, but videos, music, cafes, and everything that touches your life. When the time is right, notes emerge naturally.

**#EveryoneIsAnAuthor #LifeIsABook #Anthology**

---

## 📚 Features

- ✅ **십진분류체계(Dewey Decimal Classification)**: Citation Key 자동 생성
  - `book-*`, `blog-*`, `wiki-*`, `film-*`, `doc-*`, `web-*`, ...
- ✅ **Better BibTeX**: LaTeX/Org-mode 완벽 통합
- ✅ **Auto Export**: BibTeX 파일 자동 내보내기 (Git 추적)
- ✅ **Attanger**: 첨부파일 자동 정리
- ✅ **Reproducible**: NixOS/Home-Manager 지원

---

## 📂 Directory Structure

```
zotero-config/
├── plugins/           # Zotero 플러그인 (XPI 파일)
├── config/            # Better BibTeX 설정
├── docs/              # 문서 (설치 가이드, 워크플로우)
├── scripts/           # 자동화 스크립트
└── workspace/         # 작업 디렉토리 (로컬 전용)
    ├── data/          # Zotero 데이터 (.gitignore)
    ├── files/         # 첨부파일 (.gitignore)
    ├── exports/       # BibTeX 자동 내보내기
    └── incoming/      # Attanger 대기 파일 (.gitignore)
```

---

## 🚀 Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/junghan0611/zotero-config.git ~/zotero
cd ~/zotero
```

### 2. Install Zotero

**NixOS/Home-Manager:**
```nix
home.packages = with pkgs; [ zotero ];
```

**Ubuntu/Debian:**
```bash
sudo apt install zotero
```

### 3. Setup (Coming Soon)

```bash
./scripts/setup.sh
```

---

## 📖 Documentation

- [SETUP-GUIDE.md](docs/SETUP-GUIDE.md) - 설치 및 설정 가이드 (작성 중)
- [DEWEY-CLASSIFICATION.md](docs/DEWEY-CLASSIFICATION.md) - 십진분류 시스템 (작성 중)
- [MIGRATION-GUIDE.md](docs/MIGRATION-GUIDE.md) - NixOS 마이그레이션 (작성 중)

---

## 🔗 Links

- **Digital Garden**: [notes.junghanacs.com](https://notes.junghanacs.com)
- **Zotero Meta Note**: [meta/20240320t110018](https://notes.junghanacs.com/meta/20240320t110018)
- **Bib Folder**: [notes.junghanacs.com/bib/](https://notes.junghanacs.com/bib/)
- **Zotero Group**: [@junghanacs](https://www.zotero.org/groups/5570207/junghanacs/library)

---

## 🛠 Status

🚧 **Work in Progress** - Building in public!

- [x] Repository structure
- [x] Plugin backup (Better BibTeX, Attanger)
- [x] Configuration templates
- [ ] Setup scripts
- [ ] Documentation
- [ ] NixOS integration

---

## 📜 License

MIT License - Feel free to use and adapt!

---

**Author**: [@junghanacs](https://github.com/junghan0611)
**Created**: 2025-10-11

