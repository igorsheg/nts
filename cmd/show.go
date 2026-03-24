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
	path, err := resolveNotePath(cfg.NotesDir, query)
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

func resolveNotePath(notesDir, query string) (string, error) {
	direct := filepath.Join(notesDir, query)
	if _, err := os.Stat(direct); err == nil {
		return direct, nil
	}

	withExt := filepath.Join(notesDir, query+".md")
	if _, err := os.Stat(withExt); err == nil {
		return withExt, nil
	}

	notes, err := note.ParseAllCached(notesDir, config.MetaCachePath())
	if err != nil {
		return "", fmt.Errorf("reading notes: %w", err)
	}

	results := search.FuzzySearch(query, notes)
	if len(results) > 0 {
		return results[0].Note.Path, nil
	}

	return "", fmt.Errorf("note not found: %s", query)
}
