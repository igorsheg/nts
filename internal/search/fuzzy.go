package search

import (
	"path/filepath"
	"strings"

	"github.com/igorsheg/nts/internal/note"
	"github.com/sahilm/fuzzy"
)

type Result struct {
	Note           *note.Note
	Score          int
	MatchedIndexes []int
}

type titleSource []*note.Note

func (ts titleSource) String(i int) string { return ts[i].Title }
func (ts titleSource) Len() int            { return len(ts) }

type filenameSource []*note.Note

func (fs filenameSource) String(i int) string {
	return strings.TrimSuffix(filepath.Base(fs[i].Path), ".md")
}
func (fs filenameSource) Len() int { return len(fs) }

func FuzzySearch(query string, notes []*note.Note) []*Result {
	seen := make(map[string]*Result)

	for _, m := range fuzzy.FindFrom(query, titleSource(notes)) {
		seen[notes[m.Index].Path] = &Result{
			Note:           notes[m.Index],
			Score:          m.Score,
			MatchedIndexes: m.MatchedIndexes,
		}
	}

	for _, m := range fuzzy.FindFrom(query, filenameSource(notes)) {
		path := notes[m.Index].Path
		if existing, ok := seen[path]; ok {
			if m.Score > existing.Score {
				existing.Score = m.Score
			}
		} else {
			seen[path] = &Result{
				Note:           notes[m.Index],
				Score:          m.Score,
				MatchedIndexes: m.MatchedIndexes,
			}
		}
	}

	results := make([]*Result, 0, len(seen))
	for _, r := range seen {
		results = append(results, r)
	}

	for i := 1; i < len(results); i++ {
		for j := i; j > 0 && results[j].Score > results[j-1].Score; j-- {
			results[j], results[j-1] = results[j-1], results[j]
		}
	}

	return results
}
