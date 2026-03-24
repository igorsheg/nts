package search

import (
	"github.com/igorsheg/nts/internal/note"
	"github.com/sahilm/fuzzy"
)

type Result struct {
	Note           *note.Note
	Score          int
	MatchedIndexes []int
}

type noteSource []*note.Note

func (ns noteSource) String(i int) string { return ns[i].Title }
func (ns noteSource) Len() int            { return len(ns) }

func FuzzySearch(query string, notes []*note.Note) []*Result {
	matches := fuzzy.FindFrom(query, noteSource(notes))

	results := make([]*Result, len(matches))
	for i, m := range matches {
		results[i] = &Result{
			Note:           notes[m.Index],
			Score:          m.Score,
			MatchedIndexes: m.MatchedIndexes,
		}
	}
	return results
}
