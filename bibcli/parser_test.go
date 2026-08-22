package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const testBib = `% -*- bibtex -*-
% Test Bibliography
%
% Entries:  2

@book{165.84-박82ㅅ,
  title = {삶은 왜 짐이 되었는가 #하이데거},
  author = {{박찬국}},
  date = {2017},
  url = {https://www.yes24.com/product/goods/49855929},
  langid = {ko},
  abstract = {서울대 철학과 박찬국 교수가 들려주는 하이데거 인생수업},
  keywords = {philosophy, heidegger},
  datemodified = {2026-01-29T02:15:32Z},
  dateadded = {2026-01-25T01:21:45Z}
}

@online{web-MermaidAscii터미널에서,
  title = {Mermaid ASCII: 터미널에서 Mermaid 다이어그램 렌더링},
  author = {neo},
  date = {2026-01-30T09:57:19+09:00},
  shorttitle = {Mermaid ASCII},
  url = {https://news.hada.io/topic?id=26245},
  urldate = {2026-02-02},
  abstract = {beautiful-mermaid는 Mermaid 다이어그램을 SVG 또는 ASCII 아트로 렌더링하는 초고속 TypeScript 기반 도구},
  datemodified = {2026-02-16T13:01:58Z},
  dateadded = {2026-02-02T10:28:19Z}
}
`

func TestParseBibBasic(t *testing.T) {
	entries := ParseBib(strings.NewReader(testBib), "Test.bib")
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(entries))
	}

	// First entry: book
	e := entries[0]
	if e.Type != "book" {
		t.Errorf("expected type 'book', got %q", e.Type)
	}
	if e.Key != "165.84-박82ㅅ" {
		t.Errorf("expected key '165.84-박82ㅅ', got %q", e.Key)
	}
	if e.File != "Test.bib" {
		t.Errorf("expected file 'Test.bib', got %q", e.File)
	}
	if e.Fields["date"] != "2017" {
		t.Errorf("expected date '2017', got %q", e.Fields["date"])
	}
	if e.Fields["langid"] != "ko" {
		t.Errorf("expected langid 'ko', got %q", e.Fields["langid"])
	}
	if e.Fields["keywords"] != "philosophy, heidegger" {
		t.Errorf("expected keywords 'philosophy, heidegger', got %q", e.Fields["keywords"])
	}

	// Second entry: online
	e2 := entries[1]
	if e2.Type != "online" {
		t.Errorf("expected type 'online', got %q", e2.Type)
	}
	if e2.Key != "web-MermaidAscii터미널에서" {
		t.Errorf("expected key 'web-MermaidAscii터미널에서', got %q", e2.Key)
	}
	if e2.Fields["shorttitle"] != "Mermaid ASCII" {
		t.Errorf("expected shorttitle 'Mermaid ASCII', got %q", e2.Fields["shorttitle"])
	}
}

func TestParseBibNestedBraces(t *testing.T) {
	input := `@book{test-nested,
  title = {Test Title},
  author = {{Kim} and {Lee}},
  date = {2024}
}
`
	entries := ParseBib(strings.NewReader(input), "test.bib")
	if len(entries) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(entries))
	}
	if entries[0].Fields["author"] != "{Kim} and {Lee}" {
		t.Errorf("expected nested braces preserved, got %q", entries[0].Fields["author"])
	}
}

func TestParseBibDoubleBracedAuthor(t *testing.T) {
	input := `@book{test-double,
  title = {A Book},
  author = {{Robert C. Martin}},
  date = {2024}
}
`
	entries := ParseBib(strings.NewReader(input), "test.bib")
	if len(entries) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(entries))
	}
	if entries[0].Fields["author"] != "{Robert C. Martin}" {
		t.Errorf("expected '{Robert C. Martin}', got %q", entries[0].Fields["author"])
	}
}

func TestParseBibMultiLineValue(t *testing.T) {
	input := `@misc{test-multiline,
  title = {Test},
  abstract = {First line of abstract
second line of abstract
third line},
  date = {2024}
}
`
	entries := ParseBib(strings.NewReader(input), "test.bib")
	if len(entries) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(entries))
	}
	abs := entries[0].Fields["abstract"]
	if !strings.Contains(abs, "First line") || !strings.Contains(abs, "third line") {
		t.Errorf("multi-line abstract not captured correctly: %q", abs)
	}
}

func TestParseBibMultiLineAnnotation(t *testing.T) {
	input := `@misc{test-annotation,
  title = {Test},
  annotation = {arXiv:2304.03442
Citation Key: test123},
  date = {2024}
}
`
	entries := ParseBib(strings.NewReader(input), "test.bib")
	if len(entries) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(entries))
	}
	ann := entries[0].Fields["annotation"]
	if !strings.Contains(ann, "arXiv:2304.03442") || !strings.Contains(ann, "Citation Key: test123") {
		t.Errorf("multi-line annotation not captured: %q", ann)
	}
}

func TestParseBibEmptyKeywords(t *testing.T) {
	input := `@software{test-empty-kw,
  title = {Test},
  keywords = {},
  date = {2024}
}
`
	entries := ParseBib(strings.NewReader(input), "test.bib")
	if len(entries) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(entries))
	}
	if entries[0].Fields["keywords"] != "" {
		t.Errorf("expected empty keywords, got %q", entries[0].Fields["keywords"])
	}
}

func TestParseBibFieldExtraction(t *testing.T) {
	entries := ParseBib(strings.NewReader(testBib), "Book.bib")

	e := entries[0]
	expectedFields := []string{"title", "author", "date", "url", "langid", "abstract", "keywords", "datemodified", "dateadded"}
	for _, f := range expectedFields {
		if _, ok := e.Fields[f]; !ok {
			t.Errorf("missing field %q in entry", f)
		}
	}
}

func TestParseBibFileAttribution(t *testing.T) {
	entries := ParseBib(strings.NewReader(testBib), "MyFile.bib")
	for _, e := range entries {
		if e.File != "MyFile.bib" {
			t.Errorf("expected file 'MyFile.bib', got %q", e.File)
		}
	}
}

func TestLoadDir(t *testing.T) {
	// Create a temp directory with two bib files
	dir := t.TempDir()

	bib1 := `@book{book-test1,
  title = {Book One},
  author = {Author A},
  date = {2020}
}
`
	bib2 := `@online{web-test2,
  title = {Online Two},
  author = {Author B},
  date = {2021}
}

@online{web-test3,
  title = {Online Three},
  author = {Author C},
  date = {2022}
}
`
	if err := os.WriteFile(filepath.Join(dir, "Book.bib"), []byte(bib1), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "Online.bib"), []byte(bib2), 0644); err != nil {
		t.Fatal(err)
	}
	// Also create a non-bib file that should be ignored
	if err := os.WriteFile(filepath.Join(dir, "notes.txt"), []byte("ignore me"), 0644); err != nil {
		t.Fatal(err)
	}

	entries, err := LoadDir(dir)
	if err != nil {
		t.Fatalf("LoadDir failed: %v", err)
	}
	if len(entries) != 3 {
		t.Fatalf("expected 3 entries total, got %d", len(entries))
	}

	// Check file attribution
	bookCount := 0
	onlineCount := 0
	for _, e := range entries {
		switch e.File {
		case "Book.bib":
			bookCount++
		case "Online.bib":
			onlineCount++
		}
	}
	if bookCount != 1 {
		t.Errorf("expected 1 entry from Book.bib, got %d", bookCount)
	}
	if onlineCount != 2 {
		t.Errorf("expected 2 entries from Online.bib, got %d", onlineCount)
	}
}

func BenchmarkLoadDir(b *testing.B) {
	dir := realBibDir()
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		b.Skip("bib dir not found")
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

func TestLoadRealBibDir(t *testing.T) {
	// Optional: runs only where the live bib dir is already populated.
	// Absent (CI) or empty (before the first render on a device) → skip.
	outputDir := realBibDir()
	if _, err := os.Stat(outputDir); os.IsNotExist(err) {
		t.Skip("bib dir not found, skipping real bib test")
	}
	bibs, _ := filepath.Glob(filepath.Join(outputDir, "*.bib"))
	if len(bibs) == 0 {
		t.Skipf("no .bib files in %s yet, skipping real bib test", outputDir)
	}

	entries, err := LoadDir(outputDir)
	if err != nil {
		t.Fatalf("LoadDir failed on real data: %v", err)
	}

	// A populated library is thousands of entries across the type-split files.
	if len(entries) < 5000 {
		t.Errorf("expected at least 5000 entries from real bibs, got %d", len(entries))
	}
	t.Logf("Loaded %d entries from real bib files", len(entries))

	// Spot check: every entry should have a non-empty key and type
	for i, e := range entries {
		if e.Key == "" {
			t.Errorf("entry %d has empty key", i)
		}
		if e.Type == "" {
			t.Errorf("entry %d (%s) has empty type", i, e.Key)
		}
		if e.File == "" {
			t.Errorf("entry %d (%s) has empty file", i, e.Key)
		}
	}
}

// realBibDir points at the live bibliography surface for the optional
// real-data tests. It reuses the production resolution order so the tests
// cannot drift from it. These tests are read-only and skip when absent.
func realBibDir() string {
	return resolveDir(map[string]string{})
}
