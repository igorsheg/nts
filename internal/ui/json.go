package ui

import "github.com/igorsheg/nts/internal/note"

type JSONContext struct {
	Project string   `json:"project,omitempty"`
	Branch  string   `json:"branch,omitempty"`
	Issue   string   `json:"issue,omitempty"`
	RepoDir string   `json:"repo_dir,omitempty"`
	Commit  string   `json:"commit,omitempty"`
	Dirty   *bool    `json:"dirty,omitempty"`
	Files   []string `json:"files,omitempty"`
}

type JSONNote struct {
	Title   string       `json:"title"`
	Date    string       `json:"date"`
	Labels  []string     `json:"labels"`
	Path    string       `json:"path"`
	Body    string       `json:"body,omitempty"`
	Context *JSONContext  `json:"context,omitempty"`
}

func NoteToJSON(n *note.Note) JSONNote {
	j := JSONNote{
		Title:  n.Title,
		Date:   n.Date.Format("2006-01-02T15:04:05Z07:00"),
		Labels: n.Labels,
		Path:   n.Path,
		Body:   n.Body,
	}
	if !n.Context.IsEmpty() {
		j.Context = &JSONContext{
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
