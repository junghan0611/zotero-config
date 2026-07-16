package main

import (
	"sort"
	"strings"
)

// searchFields are the Entry fields searched by Search.
var searchFields = []string{"title", "author", "keywords", "date", "abstract", "url"}

// Search filters entries by query and type.
// query: space-separated words (AND logic, case-insensitive).
//
//	Matches against citation key, title, author, keywords, date, abstract, url.
//
// typeFilter: matches entry type (case-insensitive) or bib filename stem
//
//	(e.g. "Book" matches type "book" or file "Book.bib").
//
// max: limits results (0 = unlimited).
func Search(entries []Entry, query string, typeFilter string, max int) []Entry {
	words := splitQuery(query)
	typeLower := strings.ToLower(typeFilter)
	queryLower := strings.ToLower(strings.TrimSpace(query))

	type scoredEntry struct {
		entry Entry
		score int
		idx   int
	}

	var scored []scoredEntry
	for i := range entries {
		e := &entries[i]

		// Apply type filter
		if typeFilter != "" && !matchType(e, typeLower) {
			continue
		}

		// Apply query words (AND)
		if len(words) > 0 && !matchAllWords(e, words) {
			continue
		}

		scored = append(scored, scoredEntry{
			entry: *e,
			score: scoreEntry(e, queryLower, words),
			idx:   i,
		})
	}

	sort.SliceStable(scored, func(i, j int) bool {
		if scored[i].score != scored[j].score {
			return scored[i].score > scored[j].score
		}
		return scored[i].idx < scored[j].idx
	})

	limit := len(scored)
	if max > 0 && max < limit {
		limit = max
	}

	results := make([]Entry, 0, limit)
	for i := 0; i < limit; i++ {
		results = append(results, scored[i].entry)
	}
	return results
}

// splitQuery splits a query string into lowercase words, skipping empty tokens.
func splitQuery(query string) []string {
	raw := strings.Fields(query)
	words := make([]string, 0, len(raw))
	for _, w := range raw {
		w = strings.ToLower(w)
		if w != "" {
			words = append(words, w)
		}
	}
	return words
}

// matchType checks if an entry matches the given type filter (lowercase).
// Matches either the entry type or the bib file stem.
func matchType(e *Entry, typeLower string) bool {
	if strings.ToLower(e.Type) == typeLower {
		return true
	}
	// Match file stem: "Book.bib" → "book"
	stem := strings.TrimSuffix(e.File, ".bib")
	if strings.ToLower(stem) == typeLower {
		return true
	}
	return false
}

// matchAllWords returns true if every word appears somewhere in the entry's
// searchable text (key + searchFields).
func matchAllWords(e *Entry, words []string) bool {
	// Build searchable text once per entry
	text := buildSearchText(e)

	for _, w := range words {
		if !strings.Contains(text, w) {
			return false
		}
	}
	return true
}

// buildSearchText concatenates the citation key and relevant field values
// into a single lowercase string for searching.
func buildSearchText(e *Entry) string {
	var b strings.Builder
	b.WriteString(strings.ToLower(e.Key))
	for _, field := range searchFields {
		if v, ok := e.Fields[field]; ok {
			b.WriteByte(' ')
			b.WriteString(strings.ToLower(v))
		}
	}
	return b.String()
}

func scoreEntry(e *Entry, queryLower string, words []string) int {
	if queryLower == "" {
		return 0
	}

	score := 0
	key := strings.ToLower(e.Key)
	title := strings.ToLower(e.Fields["title"])
	author := strings.ToLower(e.Fields["author"])
	keywords := strings.ToLower(e.Fields["keywords"])
	date := strings.ToLower(e.Fields["date"])
	abstract := strings.ToLower(e.Fields["abstract"])
	url := strings.ToLower(e.Fields["url"])

	switch {
	case key == queryLower:
		score += 1000
	case strings.Contains(key, queryLower):
		score += 300
	}

	switch {
	case title == queryLower:
		score += 950
	case strings.Contains(title, queryLower):
		score += 260
	}

	switch {
	case url == queryLower:
		score += 925
	case strings.Contains(url, queryLower):
		score += 250
	}

	if strings.Contains(author, queryLower) {
		score += 120
	}
	if strings.Contains(keywords, queryLower) {
		score += 90
	}
	if strings.Contains(abstract, queryLower) {
		score += 70
	}
	if strings.Contains(date, queryLower) {
		score += 60
	}

	for _, word := range words {
		if strings.Contains(title, word) {
			score += 30
		}
		if strings.Contains(url, word) {
			score += 25
		}
		if strings.Contains(key, word) {
			score += 20
		}
		if strings.Contains(author, word) {
			score += 12
		}
		if strings.Contains(keywords, word) {
			score += 10
		}
		if strings.Contains(abstract, word) {
			score += 6
		}
		if strings.Contains(date, word) {
			score += 4
		}
	}

	return score
}
