package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/glamour"
	"github.com/igorsheg/nts/internal/config"
	"github.com/igorsheg/nts/internal/note"
	"github.com/igorsheg/nts/internal/search"
	"github.com/spf13/cobra"
	"golang.org/x/term"
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
	showCmd.Flags().BoolVar(&showRaw, "raw", false, "raw markdown, no rendering")
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
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("reading note: %w", err)
		}
		fmt.Print(string(data))
		return nil
	}

	isTTY := term.IsTerminal(int(os.Stdout.Fd()))
	if !isTTY {
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("reading note: %w", err)
		}
		fmt.Print(string(data))
		return nil
	}

	return renderPretty(n)
}

func renderPretty(n *note.Note) error {
	var header strings.Builder
	header.WriteString(fmt.Sprintf("# %s\n", n.Title))
	header.WriteString(fmt.Sprintf("*%s*", n.Date.Format("2006-01-02 15:04")))
	if len(n.Labels) > 0 {
		header.WriteString(fmt.Sprintf("  `%s`", strings.Join(n.Labels, "` `")))
	}
	if n.Context.Project != "" {
		header.WriteString(fmt.Sprintf("  📂 %s", n.Context.Project))
		if n.Context.Branch != "" {
			header.WriteString(fmt.Sprintf("@%s", n.Context.Branch))
		}
	}
	header.WriteString("\n\n---\n\n")

	content := header.String() + n.Body

	width := 80
	if w, _, err := term.GetSize(int(os.Stdout.Fd())); err == nil && w > 0 {
		width = w
	}

	renderer, err := glamour.NewTermRenderer(
		glamour.WithAutoStyle(),
		glamour.WithWordWrap(width),
	)
	if err != nil {
		fmt.Print(content)
		return nil
	}

	out, err := renderer.Render(content)
	if err != nil {
		fmt.Print(content)
		return nil
	}

	fmt.Print(out)
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
