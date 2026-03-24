package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/igorsheg/nts/internal/config"
	"github.com/spf13/cobra"
)

var (
	configSet string
	configGet string
)

var configCmd = &cobra.Command{
	Use:   "config",
	Short: "Show or modify configuration",
	RunE:  runConfig,
}

func init() {
	configCmd.Flags().StringVar(&configSet, "set", "", "set a config value (key=value)")
	configCmd.Flags().StringVar(&configGet, "get", "", "get a config value")
}

func runConfig(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}

	if configGet != "" {
		switch configGet {
		case "notes_dir":
			fmt.Println(cfg.NotesDir)
		case "editor":
			fmt.Println(cfg.ResolveEditor())
		default:
			return fmt.Errorf("unknown config key: %s", configGet)
		}
		return nil
	}

	if configSet != "" {
		parts := strings.SplitN(configSet, "=", 2)
		if len(parts) != 2 {
			return fmt.Errorf("invalid format, use key=value")
		}
		key, val := parts[0], parts[1]
		switch key {
		case "notes_dir":
			cfg.NotesDir = val
		case "editor":
			cfg.Editor = val
		default:
			return fmt.Errorf("unknown config key: %s", key)
		}
		if err := cfg.Save(); err != nil {
			return fmt.Errorf("saving config: %w", err)
		}
		fmt.Printf("%s=%s\n", key, val)
		return nil
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(cfg)
}
