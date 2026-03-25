package resolve

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/igorsheg/nts/internal/note"
	"github.com/igorsheg/nts/internal/search"
)

func Exact(notesDir, query string) (string, bool) {
	direct := filepath.Join(notesDir, query)
	if _, err := os.Stat(direct); err == nil {
		return direct, true
	}

	withExt := filepath.Join(notesDir, query+".md")
	if _, err := os.Stat(withExt); err == nil {
		return withExt, true
	}

	return "", false
}

func Strict(notesDir, query, cachePath string) (string, error) {
	if path, ok := Exact(notesDir, query); ok {
		return path, nil
	}

	notes, err := note.ParseAllCached(notesDir, cachePath)
	if err != nil {
		return "", fmt.Errorf("reading notes: %w", err)
	}

	results := search.FuzzySearch(query, notes)
	if len(results) == 0 {
		return "", fmt.Errorf("note not found: %s", query)
	}
	if len(results) == 1 {
		return results[0].Note.Path, nil
	}

	msg := fmt.Sprintf("ambiguous match for %q, found %d notes:", query, len(results))
	limit := len(results)
	if limit > 5 {
		limit = 5
	}
	for i := 0; i < limit; i++ {
		title := results[i].Note.Title
		if title == "" {
			title = "(untitled)"
		}
		slug := strings.TrimSuffix(filepath.Base(results[i].Note.Path), ".md")
		msg += fmt.Sprintf("\n  %s\t%s", slug, title)
	}
	if len(results) > 5 {
		msg += fmt.Sprintf("\n  ... and %d more", len(results)-5)
	}
	msg += "\nuse the full slug to be specific"
	return "", fmt.Errorf("%s", msg)
}
