package cmd

import (
	"github.com/spf13/cobra"
)

var Version = "dev"

var rootCmd = &cobra.Command{
	Version: Version,
	Use:   "nts [title]",
	Short: "Note to self — quick markdown notes from your terminal",
	Long: `nts creates markdown notes with frontmatter and opens them in your editor.

Examples:
  nts                              Create a date-named note
  nts "Meeting with Lars"          Create a titled note
  nts new -t "standup" -b "text"   Create without opening editor
  nts list                         List all notes
  nts search "auth flow"           Search notes
  nts show meeting-with-lars       Show a note`,
	Args:                  cobra.MaximumNArgs(1),
	DisableFlagParsing:    false,
	RunE:                  runNew,
	SilenceUsage:          true,
	SilenceErrors:         true,
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
