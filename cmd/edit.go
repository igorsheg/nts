package cmd

import (
	"errors"
	"fmt"
	"os/exec"

	"github.com/igorsheg/nts/internal/config"
	"github.com/igorsheg/nts/internal/editor"
	"github.com/igorsheg/nts/internal/resolve"
	"github.com/spf13/cobra"
)

var editCmd = &cobra.Command{
	Use:   "edit <query>",
	Short: "Edit an existing note",
	Args:  cobra.ExactArgs(1),
	RunE:  runEdit,
}

func runEdit(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}

	path, err := resolve.Strict(cfg.NotesDir, args[0], config.MetaCachePath())
	if err != nil {
		return err
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
