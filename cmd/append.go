package cmd

import (
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/igorsheg/nts/internal/config"
	"github.com/spf13/cobra"
)

var (
	appendBodyFile string
)

var appendCmd = &cobra.Command{
	Use:   "append <query> [text]",
	Short: "Append text to an existing note",
	Long: `Append text to the body of an existing note.

Examples:
  nts append meeting-with-lars "Action item: follow up on auth migration"
  nts append lars -F notes.md
  echo "new finding" | nts append lars`,
	Args:               cobra.MinimumNArgs(1),
	DisableFlagParsing: false,
	RunE: runAppend,
}

func init() {
	appendCmd.Flags().StringVarP(&appendBodyFile, "body-file", "F", "", "read text from file (- for stdin)")
}

func runAppend(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}

	query := args[0]
	path, err := resolveNotePath(cfg.NotesDir, query)
	if err != nil {
		return err
	}

	text, err := resolveAppendText(args)
	if err != nil {
		return err
	}

	if text == "" {
		return fmt.Errorf("no text provided")
	}

	existing, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("reading note: %w", err)
	}

	content := string(existing)
	if !strings.HasSuffix(content, "\n") {
		content += "\n"
	}
	content += "\n" + text
	if !strings.HasSuffix(content, "\n") {
		content += "\n"
	}

	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		return fmt.Errorf("writing note: %w", err)
	}

	fmt.Printf("appended: %s\n", path)
	return nil
}

func resolveAppendText(args []string) (string, error) {
	if len(args) > 1 {
		return strings.Join(args[1:], " "), nil
	}

	if appendBodyFile != "" {
		var r io.Reader
		if appendBodyFile == "-" {
			r = os.Stdin
		} else {
			f, err := os.Open(appendBodyFile)
			if err != nil {
				return "", fmt.Errorf("opening body file: %w", err)
			}
			defer f.Close()
			r = f
		}
		data, err := io.ReadAll(r)
		if err != nil {
			return "", fmt.Errorf("reading body: %w", err)
		}
		return string(data), nil
	}

	if fi, _ := os.Stdin.Stat(); fi != nil && (fi.Mode()&os.ModeCharDevice) == 0 {
		data, err := io.ReadAll(os.Stdin)
		if err != nil {
			return "", fmt.Errorf("reading stdin: %w", err)
		}
		return string(data), nil
	}

	return "", nil
}
