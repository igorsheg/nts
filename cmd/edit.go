package cmd

import (
	"fmt"

	"github.com/igorsheg/nts/internal/config"
	"github.com/igorsheg/nts/internal/editor"
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

	path, err := resolveNotePath(cfg.NotesDir, args[0])
	if err != nil {
		return err
	}

	if err := editor.Open(cfg.ResolveEditor(), path); err != nil {
		return fmt.Errorf("opening editor: %w", err)
	}

	fmt.Printf("edited: %s\n", path)
	return nil
}
