package cmd

import (
	"path/filepath"
	"strings"

	"github.com/igorsheg/nts/internal/config"
	"github.com/igorsheg/nts/internal/note"
	"github.com/spf13/cobra"
)

func noteSlugCompletion(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
	if len(args) > 0 {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}

	cfg, _ := config.Load()
	notes, err := note.ParseAllCached(cfg.NotesDir, config.MetaCachePath())
	if err != nil || len(notes) == 0 {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}

	var completions []string
	for _, n := range notes {
		slug := strings.TrimSuffix(filepath.Base(n.Path), ".md")
		if toComplete == "" || strings.HasPrefix(slug, toComplete) {
			desc := n.Title
			if desc == "" {
				desc = "(untitled)"
			}
			completions = append(completions, slug+"\t"+desc)
		}
	}
	return completions, cobra.ShellCompDirectiveNoFileComp
}

func init() {
	showCmd.ValidArgsFunction = noteSlugCompletion
	editCmd.ValidArgsFunction = noteSlugCompletion
	appendCmd.ValidArgsFunction = noteSlugCompletion
}
