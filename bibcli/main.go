package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

var version = "dev"

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		printHelp()
		os.Exit(1)
	}

	cmd := args[0]
	rest := args[1:]

	switch cmd {
	case "search":
		cmdSearch(rest)
	case "show":
		cmdShow(rest)
	case "list":
		cmdList(rest)
	case "lookup":
		cmdLookup(rest)
	case "stats":
		cmdStats(rest)
	case "help", "--help", "-h":
		printHelp()
	case "version", "--version", "-v":
		fmt.Println(version)
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", cmd)
		printHelp()
		os.Exit(1)
	}
}

// parseFlags extracts --key value pairs from args, returns remaining positional args.
func parseFlags(args []string) (positional []string, flags map[string]string) {
	flags = make(map[string]string)
	for i := 0; i < len(args); i++ {
		if strings.HasPrefix(args[i], "--") && i+1 < len(args) {
			key := strings.TrimPrefix(args[i], "--")
			flags[key] = args[i+1]
			i++ // skip value
		} else {
			positional = append(positional, args[i])
		}
	}
	return
}

// resolveDir determines the bib directory to use.
// Priority: --dir flag > BIBCLI_DIR env > ../output relative to exe > ./output
func resolveDir(flags map[string]string) string {
	if d, ok := flags["dir"]; ok {
		return d
	}
	if d := os.Getenv("BIBCLI_DIR"); d != "" {
		return d
	}
	// Relative to executable
	exe, err := os.Executable()
	if err == nil {
		candidate := filepath.Join(filepath.Dir(exe), "..", "output")
		if info, err := os.Stat(candidate); err == nil && info.IsDir() {
			return candidate
		}
	}
	// Fallback
	return "./output"
}

// loadEntries loads all entries from the resolved directory.
func loadEntries(flags map[string]string) []Entry {
	dir := resolveDir(flags)
	entries, err := LoadDir(dir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error loading bib files from %s: %v\n", dir, err)
		os.Exit(1)
	}
	if len(entries) == 0 {
		fmt.Fprintf(os.Stderr, "no bib entries found in %s\n", dir)
		os.Exit(1)
	}
	return entries
}

// writeJSON writes v as indented JSON to stdout with SetEscapeHTML(false).
func writeJSON(v interface{}) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		fmt.Fprintf(os.Stderr, "json encode error: %v\n", err)
		os.Exit(1)
	}
}

// briefEntry is the JSON representation for search/list results.
type briefEntry struct {
	Key    string `json:"key"`
	Type   string `json:"type"`
	Title  string `json:"title,omitempty"`
	Author string `json:"author,omitempty"`
	Date   string `json:"date,omitempty"`
	File   string `json:"file"`
}

// fullEntry is the JSON representation for show results (all fields).
type fullEntry struct {
	Key    string            `json:"key"`
	Type   string            `json:"type"`
	Fields map[string]string `json:"-"`
	File   string            `json:"file"`
}

// MarshalJSON for fullEntry produces a flat object with key, type, all fields, and file.
func (e fullEntry) MarshalJSON() ([]byte, error) {
	m := make(map[string]string, len(e.Fields)+3)
	m["key"] = e.Key
	m["type"] = e.Type
	for k, v := range e.Fields {
		m[k] = v
	}
	m["file"] = e.File
	return json.Marshal(m)
}

func toBrief(e Entry) briefEntry {
	return briefEntry{
		Key:    e.Key,
		Type:   e.Type,
		Title:  e.Fields["title"],
		Author: e.Fields["author"],
		Date:   e.Fields["date"],
		File:   e.File,
	}
}

func toFull(e Entry) fullEntry {
	return fullEntry{
		Key:    e.Key,
		Type:   e.Type,
		Fields: e.Fields,
		File:   e.File,
	}
}

func cmdSearch(args []string) {
	pos, flags := parseFlags(args)
	if len(pos) == 0 {
		fmt.Fprintln(os.Stderr, "usage: bibcli search <query> [--type TYPE] [--max N] [--dir DIR]")
		os.Exit(1)
	}
	query := strings.Join(pos, " ")
	typeFilter := flags["type"]
	maxVal := 20
	if m, ok := flags["max"]; ok {
		n, err := strconv.Atoi(m)
		if err != nil || n < 0 {
			fmt.Fprintf(os.Stderr, "invalid --max value: %s\n", m)
			os.Exit(1)
		}
		maxVal = n
	}

	entries := loadEntries(flags)
	results := Search(entries, query, typeFilter, maxVal)

	briefs := make([]briefEntry, len(results))
	for i, r := range results {
		briefs[i] = toBrief(r)
	}
	writeJSON(briefs)
}

func cmdShow(args []string) {
	pos, flags := parseFlags(args)
	if len(pos) == 0 {
		fmt.Fprintln(os.Stderr, "usage: bibcli show <citation-key> [--dir DIR]")
		os.Exit(1)
	}
	key := pos[0]

	entries := loadEntries(flags)
	for _, e := range entries {
		if e.Key == key {
			writeJSON(toFull(e))
			return
		}
	}
	fmt.Fprintf(os.Stderr, "entry not found: %s\n", key)
	os.Exit(1)
}

func cmdList(args []string) {
	_, flags := parseFlags(args)
	typeFilter := flags["type"]
	maxVal := 50
	if m, ok := flags["max"]; ok {
		n, err := strconv.Atoi(m)
		if err != nil || n < 0 {
			fmt.Fprintf(os.Stderr, "invalid --max value: %s\n", m)
			os.Exit(1)
		}
		maxVal = n
	}

	entries := loadEntries(flags)
	results := Search(entries, "", typeFilter, maxVal)

	briefs := make([]briefEntry, len(results))
	for i, r := range results {
		briefs[i] = toBrief(r)
	}
	writeJSON(briefs)
}

type statsOutput struct {
	Total int            `json:"total"`
	Files map[string]int `json:"files"`
}

func cmdStats(args []string) {
	_, flags := parseFlags(args)
	entries := loadEntries(flags)

	files := make(map[string]int)
	for _, e := range entries {
		files[e.File]++
	}
	writeJSON(statsOutput{
		Total: len(entries),
		Files: files,
	})
}

func printHelp() {
	fmt.Fprintln(os.Stderr, `bibcli - BibTeX search CLI for AI agents

Usage:
  bibcli search <query> [--type TYPE] [--max N] [--dir DIR]
  bibcli show <citation-key> [--dir DIR]
  bibcli list [--type TYPE] [--max N] [--dir DIR]
  bibcli lookup <isbn-or-title> [--max N]
  bibcli stats [--dir DIR]
  bibcli version
  bibcli help

Output: JSON only. Korean text preserved as-is.

Commands:
  search     Local bib files 검색 (title, author, keywords)
  show       Citation key로 상세 조회
  list       타입별 목록
  lookup     data4library 서지 검색 (ISBN 또는 제목)
  stats      통계

Flags:
  --dir DIR    Bib directory (default: $BIBCLI_DIR or ../output relative to exe)
  --type TYPE  Filter by entry type or bib file stem (e.g. Book, online)
  --max N      Maximum results (search default: 20, list default: 50)

Environment:
  BIBCLI_DIR              Default bib directory (overridden by --dir flag)
  DATA4LIBRARY_API_KEY    data4library API key (lookup command)`)
}
