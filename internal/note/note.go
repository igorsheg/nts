package note

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/igorsheg/nts/internal/gitctx"
	"gopkg.in/yaml.v2"
)

type Note struct {
	Title   string
	Labels  []string
	Date    time.Time
	Body    string
	Dir     string
	Path    string
	Context gitctx.Context
}

func New(title string, labels []string, dir string) Note {
	n := Note{
		Title:  title,
		Labels: labels,
		Date:   time.Now(),
		Dir:    dir,
	}
	n.Path = filepath.Join(n.Dir, n.Filename())
	return n
}

type frontmatterYAML struct {
	Title   string       `yaml:"title"`
	Date    string       `yaml:"date"`
	Tags    []string     `yaml:"tags"`
	Context *contextYAML `yaml:"context,omitempty"`
}

type contextYAML struct {
	Project string   `yaml:"project,omitempty"`
	Branch  string   `yaml:"branch,omitempty"`
	Issue   string   `yaml:"issue,omitempty"`
	RepoDir string   `yaml:"repo_dir,omitempty"`
	Commit  string   `yaml:"commit,omitempty"`
	Dirty   *bool    `yaml:"dirty,omitempty"`
	Files   []string `yaml:"files,omitempty"`
}

func (n Note) Frontmatter() string {
	title := n.Title
	if title == "" {
		title = "Untitled"
	}

	fm := frontmatterYAML{
		Title: title,
		Date:  n.Date.Format(time.RFC3339),
		Tags:  n.Labels,
	}

	if !n.Context.IsEmpty() {
		fm.Context = &contextYAML{
			Project: n.Context.Project,
			Branch:  n.Context.Branch,
			Issue:   n.Context.Issue,
			RepoDir: n.Context.RepoDir,
			Commit:  n.Context.Commit,
			Dirty:   n.Context.Dirty,
			Files:   n.Context.Files,
		}
	}

	data, _ := yaml.Marshal(fm)
	return "---\n" + string(data) + "---\n"
}

func (n Note) Filename() string {
	if n.Title != "" {
		return slugify(n.Title) + ".md"
	}
	return fmt.Sprintf("nts-%s.md", n.Date.Format("2006-01-02"))
}

func (n Note) Create() (string, error) {
	if err := os.MkdirAll(n.Dir, 0o755); err != nil {
		return "", fmt.Errorf("creating notes directory: %w", err)
	}

	path := dedup(n.Path)

	content := n.Frontmatter() + "\n" + n.Body

	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		return "", fmt.Errorf("writing note: %w", err)
	}

	return path, nil
}

var nonAlphaNum = regexp.MustCompile(`[^a-z0-9]+`)

func slugify(s string) string {
	s = strings.ToLower(s)
	s = nonAlphaNum.ReplaceAllString(s, "-")
	s = strings.Trim(s, "-")
	return s
}

func dedup(path string) string {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return path
	}

	ext := filepath.Ext(path)
	base := strings.TrimSuffix(path, ext)

	for i := 1; ; i++ {
		candidate := fmt.Sprintf("%s-%d%s", base, i, ext)
		if _, err := os.Stat(candidate); os.IsNotExist(err) {
			return candidate
		}
	}
}
