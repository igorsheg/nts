package cmd

import (
	"fmt"
	"strings"

	"github.com/igorsheg/nts/internal/config"
	"github.com/igorsheg/nts/internal/editor"
	"github.com/igorsheg/nts/internal/note"
	"github.com/spf13/cobra"
)

var tags []string

var rootCmd = &cobra.Command{
	Use:   "nts [title]",
	Short: "Note to self — quick markdown notes from your terminal",
	Long:  `nts creates a markdown note with frontmatter and opens it in your editor.`,
	Args:  cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := config.Load()
		if err != nil {
			return fmt.Errorf("loading config: %w", err)
		}

		var title string
		if len(args) > 0 {
			title = args[0]
		}

		var parsedTags []string
		for _, t := range tags {
			for _, s := range strings.Split(t, ",") {
				s = strings.TrimSpace(s)
				if s != "" {
					parsedTags = append(parsedTags, s)
				}
			}
		}

		n := note.New(title, parsedTags, cfg.NotesDir)
		path, err := n.Create()
		if err != nil {
			return err
		}

		editorBin := cfg.ResolveEditor()
		if err := editor.Open(editorBin, path); err != nil {
			return err
		}

		fmt.Printf("saved: %s\n", path)
		return nil
	},
}

func init() {
	rootCmd.Flags().StringSliceVarP(&tags, "tags", "t", nil, "comma-separated tags")
}

func Execute() error {
	return rootCmd.Execute()
}
