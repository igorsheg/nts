package note

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

type Note struct {
	Title string
	Tags  []string
	Date  time.Time
	Dir   string
}

func New(title string, tags []string, dir string) Note {
	return Note{
		Title: title,
		Tags:  tags,
		Date:  time.Now(),
		Dir:   dir,
	}
}

func (n Note) Frontmatter() string {
	title := n.Title
	if title == "" {
		title = "Untitled"
	}

	tags := "[]"
	if len(n.Tags) > 0 {
		quoted := make([]string, len(n.Tags))
		for i, t := range n.Tags {
			quoted[i] = fmt.Sprintf("%q", t)
		}
		tags = fmt.Sprintf("[%s]", strings.Join(quoted, ", "))
	}

	return fmt.Sprintf(`---
title: %s
date: %s
tags: %s
---

`, title, n.Date.Format(time.RFC3339), tags)
}

func (n Note) Filename() string {
	if n.Title != "" {
		return slugify(n.Title) + ".md"
	}
	return fmt.Sprintf("nts-%s.md", n.Date.Format("2006-01-02"))
}

func (n Note) Path() string {
	return filepath.Join(n.Dir, n.Filename())
}

func (n Note) Create() (string, error) {
	if err := os.MkdirAll(n.Dir, 0o755); err != nil {
		return "", fmt.Errorf("creating notes directory: %w", err)
	}

	path := n.Path()
	path = dedup(path)

	if err := os.WriteFile(path, []byte(n.Frontmatter()), 0o644); err != nil {
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
