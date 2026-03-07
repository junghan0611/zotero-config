package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// data4library API response structures
type d4lSearchResponse struct {
	Response struct {
		NumFound int `json:"numFound"`
		Docs     []struct {
			Doc d4lBook `json:"doc"`
		} `json:"docs"`
	} `json:"response"`
}

type d4lDetailResponse struct {
	Response struct {
		Detail []struct {
			Book d4lBook `json:"book"`
		} `json:"detail"`
	} `json:"response"`
}

type d4lBook struct {
	BookName        string `json:"bookname"`
	Authors         string `json:"authors"`
	Publisher       string `json:"publisher"`
	PublicationDate string `json:"publication_date,omitempty"`
	PublicationYear string `json:"publication_year"`
	ISBN            string `json:"isbn,omitempty"`
	ISBN13          string `json:"isbn13"`
	AdditionSymbol  string `json:"addition_symbol,omitempty"`
	Vol             string `json:"vol,omitempty"`
	ClassNo         string `json:"class_no"`
	ClassNm         string `json:"class_nm"`
	Description     string `json:"description,omitempty"`
	BookImageURL    string `json:"bookImageURL,omitempty"`
}

// lookupResult is the JSON output for lookup command
type lookupResult struct {
	ISBN13      string `json:"isbn13"`
	Title       string `json:"title"`
	Authors     string `json:"authors"`
	Publisher   string `json:"publisher"`
	Year        string `json:"year"`
	KDC         string `json:"kdc"`
	KDCName     string `json:"kdc_name"`
	Description string `json:"description,omitempty"`
	ImageURL    string `json:"image_url,omitempty"`
}

func cmdLookup(args []string) {
	pos, flags := parseFlags(args)
	if len(pos) == 0 {
		fmt.Fprintln(os.Stderr, "usage: bibcli lookup <isbn-or-title> [--max N]")
		fmt.Fprintln(os.Stderr, "")
		fmt.Fprintln(os.Stderr, "  ISBN (13자리 숫자):  data4library ISBN 조회")
		fmt.Fprintln(os.Stderr, "  그 외:              data4library 제목 검색")
		fmt.Fprintln(os.Stderr, "")
		fmt.Fprintln(os.Stderr, "Environment:")
		fmt.Fprintln(os.Stderr, "  DATA4LIBRARY_API_KEY  API key (required)")
		os.Exit(1)
	}

	apiKey := os.Getenv("DATA4LIBRARY_API_KEY")
	if apiKey == "" {
		// try loading from .envrc in parent dir
		apiKey = loadEnvrcKey("DATA4LIBRARY_API_KEY")
	}
	if apiKey == "" {
		fmt.Fprintln(os.Stderr, "error: DATA4LIBRARY_API_KEY not set")
		os.Exit(1)
	}

	query := strings.Join(pos, " ")
	maxVal := 5
	if m, ok := flags["max"]; ok {
		n := 5
		fmt.Sscanf(m, "%d", &n)
		if n > 0 {
			maxVal = n
		}
	}

	// Detect ISBN vs title
	cleaned := strings.ReplaceAll(query, "-", "")
	isISBN := len(cleaned) >= 10 && isAllDigits(cleaned)

	if isISBN {
		result, err := lookupByISBN(apiKey, cleaned)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error: %v\n", err)
			os.Exit(1)
		}
		if result == nil {
			writeJSON([]lookupResult{})
			return
		}
		writeJSON([]lookupResult{*result})
	} else {
		results, err := lookupByTitle(apiKey, query, maxVal)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error: %v\n", err)
			os.Exit(1)
		}
		writeJSON(results)
	}
}

func isAllDigits(s string) bool {
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

func lookupByISBN(apiKey, isbn string) (*lookupResult, error) {
	u := fmt.Sprintf(
		"https://data4library.kr/api/srchDtlList?authKey=%s&isbn13=%s&format=json",
		url.QueryEscape(apiKey), url.QueryEscape(isbn),
	)

	body, err := httpGet(u)
	if err != nil {
		return nil, err
	}

	var resp d4lDetailResponse
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, fmt.Errorf("parse error: %w", err)
	}

	if len(resp.Response.Detail) == 0 {
		return nil, nil
	}

	book := resp.Response.Detail[0].Book
	return bookToResult(book), nil
}

func lookupByTitle(apiKey, title string, max int) ([]lookupResult, error) {
	u := fmt.Sprintf(
		"https://data4library.kr/api/srchBooks?authKey=%s&title=%s&format=json&pageSize=%d",
		url.QueryEscape(apiKey), url.QueryEscape(title), max,
	)

	body, err := httpGet(u)
	if err != nil {
		return nil, err
	}

	var resp d4lSearchResponse
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, fmt.Errorf("parse error: %w", err)
	}

	results := make([]lookupResult, 0, len(resp.Response.Docs))
	for _, doc := range resp.Response.Docs {
		results = append(results, *bookToResult(doc.Doc))
	}
	return results, nil
}

func bookToResult(book d4lBook) *lookupResult {
	year := book.PublicationYear
	if year == "" {
		year = book.PublicationDate
	}
	return &lookupResult{
		ISBN13:      book.ISBN13,
		Title:       strings.TrimSpace(book.BookName),
		Authors:     strings.TrimSpace(book.Authors),
		Publisher:   strings.TrimSpace(book.Publisher),
		Year:        year,
		KDC:         strings.TrimSpace(book.ClassNo),
		KDCName:     strings.TrimSpace(book.ClassNm),
		Description: strings.TrimSpace(book.Description),
		ImageURL:    book.BookImageURL,
	}
}

func httpGet(rawURL string) ([]byte, error) {
	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest("GET", rawURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "bibcli/1.0")

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	return io.ReadAll(resp.Body)
}

// loadEnvrcKey tries to read a key from .envrc files
func loadEnvrcKey(key string) string {
	// Try common locations
	paths := []string{
		"../.envrc",
	}
	exe, err := os.Executable()
	if err == nil {
		paths = append(paths, filepath.Join(filepath.Dir(exe), "..", ".envrc"))
	}

	for _, p := range paths {
		data, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(data), "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "export ") {
				line = strings.TrimPrefix(line, "export ")
			}
			if strings.HasPrefix(line, key+"=") {
				val := strings.TrimPrefix(line, key+"=")
				val = strings.Trim(val, "\"'")
				return val
			}
		}
	}
	return ""
}
