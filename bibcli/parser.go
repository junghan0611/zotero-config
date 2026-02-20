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
	Type   string            // e.g. "book", "online", "software"
	Key    string            // citation key
	Fields map[string]string // field name → value (outer braces stripped)
	File   string            // source filename (e.g. "Book.bib")
}

// ParseBib parses BibTeX entries from r, tagging each with filename.
func ParseBib(r io.Reader, filename string) []Entry {
	var entries []Entry
	scanner := bufio.NewScanner(r)
	// Increase buffer for long lines (abstracts can be very long)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	var cur *Entry
	var fieldName string
	var fieldValue strings.Builder
	var braceDepth int
	inField := false

	flushField := func() {
		if cur != nil && fieldName != "" {
			cur.Fields[fieldName] = strings.TrimSpace(fieldValue.String())
		}
		fieldName = ""
		fieldValue.Reset()
		inField = false
	}

	for scanner.Scan() {
		line := scanner.Text()

		// Outside an entry
		if cur == nil {
			trimmed := strings.TrimSpace(line)
			// Skip comments and blank lines
			if trimmed == "" || strings.HasPrefix(trimmed, "%") {
				continue
			}
			// Look for @type{key,
			if strings.HasPrefix(trimmed, "@") {
				atIdx := strings.Index(trimmed, "@")
				braceIdx := strings.Index(trimmed, "{")
				if braceIdx > atIdx {
					entryType := strings.ToLower(strings.TrimSpace(trimmed[atIdx+1 : braceIdx]))
					rest := trimmed[braceIdx+1:]
					// key is everything up to the comma (or end of line)
					commaIdx := strings.Index(rest, ",")
					var key string
					if commaIdx >= 0 {
						key = strings.TrimSpace(rest[:commaIdx])
					} else {
						key = strings.TrimSpace(rest)
					}
					cur = &Entry{
						Type:   entryType,
						Key:    key,
						Fields: make(map[string]string),
						File:   filename,
					}
				}
			}
			continue
		}

		// Inside an entry
		if inField {
			// Continue accumulating a multi-line field value
			// Count braces to find where the value ends
			for i, ch := range line {
				if ch == '{' {
					braceDepth++
				} else if ch == '}' {
					braceDepth--
					if braceDepth == 0 {
						// End of this field value
						fieldValue.WriteString(line[:i])
						flushField()
						// Check if rest of line has more content (unlikely but safe)
						break
					}
				}
			}
			if inField {
				// Still accumulating — full line is part of value
				fieldValue.WriteByte('\n')
				fieldValue.WriteString(line)
			}
			continue
		}

		trimmed := strings.TrimSpace(line)

		// Closing brace of entry
		if trimmed == "}" {
			entries = append(entries, *cur)
			cur = nil
			continue
		}

		// Parse field = {value} or field = {value (possibly multi-line)
		eqIdx := strings.Index(trimmed, "=")
		if eqIdx < 0 {
			continue
		}
		fieldName = strings.TrimSpace(trimmed[:eqIdx])
		rhs := strings.TrimSpace(trimmed[eqIdx+1:])

		// Strip leading { and find matching }
		if len(rhs) == 0 || rhs[0] != '{' {
			// Not brace-delimited; skip
			fieldName = ""
			continue
		}

		// Count braces in rhs
		braceDepth = 0
		valueStart := 1 // skip the opening {
		for i, ch := range rhs {
			if ch == '{' {
				braceDepth++
			} else if ch == '}' {
				braceDepth--
				if braceDepth == 0 {
					// Complete value on this line
					val := rhs[valueStart:i]
					// Strip trailing comma after closing brace if present
					cur.Fields[fieldName] = strings.TrimSpace(val)
					fieldName = ""
					break
				}
			}
		}
		if braceDepth > 0 {
			// Value spans multiple lines
			fieldValue.WriteString(rhs[valueStart:])
			inField = true
		}
	}

	return entries
}

// LoadDir loads all *.bib files from dir and returns combined entries.
func LoadDir(dir string) ([]Entry, error) {
	matches, err := filepath.Glob(filepath.Join(dir, "*.bib"))
	if err != nil {
		return nil, err
	}

	var all []Entry
	for _, path := range matches {
		f, err := os.Open(path)
		if err != nil {
			return nil, err
		}
		entries := ParseBib(f, filepath.Base(path))
		f.Close()
		all = append(all, entries...)
	}
	return all, nil
}
