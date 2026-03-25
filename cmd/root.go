package cmd

import (
	"fmt"
	"os"

	"github.com/igorsheg/nts/internal/config"
	"github.com/igorsheg/nts/internal/ui"
	"github.com/spf13/cobra"
)

var Version = "dev"

var rootCmd = &cobra.Command{
	Version: Version,
	Use:     "nts [title]",
	Short:   "Note to self — quick markdown notes from your terminal",
	Long: `nts creates markdown notes with frontmatter and opens them in your editor.

Examples:
  nts "Meeting with Lars"          Create a titled note
  nts new -t "standup" -b "text"   Create without opening editor
  nts list                         List all notes
  nts search "auth flow"           Search notes
  nts show meeting-with-lars       Show a note`,
	Args: cobra.ArbitraryArgs,
	PersistentPreRun: func(cmd *cobra.Command, args []string) {
		checkFirstRun()
	},
	RunE: func(cmd *cobra.Command, args []string) error {
		if len(args) == 0 {
			return cmd.Help()
		}
		return runNew(cmd, args)
	},
	SilenceUsage:  true,
	SilenceErrors: true,
}

func init() {
	rootCmd.AddCommand(newCmd)
	rootCmd.AddCommand(listCmd)
	rootCmd.AddCommand(showCmd)
	rootCmd.AddCommand(searchCmd)
	rootCmd.AddCommand(configCmd)
	rootCmd.AddCommand(appendCmd)
	rootCmd.AddCommand(editCmd)

	rootCmd.Flags().StringVarP(&newTitle, "title", "t", "", "note title")
	rootCmd.Flags().StringSliceVarP(&newLabels, "labels", "l", nil, "comma-separated labels")
	rootCmd.Flags().StringVarP(&newBody, "body", "b", "", "body text (skips editor)")
	rootCmd.Flags().StringVarP(&newBodyFile, "body-file", "F", "", "read body from file (- for stdin)")
	rootCmd.Flags().BoolVarP(&newEditor, "editor", "e", false, "force editor even with --body")
	rootCmd.Flags().BoolVar(&newJSON, "json", false, "output created note as JSON")
}

func Execute() error {
	return rootCmd.Execute()
}

func checkFirstRun() {
	cfg, err := config.Load()
	if err != nil {
		return
	}
	if _, err := os.Stat(cfg.NotesDir); err == nil {
		return
	}
	if !ui.IsTTY() {
		return
	}
	fmt.Println(ui.Hint(fmt.Sprintf("welcome to nts — notes will be saved to %s", cfg.NotesDir)))
	fmt.Println(ui.Hint("change with: nts config --set notes_dir=/path/to/notes"))
	fmt.Println()
}
