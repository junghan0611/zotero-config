package main

import (
	"testing"
)

func testEntries() []Entry {
	return []Entry{
		{
			Type: "book",
			Key:  "165.84-박82ㅅ",
			Fields: map[string]string{
				"title":    "삶은 왜 짐이 되었는가 #하이데거",
				"author":   "{박찬국}",
				"date":     "2017",
				"keywords": "philosophy, heidegger",
				"abstract": "서울대 철학과 박찬국 교수",
				"url":      "https://example.com/heidegger-burden",
			},
			File: "Book.bib",
		},
		{
			Type: "online",
			Key:  "web-MermaidAscii터미널에서",
			Fields: map[string]string{
				"title":    "Mermaid ASCII: 터미널에서 다이어그램 렌더링",
				"author":   "neo",
				"date":     "2026-01-30T09:57:19+09:00",
				"abstract": "TypeScript 기반 도구",
				"url":      "https://example.com/mermaid-ascii",
			},
			File: "Online.bib",
		},
		{
			Type: "software",
			Key:  "ExecEvalExecNeomacs26",
			Fields: map[string]string{
				"title":    "eval-exec/neomacs",
				"author":   "eval-exec",
				"date":     "2026-02-08T12:22:05Z",
				"keywords": "elisp, emacs, neomacs, rust, wgpu",
				"abstract": "NEO Emacs — A GPU-powered Emacs written in Rust",
				"url":      "https://github.com/eval-exec/neomacs",
			},
			File: "Software.bib",
		},
		{
			Type: "book",
			Key:  "book-uripeurogeuraemeodeulwe",
			Fields: map[string]string{
				"title":    "우리, 프로그래머들 We, Programmers",
				"author":   "{로버트 C. 마틴}",
				"date":     "2024",
				"keywords": "programming",
				"abstract": "소프트웨어 개발 업계의 선도적 인물",
				"url":      "https://example.com/we-programmers",
			},
			File: "Book.bib",
		},
		{
			Type: "misc",
			Key:  "learningtransferablevisual21",
			Fields: map[string]string{
				"title":    "Learning Transferable Visual Models From Natural Language Supervision",
				"author":   "Radford, Alec and Kim, Jong Wook",
				"date":     "2021-02-26",
				"keywords": "Computer Science, Machine Learning",
				"abstract": "State-of-the-art computer vision systems",
				"url":      "https://example.com/clip-paper",
			},
			File: "Misc.bib",
		},
	}
}

func TestSearchSingleWord(t *testing.T) {
	entries := testEntries()

	results := Search(entries, "emacs", "", 0)
	if len(results) != 1 {
		t.Fatalf("expected 1 result for 'emacs', got %d", len(results))
	}
	if results[0].Key != "ExecEvalExecNeomacs26" {
		t.Errorf("expected neomacs entry, got %q", results[0].Key)
	}
}

func TestSearchCaseInsensitive(t *testing.T) {
	entries := testEntries()

	results := Search(entries, "EMACS", "", 0)
	if len(results) != 1 {
		t.Fatalf("expected 1 result for 'EMACS', got %d", len(results))
	}

	results = Search(entries, "Mermaid", "", 0)
	if len(results) != 1 {
		t.Fatalf("expected 1 result for 'Mermaid', got %d", len(results))
	}
}

func TestSearchMultiWordAND(t *testing.T) {
	entries := testEntries()

	// "rust emacs" should match neomacs (has both in keywords)
	results := Search(entries, "rust emacs", "", 0)
	if len(results) != 1 {
		t.Fatalf("expected 1 result for 'rust emacs', got %d", len(results))
	}
	if results[0].Key != "ExecEvalExecNeomacs26" {
		t.Errorf("expected neomacs, got %q", results[0].Key)
	}

	// "rust book" should match nothing (no entry has both)
	results = Search(entries, "rust book", "", 0)
	if len(results) != 0 {
		t.Errorf("expected 0 results for 'rust book', got %d", len(results))
	}
}

func TestSearchTypeFilter(t *testing.T) {
	entries := testEntries()

	// Filter by entry type
	results := Search(entries, "", "book", 0)
	if len(results) != 2 {
		t.Fatalf("expected 2 books, got %d", len(results))
	}
	for _, r := range results {
		if r.Type != "book" {
			t.Errorf("expected type 'book', got %q", r.Type)
		}
	}

	// Filter by file stem (capitalized)
	results = Search(entries, "", "Book", 0)
	if len(results) != 2 {
		t.Fatalf("expected 2 entries from Book.bib, got %d", len(results))
	}

	// Filter by file stem for Software
	results = Search(entries, "", "Software", 0)
	if len(results) != 1 {
		t.Fatalf("expected 1 Software entry, got %d", len(results))
	}
}

func TestSearchTypeFilterWithQuery(t *testing.T) {
	entries := testEntries()

	results := Search(entries, "프로그래머", "book", 0)
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Key != "book-uripeurogeuraemeodeulwe" {
		t.Errorf("expected 프로그래머 book, got %q", results[0].Key)
	}
}

func TestSearchMaxResults(t *testing.T) {
	entries := testEntries()

	// All entries match empty query with no type filter
	results := Search(entries, "", "", 0)
	if len(results) != 5 {
		t.Fatalf("expected 5 results with no filter, got %d", len(results))
	}

	results = Search(entries, "", "", 2)
	if len(results) != 2 {
		t.Fatalf("expected 2 results with max=2, got %d", len(results))
	}
}

func TestSearchByCitationKey(t *testing.T) {
	entries := testEntries()

	results := Search(entries, "learningtransferablevisual", "", 0)
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Key != "learningtransferablevisual21" {
		t.Errorf("expected learningtransferablevisual21, got %q", results[0].Key)
	}
}

func TestSearchByDate(t *testing.T) {
	entries := testEntries()

	results := Search(entries, "2021", "", 0)
	if len(results) != 1 {
		t.Fatalf("expected 1 result for date '2021', got %d", len(results))
	}
	if results[0].Key != "learningtransferablevisual21" {
		t.Errorf("expected learningtransferablevisual21, got %q", results[0].Key)
	}
}

func TestSearchKoreanText(t *testing.T) {
	entries := testEntries()

	results := Search(entries, "하이데거", "", 0)
	if len(results) != 1 {
		t.Fatalf("expected 1 result for '하이데거', got %d", len(results))
	}
	if results[0].Key != "165.84-박82ㅅ" {
		t.Errorf("expected 박찬국 book, got %q", results[0].Key)
	}
}

func TestSearchEmptyQueryWithTypeReturnsAll(t *testing.T) {
	entries := testEntries()

	results := Search(entries, "", "misc", 0)
	if len(results) != 1 {
		t.Fatalf("expected 1 misc entry, got %d", len(results))
	}
}

func TestSearchByURL(t *testing.T) {
	entries := testEntries()

	results := Search(entries, "github.com/eval-exec/neomacs", "", 0)
	if len(results) != 1 {
		t.Fatalf("expected 1 result for URL search, got %d", len(results))
	}
	if results[0].Key != "ExecEvalExecNeomacs26" {
		t.Errorf("expected neomacs entry, got %q", results[0].Key)
	}
}

func TestSearchPrefersExactTitleMatch(t *testing.T) {
	entries := append(testEntries(), Entry{
		Type: "inreference",
		Key:  "wiki-AsWeMay",
		Fields: map[string]string{
			"title":    "As We May Think",
			"author":   "{Vannevar Bush}",
			"abstract": "memex essay",
			"url":      "https://en.wikipedia.org/wiki/As_We_May_Think",
		},
		File: "Reference.bib",
	})

	results := Search(entries, "As We May Think", "", 5)
	if len(results) == 0 {
		t.Fatal("expected at least 1 result")
	}
	if results[0].Key != "wiki-AsWeMay" {
		t.Errorf("expected exact title match first, got %q", results[0].Key)
	}
}
