package main

import (
	"strings"
)

// searchFields are the Entry fields searched by Search.
var searchFields = []string{"title", "author", "keywords", "date", "abstract"}

// Search filters entries by query and type.
// query: space-separated words (AND logic, case-insensitive).
//
//	Matches against citation key, title, author, keywords, date, abstract.
//
// typeFilter: matches entry type (case-insensitive) or bib filename stem
//
//	(e.g. "Book" matches type "book" or file "Book.bib").
//
// max: limits results (0 = unlimited).
func Search(entries []Entry, query string, typeFilter string, max int) []Entry {
	words := splitQuery(query)
	typeLower := strings.ToLower(typeFilter)

	var results []Entry
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

		results = append(results, *e)
		if max > 0 && len(results) >= max {
			break
		}
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
