package note

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	devctx "github.com/igorsheg/nts/internal/context"
)

type Note struct {
	Title   string
	Labels  []string
	Date    time.Time
	Body    string
	Dir     string
	Path    string
	Context devctx.Context
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

func (n Note) Frontmatter() string {
	title := n.Title
	if title == "" {
		title = "Untitled"
	}

	tags := "[]"
	if len(n.Labels) > 0 {
		quoted := make([]string, len(n.Labels))
		for i, l := range n.Labels {
			quoted[i] = l
		}
		tags = fmt.Sprintf("[%s]", strings.Join(quoted, ", "))
	}

	ctx := ""
	if !n.Context.IsEmpty() {
		ctx = "context:\n"
		if n.Context.Project != "" {
			ctx += fmt.Sprintf("  project: %s\n", n.Context.Project)
		}
		if n.Context.Branch != "" {
			ctx += fmt.Sprintf("  branch: %s\n", n.Context.Branch)
		}
		if n.Context.Issue != "" {
			ctx += fmt.Sprintf("  issue: %s\n", n.Context.Issue)
		}
		if n.Context.RepoDir != "" {
			ctx += fmt.Sprintf("  repo_dir: %s\n", n.Context.RepoDir)
		}
		if n.Context.Commit != "" {
			ctx += fmt.Sprintf("  commit: %s\n", n.Context.Commit)
		}
		if n.Context.Dirty != nil {
			ctx += fmt.Sprintf("  dirty: %t\n", *n.Context.Dirty)
		}
		if len(n.Context.Files) > 0 {
			ctx += "  files:\n"
			for _, f := range n.Context.Files {
				ctx += fmt.Sprintf("    - %s\n", f)
			}
		}
	}

	return fmt.Sprintf(`---
title: %q
date: %s
tags: %s
%s---
`, title, n.Date.Format(time.RFC3339), tags, ctx)
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
