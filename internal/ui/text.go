package ui

import (
	"strings"

	"github.com/igorsheg/nts/internal/note"
)

func FilterByLabels(notes []*note.Note, labels []string) []*note.Note {
	labelSet := make(map[string]bool)
	for _, l := range labels {
		labelSet[strings.ToLower(strings.TrimSpace(l))] = true
	}

	var filtered []*note.Note
	for _, n := range notes {
		for _, nl := range n.Labels {
			if labelSet[strings.ToLower(nl)] {
				filtered = append(filtered, n)
				break
			}
		}
	}
	return filtered
}

func FilterByProject(notes []*note.Note, project string) []*note.Note {
	p := strings.ToLower(project)
	var filtered []*note.Note
	for _, n := range notes {
		if strings.ToLower(n.Context.Project) == p {
			filtered = append(filtered, n)
		}
	}
	return filtered
}

func FilterBySearch(notes []*note.Note, query string) []*note.Note {
	q := strings.ToLower(query)
	var filtered []*note.Note
	for _, n := range notes {
		if strings.Contains(strings.ToLower(n.Title), q) ||
			strings.Contains(strings.ToLower(n.Body), q) {
			filtered = append(filtered, n)
		}
	}
	return filtered
}
