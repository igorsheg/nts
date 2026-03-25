package cmd

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"

	devctx "github.com/igorsheg/nts/internal/context"
	"github.com/igorsheg/nts/internal/config"
	"github.com/igorsheg/nts/internal/editor"
	"github.com/igorsheg/nts/internal/note"
	"github.com/spf13/cobra"
)

var (
	newTitle    string
	newLabels  []string
	newBody    string
	newBodyFile string
	newEditor  bool
	newJSON    bool
)

var newCmd = &cobra.Command{
	Use:   "new [title]",
	Short: "Create a new note",
	Long:  `Create a new markdown note with frontmatter and open it in your editor.`,
	Args:  cobra.MaximumNArgs(1),
	RunE:  runNew,
}

func init() {
	newCmd.Flags().StringVarP(&newTitle, "title", "t", "", "note title")
	newCmd.Flags().StringSliceVarP(&newLabels, "labels", "l", nil, "comma-separated labels")
	newCmd.Flags().StringVarP(&newBody, "body", "b", "", "body text (skips editor)")
	newCmd.Flags().StringVarP(&newBodyFile, "body-file", "F", "", "read body from file (- for stdin)")
	newCmd.Flags().BoolVarP(&newEditor, "editor", "e", false, "force editor even with --body")
	newCmd.Flags().BoolVar(&newJSON, "json", false, "output created note as JSON")
}

func runNew(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}

	title := newTitle
	if title == "" && len(args) > 0 {
		title = args[0]
	}

	var parsedLabels []string
	for _, l := range newLabels {
		for _, s := range strings.Split(l, ",") {
			s = strings.TrimSpace(s)
			if s != "" {
				parsedLabels = append(parsedLabels, s)
			}
		}
	}

	body, err := resolveBody()
	if err != nil {
		return err
	}

	n := note.New(title, parsedLabels, cfg.NotesDir)
	n.Body = body
	n.Context = devctx.Detect()

	path, err := n.Create()
	if err != nil {
		return err
	}

	needsEditor := body == "" || newEditor
	if needsEditor {
		editorBin := cfg.ResolveEditor()
		if err := editor.Open(editorBin, path); err != nil {
			return err
		}
	}

	if newJSON {
		parsed, err := note.Parse(path)
		if err != nil {
			return err
		}
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(noteToJSON(parsed))
	}

	fmt.Printf("saved: %s\n", path)
	return nil
}

func resolveBody() (string, error) {
	if newBody != "" {
		return newBody, nil
	}

	if newBodyFile != "" {
		var r io.Reader
		if newBodyFile == "-" {
			r = os.Stdin
		} else {
			f, err := os.Open(newBodyFile)
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

type jsonContext struct {
	Project string   `json:"project,omitempty"`
	Branch  string   `json:"branch,omitempty"`
	Issue   string   `json:"issue,omitempty"`
	RepoDir string   `json:"repo_dir,omitempty"`
	Commit  string   `json:"commit,omitempty"`
	Dirty   *bool    `json:"dirty,omitempty"`
	Files   []string `json:"files,omitempty"`
}

type jsonNote struct {
	Title   string       `json:"title"`
	Date    string       `json:"date"`
	Labels  []string     `json:"labels"`
	Path    string       `json:"path"`
	Body    string       `json:"body,omitempty"`
	Context *jsonContext  `json:"context,omitempty"`
}

func noteToJSON(n *note.Note) jsonNote {
	j := jsonNote{
		Title:  n.Title,
		Date:   n.Date.Format("2006-01-02T15:04:05Z07:00"),
		Labels: n.Labels,
		Path:   n.Path,
		Body:   n.Body,
	}
	if !n.Context.IsEmpty() {
		j.Context = &jsonContext{
			Project: n.Context.Project,
			Branch:  n.Context.Branch,
			Issue:   n.Context.Issue,
			RepoDir: n.Context.RepoDir,
			Commit:  n.Context.Commit,
			Dirty:   n.Context.Dirty,
			Files:   n.Context.Files,
		}
	}
	return j
}
