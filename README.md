# zotero-config

**Reproducible bibliographic workflow with AI-queryable knowledge repository**

> Transform Zotero into a meta-knowledge hub that AI agents can understand and reference.

[![한글](https://img.shields.io/badge/한글-README--KO.md-blue)](README-KO.md)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Work in Progress](https://img.shields.io/badge/status-WIP-yellow.svg)](https://github.com/junghan0611/zotero-config)

---

## 🎯 Why This Project?

**Problem**: AI agents can answer anything, but that doesn't build **your** knowledge.

You read a paper. An AI summarizes it. Great! But where does that leave you? Disconnected facts. No personal archive. No conversation context.

**Solution**: Zotero as your **queryable knowledge repository**

- 📚 Your archive: Not just papers—videos, podcasts, cafes, life moments
- 🤖 AI agents **query your library** during conversations (via MCP)
- 🔗 Bibliographic notes become **shared context** between you and agents
- 📖 Reading workflow: **capture → query → connect → emerge**

**Philosophy**: Life is a book. Everyone is an author. Build your anthology.

---

## What You Get

**For Humans:**
- ✅ Reproducible Zotero setup (NixOS-ready, syncs via Git)
- ✅ Korean Dewey Decimal Classification citation keys (`book-pkm2024`)
- ✅ Auto-export BibTeX for Org-mode/LaTeX
- ✅ Self-contained workspace (no scattered configs)

**For AI Agents:**
- ✅ MCP integration: Semantic search over your library
- ✅ PDF annotation queries: "What did I highlight in this paper?"
- ✅ Context-aware conversations: "Find related papers I've read"
- ✅ Knowledge archaeology: "What was I thinking 2 years ago?"

---

## 🏗 How It Works

**Simple flow:**

```
You → Zotero → MCP Server → AI Agent
```

1. **You capture** papers/videos/notes in Zotero
2. **Better BibTeX** generates citation keys (`book-pkm2024`)
3. **MCP Server** indexes your library (semantic search)
4. **AI agents** query during conversations

**Example conversation:**

> **You**: "I'm researching knowledge graphs"
> **Agent** (queries your Zotero via MCP): "You have 3 papers on this topic. One from 2020 highlights the connection to PKM systems. Want me to reference your annotations?"

---

## 📚 Features

### Core Components

- ✅ **Korean Dewey Decimal Classification (KDC)**
  - Citation key format: `book-title2024`, `blog-title2024`, `wiki-title`, ...
  - Type-based prefixes: `book`, `blog`, `wiki`, `film`, `doc`, `web`, `news`, `person`, `dict`, `art`
  - Reproducible keys for LaTeX/Org-mode integration

- ✅ **Better BibTeX Integration**
  - Auto-export to `.bib` files (tracked in Git)
  - Org-mode Quick Copy: `Ctrl+Shift+C` → citation key
  - Custom postscript: `callnumber`, `datemodified`, `dateadded` fields

- ✅ **MCP (Model Context Protocol) Support**
  - Semantic search: concept-based paper discovery
  - PDF annotation extraction and search
  - Full-text indexing for deep queries
  - Integration with Claude Desktop, Cline, etc.

- ✅ **Attanger Plugin**
  - Auto-organize attachments by item type
  - Source directory monitoring
  - Configurable file type filters

- ✅ **Reproducible Setup**
  - NixOS/Home-Manager compatible
  - Self-contained workspace structure
  - Plugin XPI files versioned in Git
  - Configuration templates with path variables

---

## 📂 Directory Structure

```
zotero-config/
├── plugins/               # Zotero plugins (XPI files)
│   ├── better-bibtex@iris-advies.com.xpi
│   └── zoteroattanger@polygon.org.xpi
├── config/                # Better BibTeX configuration
│   └── betterbibtex-preferences-nixos.json
├── docs/                  # Documentation
│   ├── MCP-INTEGRATION.md
│   ├── SETUP-GUIDE.md
│   └── DEWEY-CLASSIFICATION.md
├── scripts/               # Automation scripts
│   ├── setup.sh
│   └── mcp-setup.sh
└── workspace/             # Local workspace (not tracked)
    ├── data/              # Zotero database (.gitignore)
    ├── files/             # Attachments (.gitignore)
    ├── exports/           # Auto-exported BibTeX
    └── incoming/          # Attanger source (.gitignore)
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

### 3. Install MCP Server (Optional but Recommended)

```bash
# Install 54yyyu/zotero-mcp for AI agent integration
uv tool install "git+https://github.com/54yyyu/zotero-mcp.git"

# Setup with local Zotero database
zotero-mcp setup --local

# Or use Zotero Web API (for cloud sync)
zotero-mcp setup --no-local \
  --api-key YOUR_API_KEY \
  --library-id YOUR_LIBRARY_ID

# Build semantic search database
zotero-mcp update-db --fulltext
```

### 4. Configure Zotero

```bash
# Run setup script (coming soon)
./scripts/setup.sh

# Or manually:
# 1. Install plugins from plugins/
# 2. Import Better BibTeX config from config/
# 3. Set data directory to workspace/data/
```

---

## 🤖 MCP Integration

### What is MCP?

**Model Context Protocol (MCP)** enables AI agents to access external data sources. With Zotero MCP:

- 🔍 **Semantic Search**: Ask agents to find papers by concept, not just keywords
- 📝 **Annotation Access**: Query your PDF highlights and notes
- 🔗 **Context Awareness**: Agents reference your reading history during conversations
- 📊 **Meta-Analysis**: Generate insights from your entire library

### Supported MCP Servers

| Server | Features | Best For |
|--------|----------|----------|
| **[54yyyu/zotero-mcp](https://github.com/54yyyu/zotero-mcp)** | Semantic search, PDF annotations, full-text indexing | **Recommended** - Most complete |
| [kaliaboi/mcp-zotero](https://github.com/kaliaboi/mcp-zotero) | Collection queries, basic search | Simple web API integration |
| [kujenga/zotero-mcp](https://pypi.org/project/zotero-mcp/) | Python-based, Docker support | Python workflows |

### Example Usage

```python
# AI agent queries your Zotero library
"Find papers about knowledge graphs published after 2020"
"What are my annotations in the paper about PKM systems?"
"Connect this concept to books in my Collection C3"
```

See [docs/MCP-INTEGRATION.md](docs/MCP-INTEGRATION.md) for detailed setup.

---

## 📖 Use Cases

### Reading Workflow with AI Agents

**Before (Traditional):**
1. Read paper → manual notes → disconnected knowledge

**After (Agent-Integrated):**
1. **Capture**: Save to Zotero with citation key (`book-pkm2024`)
2. **Query**: Ask AI agent to find related papers
3. **Connect**: Agent references your annotations and library
4. **Emerge**: New insights from conversation context

### Digital Gardening

- **Org-mode Integration**: Citation keys directly in your notes
- **Denote Linking**: `[[book-title2024]]` links to bibliographic entries
- **Emacs Workflow**: Quick Copy → insert citation → auto-update `.bib`

### Knowledge Archaeology

AI agents help you rediscover forgotten connections:
- "What did I read about this topic 2 years ago?"
- "Find patterns in my reading history"
- "Which books influenced my thinking on X?"

---

## 🔗 Links

- **Digital Garden**: [notes.junghanacs.com](https://notes.junghanacs.com)
- **Zotero Meta Note**: [meta/20240320t110018](https://notes.junghanacs.com/meta/20240320t110018)
- **Bib Folder**: [notes.junghanacs.com/bib/](https://notes.junghanacs.com/bib/)
- **Zotero Group Library**: [@junghanacs](https://www.zotero.org/groups/5570207/junghanacs/library)

---

## 🛠 Status

🚧 **Work in Progress** - Building in public!

**Completed:**
- [x] Repository structure
- [x] Plugin backup (Better BibTeX v7.0.50, Attanger v1.3.8)
- [x] Configuration templates
- [x] MCP architecture design

**In Progress:**
- [ ] MCP setup scripts
- [ ] Documentation (MCP integration, setup guide)
- [ ] Korean Dewey Classification guide
- [ ] NixOS Home-Manager module

---

## 🤝 Contributing

This is a personal configuration, but feel free to:
- Open issues for questions about the workflow
- Fork and adapt for your own bibliographic system
- Share your MCP integration experiences

---

## 📜 License

MIT License - Feel free to use and adapt!

---

**Author**: [@junghanacs](https://github.com/junghan0611)
**Created**: 2025-10-11
**Philosophy**: 인생은 한 권의 책 (Life is a book)
