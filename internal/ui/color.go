package ui

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/igorsheg/nts/internal/note"
	"golang.org/x/term"
)

var (
	titleStyle   = lipgloss.NewStyle().Bold(true)
	dateStyle    = lipgloss.NewStyle().Faint(true)
	labelStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("6"))
	projectStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("5"))
	scoreStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("3"))
	dimStyle     = lipgloss.NewStyle().Faint(true)
	hintStyle    = lipgloss.NewStyle().Faint(true).Italic(true)
)

func IsTTY() bool {
	return term.IsTerminal(int(os.Stdout.Fd()))
}

func FormatNoteRow(n *note.Note) string {
	date := n.Date.Format("2006-01-02")
	title := n.Title
	if title == "" {
		title = "(untitled)"
	}
	labels := ""
	if len(n.Labels) > 0 {
		labels = " [" + strings.Join(n.Labels, ", ") + "]"
	}
	project := ""
	if n.Context.Project != "" {
		project = " " + n.Context.Project
	}

	if !IsTTY() {
		return fmt.Sprintf("%s  %s%s", date, title, labels)
	}

	row := dateStyle.Render(date) + "  " + titleStyle.Render(title)
	if labels != "" {
		row += " " + labelStyle.Render(labels)
	}
	if project != "" {
		row += " " + projectStyle.Render(project)
	}
	return row
}

func FormatSearchRow(n *note.Note, score int) string {
	if !IsTTY() {
		return fmt.Sprintf("%d\t%s", score, FormatNoteRow(n))
	}
	return scoreStyle.Render(fmt.Sprintf("%d", score)) + "\t" + FormatNoteRow(n)
}

func Hint(text string) string {
	if !IsTTY() {
		return ""
	}
	return hintStyle.Render(text)
}

func FormatSlug(n *note.Note) string {
	slug := strings.TrimSuffix(filepath.Base(n.Path), ".md")
	if IsTTY() {
		return dimStyle.Render(slug)
	}
	return slug
}
