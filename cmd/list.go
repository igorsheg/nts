package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/igorsheg/nts/internal/config"
	"github.com/igorsheg/nts/internal/note"
	"github.com/spf13/cobra"
)

var (
	listLabels []string
	listLimit  int
	listSearch string
	listJSON   bool
)

var listCmd = &cobra.Command{
	Use:     "list",
	Aliases: []string{"ls"},
	Short:   "List notes",
	RunE:    runList,
}

func init() {
	listCmd.Flags().StringSliceVarP(&listLabels, "labels", "l", nil, "filter by labels")
	listCmd.Flags().IntVarP(&listLimit, "limit", "n", 20, "max results")
	listCmd.Flags().StringVarP(&listSearch, "search", "S", "", "filter by search query")
	listCmd.Flags().BoolVar(&listJSON, "json", false, "output as JSON")
}

func runList(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}

	notes, err := note.ParseAll(cfg.NotesDir)
	if err != nil {
		return fmt.Errorf("reading notes: %w", err)
	}

	sort.Slice(notes, func(i, j int) bool {
		return notes[i].Date.After(notes[j].Date)
	})

	if len(listLabels) > 0 {
		notes = filterByLabels(notes, listLabels)
	}

	if listSearch != "" {
		notes = filterBySearch(notes, listSearch)
	}

	if listLimit > 0 && len(notes) > listLimit {
		notes = notes[:listLimit]
	}

	if listJSON {
		out := make([]jsonNote, len(notes))
		for i, n := range notes {
			out[i] = noteToJSON(n)
		}
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(out)
	}

	if len(notes) == 0 {
		fmt.Println("no notes found")
		return nil
	}

	for _, n := range notes {
		date := n.Date.Format("2006-01-02")
		labels := ""
		if len(n.Labels) > 0 {
			labels = " [" + strings.Join(n.Labels, ", ") + "]"
		}
		title := n.Title
		if title == "" {
			title = "(untitled)"
		}
		fmt.Printf("%s  %s%s\n", date, title, labels)
	}

	return nil
}

func filterByLabels(notes []*note.Note, labels []string) []*note.Note {
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

func filterBySearch(notes []*note.Note, query string) []*note.Note {
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
