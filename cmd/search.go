package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/igorsheg/nts/internal/config"
	"github.com/igorsheg/nts/internal/note"
	"github.com/igorsheg/nts/internal/search"
	"github.com/igorsheg/nts/internal/ui"
	"github.com/spf13/cobra"
)

var (
	searchLabels  []string
	searchLimit   int
	searchJSON    bool
	searchProject string
)

var searchCmd = &cobra.Command{
	Use:   "search <query>",
	Short: "Search notes",
	Long: `Search notes by title (fuzzy) and content (full-text).
Uses fuzzy matching on titles and BM25 full-text search on content.`,
	Args: cobra.ExactArgs(1),
	RunE: runSearch,
}

func init() {
	searchCmd.Flags().StringSliceVarP(&searchLabels, "labels", "l", nil, "filter by labels")
	searchCmd.Flags().IntVarP(&searchLimit, "limit", "n", 10, "max results")
	searchCmd.Flags().StringVarP(&searchProject, "project", "p", "", "filter by project")
	searchCmd.Flags().BoolVar(&searchJSON, "json", false, "output as JSON")
}

func runSearch(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}

	query := args[0]

	notes, err := note.ParseAllCached(cfg.NotesDir, config.MetaCachePath())
	if err != nil {
		return fmt.Errorf("reading notes: %w", err)
	}

	if len(searchLabels) > 0 {
		notes = ui.FilterByLabels(notes, searchLabels)
	}

	if searchProject != "" {
		notes = ui.FilterByProject(notes, searchProject)
	}

	fuzzyResults := search.FuzzySearch(query, notes)

	ix, err := search.OpenIndex(config.IndexPath())
	if err != nil {
		return fmt.Errorf("search index corrupted — delete %s and retry", config.IndexPath())
	}
	defer ix.Close()

	if _, err := ix.IndexChanged(notes); err != nil {
		return fmt.Errorf("indexing notes: %w", err)
	}

	bleveResults, err := ix.Search(query, searchLimit)
	if err != nil {
		return fmt.Errorf("searching index: %w", err)
	}

	merged := mergeResults(fuzzyResults, bleveResults, notes, searchLimit)

	if searchJSON {
		out := make([]searchResultJSON, len(merged))
		for i, r := range merged {
			out[i] = searchResultJSON{
				Title:  r.Note.Title,
				Date:   r.Note.Date.Format("2006-01-02T15:04:05Z07:00"),
				Labels: r.Note.Labels,
				Path:   r.Note.Path,
				Score:  r.Score,
			}
		}
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(out)
	}

	if len(merged) == 0 {
		fmt.Println("no results")
		if hint := ui.Hint("try broader terms, or create: nts \"" + query + "\""); hint != "" {
			fmt.Println(hint)
		}
		return nil
	}

	for _, r := range merged {
		fmt.Println(ui.FormatSearchRow(r.Note, r.Score))
	}

	return nil
}

type searchResultJSON struct {
	Title  string   `json:"title"`
	Date   string   `json:"date"`
	Labels []string `json:"labels"`
	Path   string   `json:"path"`
	Score  int      `json:"score"`
}

func mergeResults(fuzzyResults, bleveResults []*search.Result, notes []*note.Note, limit int) []*search.Result {
	seen := make(map[string]*search.Result)

	for _, r := range fuzzyResults {
		seen[r.Note.Path] = r
	}

	notesByPath := make(map[string]*note.Note)
	for _, n := range notes {
		notesByPath[n.Path] = n
	}

	for _, r := range bleveResults {
		if existing, ok := seen[r.Note.Path]; ok {
			existing.Score += r.Score
		} else if n, ok := notesByPath[r.Note.Path]; ok {
			r.Note = n
			seen[r.Note.Path] = r
		}
	}

	merged := make([]*search.Result, 0, len(seen))
	for _, r := range seen {
		merged = append(merged, r)
	}

	sort := func(i, j int) bool { return merged[i].Score > merged[j].Score }
	sortResults(merged, sort)

	if limit > 0 && len(merged) > limit {
		merged = merged[:limit]
	}

	return merged
}

func sortResults(results []*search.Result, less func(i, j int) bool) {
	for i := 1; i < len(results); i++ {
		for j := i; j > 0 && less(j, j-1); j-- {
			results[j], results[j-1] = results[j-1], results[j]
		}
	}
}
