package context

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type Context struct {
	Project   string `yaml:"project,omitempty" json:"project,omitempty"`
	Branch    string `yaml:"branch,omitempty" json:"branch,omitempty"`
	Directory string `yaml:"directory,omitempty" json:"directory,omitempty"`
}

func Detect() Context {
	var c Context

	if dir, err := os.Getwd(); err == nil {
		c.Directory = shortenHome(dir)
	}

	root := gitCmd("rev-parse", "--show-toplevel")
	if root == "" {
		return c
	}
	c.Project = filepath.Base(root)

	if branch := gitCmd("symbolic-ref", "--short", "HEAD"); branch != "" {
		c.Branch = branch
	} else {
		c.Branch = gitCmd("rev-parse", "--short", "HEAD")
	}

	return c
}

func (c Context) IsEmpty() bool {
	return c.Project == "" && c.Branch == "" && c.Directory == ""
}

func gitCmd(args ...string) string {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	out, err := exec.CommandContext(ctx, "git", args...).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func shortenHome(dir string) string {
	if home, err := os.UserHomeDir(); err == nil {
		if rel, err := filepath.Rel(home, dir); err == nil && !strings.HasPrefix(rel, "..") {
			return "~/" + rel
		}
	}
	return dir
}
