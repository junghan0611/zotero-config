# bibcli Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Go CLI that parses output/*.bib files and provides search/show/list/stats for AI agents (JSON-only output).

**Architecture:** Single Go module at `bibcli/`, stdlib only. Regex-based BibTeX parser reads all .bib files from a directory, stores entries as structs. Subcommands route via os.Args.

**Tech Stack:** Go 1.21+, stdlib only (encoding/json, regexp, os, path/filepath, strings, fmt, flag, strconv)

---

### Task 1: Go module + BibTeX parser

**Files:**
- Create: `bibcli/go.mod`
- Create: `bibcli/parser.go`
- Create: `bibcli/parser_test.go`

**Step 1: Initialize Go module**

```bash
cd bibcli && go mod init github.com/junghan0611/zotero-config/bibcli
```

**Step 2: Write parser test**

```go
// parser_test.go
package main

import (
	"strings"
	"testing"
)

const testBib = `% -*- bibtex -*-
% Test

@book{book-testkey,
  title = {Test Title},
  author = {{Kim Jung Han}},
  date = {2024},
  keywords = {programming, AI}
}

@online{web-example,
  title = {Example Page},
  author = {Doe, Jane},
  url = {https://example.com},
  date = {2025-01-15}
}
`

func TestParseEntries(t *testing.T) {
	entries := ParseBib(strings.NewReader(testBib), "test.bib")
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(entries))
	}

	e := entries[0]
	if e.Key != "book-testkey" {
		t.Errorf("key = %q, want book-testkey", e.Key)
	}
	if e.Type != "book" {
		t.Errorf("type = %q, want book", e.Type)
	}
	if e.Fields["title"] != "Test Title" {
		t.Errorf("title = %q", e.Fields["title"])
	}
	if e.Fields["keywords"] != "programming, AI" {
		t.Errorf("keywords = %q", e.Fields["keywords"])
	}
	if e.File != "test.bib" {
		t.Errorf("file = %q", e.File)
	}
}

func TestParseNestedBraces(t *testing.T) {
	bib := `@book{key1,
  author = {{Kim} and {Lee}},
  title = {Test {with} braces}
}
`
	entries := ParseBib(strings.NewReader(bib), "t.bib")
	if len(entries) != 1 {
		t.Fatalf("expected 1, got %d", len(entries))
	}
	if entries[0].Fields["author"] != "{Kim} and {Lee}" {
		t.Errorf("author = %q", entries[0].Fields["author"])
	}
}
```

**Step 3: Run test — expect FAIL**

```bash
cd bibcli && go test -v -run TestParse
```

**Step 4: Implement parser**

```go
// parser.go
package main

import (
	"bufio"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// Entry represents a single BibTeX entry.
type Entry struct {
	Type   string            `json:"type"`
	Key    string            `json:"key"`
	Fields map[string]string `json:"-"`
	File   string            `json:"file"`
}

// ParseBib parses BibTeX entries from a reader.
func ParseBib(r io.Reader, filename string) []Entry {
	var entries []Entry
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024)

	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)

		// Detect entry start: @type{key,
		if len(trimmed) > 0 && trimmed[0] == '@' {
			entryType, key := parseEntryHeader(trimmed)
			if entryType == "" {
				continue
			}
			fields := parseFields(scanner)
			entries = append(entries, Entry{
				Type:   entryType,
				Key:    key,
				Fields: fields,
				File:   filename,
			})
		}
	}
	return entries
}

func parseEntryHeader(line string) (string, string) {
	// @type{key,
	at := strings.IndexByte(line, '{')
	if at < 1 {
		return "", ""
	}
	entryType := strings.ToLower(line[1:at])
	rest := line[at+1:]
	comma := strings.IndexByte(rest, ',')
	if comma < 0 {
		return entryType, strings.TrimSpace(rest)
	}
	return entryType, strings.TrimSpace(rest[:comma])
}

func parseFields(scanner *bufio.Scanner) map[string]string {
	fields := make(map[string]string)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "}" || line == "" {
			if line == "}" {
				break
			}
			continue
		}

		eq := strings.Index(line, " = {")
		if eq < 0 {
			continue
		}
		fieldName := strings.TrimSpace(line[:eq])

		// Extract value handling nested braces
		rest := line[eq+4:] // skip " = {"
		value := extractBraceValue(rest)
		fields[fieldName] = value
	}
	return fields
}

func extractBraceValue(s string) string {
	depth := 1
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		ch := s[i]
		if ch == '{' {
			depth++
			b.WriteByte(ch)
		} else if ch == '}' {
			depth--
			if depth == 0 {
				break
			}
			b.WriteByte(ch)
		} else {
			b.WriteByte(ch)
		}
	}
	return b.String()
}

// LoadDir loads all .bib files from a directory.
func LoadDir(dir string) ([]Entry, error) {
	files, err := filepath.Glob(filepath.Join(dir, "*.bib"))
	if err != nil {
		return nil, err
	}
	var all []Entry
	for _, f := range files {
		fh, err := os.Open(f)
		if err != nil {
			continue
		}
		entries := ParseBib(fh, filepath.Base(f))
		fh.Close()
		all = append(all, entries...)
	}
	return all, nil
}
```

**Step 5: Run test — expect PASS**

```bash
cd bibcli && go test -v -run TestParse
```

**Step 6: Commit**

```bash
git add bibcli/ && git commit -m "feat(bibcli): Go module + BibTeX parser with tests"
```

---

### Task 2: Search logic

**Files:**
- Create: `bibcli/search.go`
- Create: `bibcli/search_test.go`

**Step 1: Write search test**

```go
// search_test.go
package main

import (
	"strings"
	"testing"
)

func testEntries() []Entry {
	return ParseBib(strings.NewReader(`
@book{book-pkm2024,
  title = {Personal Knowledge Management},
  author = {{Kim Jung Han}},
  date = {2024},
  keywords = {pkm, knowledge}
}

@online{web-example,
  title = {Go Programming Guide},
  author = {Doe, Jane},
  date = {2025},
  keywords = {golang, tutorial}
}

@software{vim-plugin,
  title = {Neovim Plugin},
  author = {Smith, Bob},
  date = {2024}
}
`), "test.bib")
}

func TestSearchSingle(t *testing.T) {
	results := Search(testEntries(), "knowledge", "", 20)
	if len(results) != 1 {
		t.Fatalf("expected 1, got %d", len(results))
	}
	if results[0].Key != "book-pkm2024" {
		t.Errorf("key = %q", results[0].Key)
	}
}

func TestSearchMultiWord(t *testing.T) {
	results := Search(testEntries(), "kim 2024", "", 20)
	if len(results) != 1 {
		t.Fatalf("expected 1, got %d", len(results))
	}
}

func TestSearchByType(t *testing.T) {
	results := Search(testEntries(), "", "software", 20)
	if len(results) != 1 {
		t.Fatalf("expected 1, got %d", len(results))
	}
}

func TestSearchMaxResults(t *testing.T) {
	results := Search(testEntries(), "", "", 1)
	if len(results) != 1 {
		t.Fatalf("expected 1, got %d", len(results))
	}
}

func TestSearchByCitationKey(t *testing.T) {
	results := Search(testEntries(), "vim-plugin", "", 20)
	if len(results) != 1 {
		t.Fatalf("expected 1, got %d", len(results))
	}
}
```

**Step 2: Run test — expect FAIL**

```bash
cd bibcli && go test -v -run TestSearch
```

**Step 3: Implement search**

```go
// search.go
package main

import "strings"

// Search filters entries by query and type. Multiple words are AND.
func Search(entries []Entry, query string, typeFilter string, max int) []Entry {
	words := splitQuery(query)
	var results []Entry

	for i := range entries {
		e := &entries[i]

		// Type filter
		if typeFilter != "" {
			if !strings.EqualFold(e.Type, typeFilter) &&
				!strings.EqualFold(e.File, typeFilter+".bib") &&
				!strings.EqualFold(strings.TrimSuffix(e.File, ".bib"), typeFilter) {
				continue
			}
		}

		// Query filter (AND)
		if len(words) > 0 && !matchAll(e, words) {
			continue
		}

		results = append(results, *e)
		if len(results) >= max {
			break
		}
	}
	return results
}

func splitQuery(q string) []string {
	q = strings.TrimSpace(q)
	if q == "" {
		return nil
	}
	parts := strings.Fields(strings.ToLower(q))
	return parts
}

func matchAll(e *Entry, words []string) bool {
	searchable := buildSearchable(e)
	for _, w := range words {
		if !strings.Contains(searchable, w) {
			return false
		}
	}
	return true
}

func buildSearchable(e *Entry) string {
	var b strings.Builder
	b.WriteString(strings.ToLower(e.Key))
	b.WriteByte(' ')
	b.WriteString(strings.ToLower(e.Type))
	for _, field := range []string{"title", "author", "keywords", "date", "abstract"} {
		if v, ok := e.Fields[field]; ok {
			b.WriteByte(' ')
			b.WriteString(strings.ToLower(v))
		}
	}
	return b.String()
}
```

**Step 4: Run test — expect PASS**

```bash
cd bibcli && go test -v -run TestSearch
```

**Step 5: Commit**

```bash
git add bibcli/ && git commit -m "feat(bibcli): search logic with multi-word AND + type filter"
```

---

### Task 3: CLI main + JSON output

**Files:**
- Create: `bibcli/main.go`

**Step 1: Implement main.go**

```go
// main.go
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	dir := findBibDir()

	switch os.Args[1] {
	case "search":
		cmdSearch(dir)
	case "show":
		cmdShow(dir)
	case "list":
		cmdList(dir)
	case "stats":
		cmdStats(dir)
	case "-h", "--help", "help":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
		usage()
		os.Exit(1)
	}
}

func findBibDir() string {
	// Check --dir flag anywhere in args
	for i, arg := range os.Args {
		if arg == "--dir" && i+1 < len(os.Args) {
			return os.Args[i+1]
		}
	}
	// Default: ../output relative to binary, or ./output
	exe, _ := os.Executable()
	candidate := filepath.Join(filepath.Dir(exe), "..", "output")
	if info, err := os.Stat(candidate); err == nil && info.IsDir() {
		return candidate
	}
	return "output"
}

func getFlag(args []string, name string, def string) string {
	for i, arg := range args {
		if arg == name && i+1 < len(args) {
			return args[i+1]
		}
	}
	return def
}

func cmdSearch(dir string) {
	if len(os.Args) < 3 {
		fatal("usage: bibcli search <query> [--type TYPE] [--max N]")
	}
	query := os.Args[2]
	args := os.Args[3:]
	typeFilter := getFlag(args, "--type", "")
	maxStr := getFlag(args, "--max", "20")
	max, _ := strconv.Atoi(maxStr)
	if max <= 0 {
		max = 20
	}

	entries, err := LoadDir(dir)
	if err != nil {
		fatal("failed to load bib files: " + err.Error())
	}

	results := Search(entries, query, typeFilter, max)
	printJSON(toBriefList(results))
}

func cmdShow(dir string) {
	if len(os.Args) < 3 {
		fatal("usage: bibcli show <citation-key>")
	}
	key := os.Args[2]

	entries, err := LoadDir(dir)
	if err != nil {
		fatal("failed to load bib files: " + err.Error())
	}

	for _, e := range entries {
		if e.Key == key {
			printJSON(toFull(e))
			return
		}
	}
	fatal("not found: " + key)
}

func cmdList(dir string) {
	args := os.Args[2:]
	typeFilter := getFlag(args, "--type", "")
	maxStr := getFlag(args, "--max", "50")
	max, _ := strconv.Atoi(maxStr)
	if max <= 0 {
		max = 50
	}

	entries, err := LoadDir(dir)
	if err != nil {
		fatal("failed to load bib files: " + err.Error())
	}

	results := Search(entries, "", typeFilter, max)
	printJSON(toBriefList(results))
}

func cmdStats(dir string) {
	entries, err := LoadDir(dir)
	if err != nil {
		fatal("failed to load bib files: " + err.Error())
	}

	files := make(map[string]int)
	for _, e := range entries {
		files[e.File]++
	}
	stats := map[string]interface{}{
		"total": len(entries),
		"files": files,
	}
	printJSON(stats)
}

// Brief entry for search/list output.
type BriefEntry struct {
	Key    string `json:"key"`
	Type   string `json:"type"`
	Title  string `json:"title"`
	Author string `json:"author"`
	Date   string `json:"date"`
	File   string `json:"file"`
}

func toBriefList(entries []Entry) []BriefEntry {
	out := make([]BriefEntry, len(entries))
	for i, e := range entries {
		out[i] = BriefEntry{
			Key:    e.Key,
			Type:   e.Type,
			Title:  e.Fields["title"],
			Author: e.Fields["author"],
			Date:   e.Fields["date"],
			File:   e.File,
		}
	}
	return out
}

func toFull(e Entry) map[string]interface{} {
	m := map[string]interface{}{
		"key":  e.Key,
		"type": e.Type,
		"file": e.File,
	}
	for k, v := range e.Fields {
		m[k] = v
	}
	return m
}

func printJSON(v interface{}) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	enc.SetEscapeHTML(false)
	enc.Encode(v)
}

func fatal(msg string) {
	fmt.Fprintf(os.Stderr, "error: %s\n", msg)
	os.Exit(1)
}

func usage() {
	fmt.Fprintf(os.Stderr, `bibcli - BibTeX search CLI for AI agents

Usage:
  bibcli search <query> [--type TYPE] [--max N]
  bibcli show <citation-key>
  bibcli list [--type TYPE] [--max N]
  bibcli stats

Options:
  --dir DIR    Path to bib files directory (default: output/)
  --type TYPE  Filter by type or filename stem (Book, Online, etc.)
  --max N      Max results (search default: 20, list default: 50)
`)
}
```

**Step 2: Build and test manually**

```bash
cd bibcli && go build -o bibcli . && ./bibcli stats --dir ../output
```

Expected: JSON with total=8030 and per-file counts.

```bash
./bibcli search "knowledge graph" --dir ../output --max 5
./bibcli show "book-pkm2024" --dir ../output
./bibcli list --type Book --max 3 --dir ../output
```

**Step 3: Commit**

```bash
git add bibcli/ && git commit -m "feat(bibcli): CLI main with search/show/list/stats commands"
```

---

### Task 4: Integration test with real data

**Files:**
- Modify: `bibcli/parser_test.go` (add benchmark)

**Step 1: Add benchmark test**

```go
// Add to parser_test.go
func BenchmarkLoadDir(b *testing.B) {
	dir := "../output"
	if _, err := os.Stat(dir); err != nil {
		b.Skip("output/ not found")
	}
	for i := 0; i < b.N; i++ {
		entries, err := LoadDir(dir)
		if err != nil {
			b.Fatal(err)
		}
		if len(entries) < 5000 {
			b.Fatalf("expected >5000 entries, got %d", len(entries))
		}
	}
}
```

**Step 2: Run benchmark**

```bash
cd bibcli && go test -bench=BenchmarkLoadDir -benchtime=3s -v
```

Expected: < 100ms per iteration (8000 entries, 4MB).

**Step 3: Run all tests**

```bash
cd bibcli && go test -v ./...
```

**Step 4: Build final binary**

```bash
cd bibcli && go build -o bibcli .
```

**Step 5: Commit**

```bash
git add bibcli/ && git commit -m "test(bibcli): benchmarks + integration validation"
```

---

### Task 5: Final verification + push

**Step 1: End-to-end verification**

```bash
cd bibcli
./bibcli stats --dir ../output
./bibcli search "emacs" --dir ../output --max 5
./bibcli search "한국" --type Book --dir ../output
./bibcli show "web-perplexity" --dir ../output
./bibcli list --type Video --max 3 --dir ../output
./bibcli --help
```

**Step 2: Commit and push**

```bash
git add -A && git push
```
