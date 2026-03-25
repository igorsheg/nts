package gitctx

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const maxFiles = 5

type Context struct {
	Project string   `yaml:"project,omitempty" json:"project,omitempty"`
	Branch  string   `yaml:"branch,omitempty" json:"branch,omitempty"`
	Issue   string   `yaml:"issue,omitempty" json:"issue,omitempty"`
	RepoDir string   `yaml:"repo_dir,omitempty" json:"repo_dir,omitempty"`
	Commit  string   `yaml:"commit,omitempty" json:"commit,omitempty"`
	Dirty   *bool    `yaml:"dirty,omitempty" json:"dirty,omitempty"`
	Files   []string `yaml:"files,omitempty" json:"files,omitempty"`
}

func Detect() Context {
	var c Context

	root := gitCmd("rev-parse", "--show-toplevel")
	if root == "" {
		return c
	}

	c.Project = filepath.Base(root)

	if branch := gitCmd("symbolic-ref", "--short", "HEAD"); branch != "" {
		c.Branch = branch
		c.Issue = parseIssue(branch)
	} else {
		c.Branch = gitCmd("rev-parse", "--short", "HEAD")
	}

	if cwd, err := os.Getwd(); err == nil {
		if rel, err := filepath.Rel(root, cwd); err == nil && rel != "." {
			c.RepoDir = rel
		}
	}

	c.Commit = gitCmd("rev-parse", "--short", "HEAD")

	dirtyFiles := gitCmd("diff", "--name-only")
	stagedFiles := gitCmd("diff", "--name-only", "--cached")
	allDirty := mergeFileLines(dirtyFiles, stagedFiles)

	isDirty := len(allDirty) > 0
	c.Dirty = &isDirty

	if isDirty && len(allDirty) <= maxFiles {
		c.Files = allDirty
	}

	return c
}

func (c Context) IsEmpty() bool {
	return c.Project == "" && c.Branch == "" && c.Commit == ""
}

var issuePattern = regexp.MustCompile(`(?i)([A-Z][A-Z0-9]+-\d+)`)

func parseIssue(branch string) string {
	match := issuePattern.FindString(branch)
	return strings.ToUpper(match)
}

func mergeFileLines(lists ...string) []string {
	seen := make(map[string]struct{})
	var result []string

	for _, list := range lists {
		for _, line := range strings.Split(list, "\n") {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			if _, ok := seen[line]; !ok {
				seen[line] = struct{}{}
				result = append(result, line)
			}
		}
	}
	return result
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
