package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/charmbracelet/glamour"
	"github.com/igorsheg/nts/internal/config"
	"github.com/igorsheg/nts/internal/note"
	"github.com/igorsheg/nts/internal/resolve"
	"github.com/igorsheg/nts/internal/ui"
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
	path, err := resolve.Strict(cfg.NotesDir, query, config.MetaCachePath())
	if err != nil {
		return err
	}

	n, err := note.Parse(path)
	if err != nil {
		return fmt.Errorf("could not parse note at %s — check the frontmatter YAML", path)
	}

	if showJSON {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(ui.NoteToJSON(n))
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
