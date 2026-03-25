package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/igorsheg/nts/internal/config"
	"github.com/igorsheg/nts/internal/note"
	"github.com/igorsheg/nts/internal/ui"
	"github.com/spf13/cobra"
)

var (
	listLabels  []string
	listLimit   int
	listSearch  string
	listJSON    bool
	listProject string
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
	listCmd.Flags().StringVarP(&listProject, "project", "p", "", "filter by project")
	listCmd.Flags().BoolVar(&listJSON, "json", false, "output as JSON")
}

func runList(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}

	notes, err := note.ParseAllCached(cfg.NotesDir, config.MetaCachePath())
	if err != nil {
		return fmt.Errorf("reading notes: %w", err)
	}

	sort.Slice(notes, func(i, j int) bool {
		return notes[i].Date.After(notes[j].Date)
	})

	if len(listLabels) > 0 {
		notes = ui.FilterByLabels(notes, listLabels)
	}

	if listProject != "" {
		notes = ui.FilterByProject(notes, listProject)
	}

	if listSearch != "" {
		notes = ui.FilterBySearch(notes, listSearch)
	}

	if listLimit > 0 && len(notes) > listLimit {
		notes = notes[:listLimit]
	}

	if listJSON {
		out := make([]ui.JSONNote, len(notes))
		for i, n := range notes {
			out[i] = ui.NoteToJSON(n)
		}
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(out)
	}

	if len(notes) == 0 {
		fmt.Println("no notes yet — create one with: nts \"My first note\"")
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
