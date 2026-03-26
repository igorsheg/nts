package cmd

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/charmbracelet/glamour"
	"github.com/igorsheg/nts/internal/config"
	"github.com/igorsheg/nts/internal/note"
	"github.com/igorsheg/nts/internal/resolve"
	"github.com/igorsheg/nts/internal/ui"
	"github.com/spf13/cobra"
	"golang.org/x/term"
)

//go:embed mdstyle.json
var defaultMDStyle []byte

var (
	showJSON bool
	showRaw  bool
)

var showCmd = &cobra.Command{
	Use:   "show [slug]",
	Short: "Show a note",
	Long: `Show a note's contents.

With a slug, resolves and displays the note.
Without a slug, opens an interactive picker (TTY only).`,
	Args: cobra.MaximumNArgs(1),
	RunE: runShow,
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

	var path string

	if len(args) > 0 {
		path, err = resolve.Strict(cfg.NotesDir, args[0], config.MetaCachePath())
		if err != nil {
			return err
		}
	} else {
		if !ui.IsTTY() {
			return fmt.Errorf("slug required in non-interactive mode: nts show <slug>")
		}
		notes, err := note.ParseAllCached(cfg.NotesDir, config.MetaCachePath())
		if err != nil {
			return fmt.Errorf("reading notes: %w", err)
		}
		if len(notes) == 0 {
			fmt.Println("no notes yet — create one with: nts \"My first note\"")
			return nil
		}
		sort.Slice(notes, func(i, j int) bool {
			return notes[i].Date.After(notes[j].Date)
		})
		result, err := ui.RunPicker(notes)
		if err != nil {
			return fmt.Errorf("picker: %w", err)
		}
		if result.Canceled {
			return nil
		}
		path = result.Path
	}

	n, err := note.Parse(path)
	if err != nil {
		return fmt.Errorf("could not parse note at %s — check the frontmatter YAML", path)
	}

	if showJSON {
		slug := strings.TrimSuffix(filepath.Base(path), ".md")
		return ui.PrintEnvelope(ui.Success(
			fmt.Sprintf("nts show %s", slug),
			ui.NoteToJSON(n),
			ui.NoteActions(slug),
		))
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

	var styleOpt glamour.TermRendererOption
	if os.Getenv("GLAMOUR_STYLE") != "" {
		styleOpt = glamour.WithEnvironmentConfig()
	} else {
		styleOpt = glamour.WithStylesFromJSONBytes(defaultMDStyle)
	}

	renderer, err := glamour.NewTermRenderer(
		styleOpt,
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
