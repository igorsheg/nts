package cmd

import (
	"errors"
	"fmt"
	"os/exec"
	"sort"

	"github.com/igorsheg/nts/internal/config"
	"github.com/igorsheg/nts/internal/editor"
	"github.com/igorsheg/nts/internal/note"
	"github.com/igorsheg/nts/internal/resolve"
	"github.com/igorsheg/nts/internal/ui"
	"github.com/spf13/cobra"
)

var editCmd = &cobra.Command{
	Use:   "edit [query]",
	Short: "Edit an existing note",
	Long: `Edit an existing note in your editor.

With a query, resolves the note by slug or fuzzy match.
Without a query, opens an interactive picker.`,
	Args: cobra.MaximumNArgs(1),
	RunE: runEdit,
}

func runEdit(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}

	var path string

	if !ui.IsTTY() {
		if len(args) == 0 {
			return fmt.Errorf("query required in non-interactive mode: nts edit <slug>")
		}
	}

	if len(args) > 0 {
		path, err = resolve.Strict(cfg.NotesDir, args[0], config.MetaCachePath())
		if err != nil {
			return err
		}
	} else {
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

	if !ui.IsTTY() {
		return fmt.Errorf("cannot open editor in non-interactive mode")
	}

	if err := editor.Open(cfg.ResolveEditor(), path); err != nil {
		var execErr *exec.Error
		if errors.As(err, &execErr) {
			return fmt.Errorf("could not open editor %q — set $EDITOR or run: nts config --set editor=nvim", cfg.ResolveEditor())
		}
		return fmt.Errorf("opening editor: %w", err)
	}

	fmt.Printf("edited: %s\n", path)
	return nil
}
