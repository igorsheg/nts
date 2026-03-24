package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/igorsheg/nts/internal/config"
	"github.com/igorsheg/nts/internal/note"
	"github.com/igorsheg/nts/internal/search"
	"github.com/spf13/cobra"
)

var (
	showJSON bool
	showRaw  bool
)

var showCmd = &cobra.Command{
	Use:   "show <path-or-slug>",
	Short: "Show a note",
	Args:  cobra.ExactArgs(1),
	RunE:  runShow,
}

func init() {
	showCmd.Flags().BoolVar(&showJSON, "json", false, "output as JSON")
	showCmd.Flags().BoolVar(&showRaw, "raw", false, "body only, no frontmatter")
}

func runShow(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}

	query := args[0]
	path, err := resolveNotePathStrict(cfg.NotesDir, query)
	if err != nil {
		return err
	}

	n, err := note.Parse(path)
	if err != nil {
		return fmt.Errorf("parsing note: %w", err)
	}

	if showJSON {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(noteToJSON(n))
	}

	if showRaw {
		fmt.Print(n.Body)
		if n.Body != "" && !strings.HasSuffix(n.Body, "\n") {
			fmt.Println()
		}
		return nil
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("reading note: %w", err)
	}
	fmt.Print(string(data))
	return nil
}

func resolveNotePathStrict(notesDir, query string) (string, error) {
	if path, ok := resolveExact(notesDir, query); ok {
		return path, nil
	}

	notes, err := note.ParseAllCached(notesDir, config.MetaCachePath())
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

func resolveExact(notesDir, query string) (string, bool) {
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
