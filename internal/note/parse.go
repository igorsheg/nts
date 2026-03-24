package note

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/adrg/frontmatter"
	devctx "github.com/igorsheg/nts/internal/context"
	"gopkg.in/yaml.v2"
)

type FrontmatterContext struct {
	Project   string `yaml:"project"`
	Branch    string `yaml:"branch"`
	Directory string `yaml:"directory"`
}

type FrontmatterData struct {
	Title   string             `yaml:"title"`
	Date    string             `yaml:"date"`
	Tags    []string           `yaml:"tags"`
	Context FrontmatterContext `yaml:"context"`
}

var fmFormats = []*frontmatter.Format{
	frontmatter.NewFormat("---", "---", yaml.Unmarshal),
}

func Parse(path string) (*Note, error) {
	resolved, err := filepath.Abs(path)
	if err != nil {
		return nil, fmt.Errorf("resolving path: %w", err)
	}

	f, err := os.Open(resolved)
	if err != nil {
		return nil, fmt.Errorf("opening note: %w", err)
	}
	defer f.Close()

	var fm FrontmatterData
	body, err := frontmatter.Parse(f, &fm, fmFormats...)
	if err != nil {
		return nil, fmt.Errorf("parsing frontmatter: %w", err)
	}

	var date time.Time
	if fm.Date != "" {
		date, err = time.Parse(time.RFC3339, fm.Date)
		if err != nil {
			return nil, fmt.Errorf("parsing date %q: %w", fm.Date, err)
		}
	}

	return &Note{
		Title:  fm.Title,
		Labels: fm.Tags,
		Date:   date,
		Body:   strings.TrimSpace(string(body)),
		Dir:    filepath.Dir(resolved),
		Path:   resolved,
		Context: devctx.Context{
			Project:   fm.Context.Project,
			Branch:    fm.Context.Branch,
			Directory: fm.Context.Directory,
		},
	}, nil
}

func ParseAll(dir string) ([]*Note, error) {
	var notes []*Note

	err := filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || filepath.Ext(path) != ".md" {
			return nil
		}

		n, err := Parse(path)
		if err != nil {
			return fmt.Errorf("parsing %s: %w", path, err)
		}
		notes = append(notes, n)
		return nil
	})
	if err != nil {
		return nil, err
	}

	return notes, nil
}
