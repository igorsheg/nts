package ui

import (
	"fmt"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/igorsheg/nts/internal/note"
	"github.com/sahilm/fuzzy"
)

type PickerResult struct {
	Path     string
	Canceled bool
}

func RunPicker(notes []*note.Note) (PickerResult, error) {
	m := newPickerModel(notes)
	p := tea.NewProgram(m)
	final, err := p.Run()
	if err != nil {
		return PickerResult{}, fmt.Errorf("running picker: %w", err)
	}
	fm := final.(pickerModel)
	return PickerResult{Path: fm.selected, Canceled: fm.canceled}, nil
}

const maxVisible = 10

var (
	promptStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("6"))
	cursorStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("6")).Bold(true)
	selectedStyle = lipgloss.NewStyle().Bold(true)
	matchStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("3")).Underline(true)
	slugStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("8")).Width(26)
	tagStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("8"))
	countStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("8"))
)

type pickerModel struct {
	notes    []*note.Note
	filtered []pickerItem
	input    string
	cursor   int
	offset   int
	selected string
	canceled bool
	total    int
}

type pickerItem struct {
	note           *note.Note
	matchedIndexes []int
}

type noteSource []*note.Note

func (ns noteSource) String(i int) string { return ns[i].Title }
func (ns noteSource) Len() int            { return len(ns) }

func newPickerModel(notes []*note.Note) pickerModel {
	items := make([]pickerItem, len(notes))
	for i, n := range notes {
		items[i] = pickerItem{note: n}
	}
	return pickerModel{
		notes:    notes,
		filtered: items,
		total:    len(notes),
	}
}

func (m pickerModel) Init() tea.Cmd { return nil }

func (m pickerModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "esc":
			m.canceled = true
			return m, tea.Quit
		case "enter":
			if len(m.filtered) > 0 {
				m.selected = m.filtered[m.cursor].note.Path
			}
			return m, tea.Quit
		case "up", "ctrl+p", "ctrl+k":
			if m.cursor > 0 {
				m.cursor--
				if m.cursor < m.offset {
					m.offset = m.cursor
				}
			}
		case "down", "ctrl+n", "ctrl+j":
			if m.cursor < len(m.filtered)-1 {
				m.cursor++
				if m.cursor >= m.offset+maxVisible {
					m.offset = m.cursor - maxVisible + 1
				}
			}
		case "backspace":
			if len(m.input) > 0 {
				m.input = m.input[:len(m.input)-1]
				m.applyFilter()
			}
		default:
			if len(msg.Runes) == 1 {
				m.input += string(msg.Runes)
				m.applyFilter()
			}
		}
	}
	return m, nil
}

func (m *pickerModel) applyFilter() {
	m.cursor = 0
	m.offset = 0
	if m.input == "" {
		items := make([]pickerItem, len(m.notes))
		for i, n := range m.notes {
			items[i] = pickerItem{note: n}
		}
		m.filtered = items
		return
	}
	matches := fuzzy.FindFrom(m.input, noteSource(m.notes))
	items := make([]pickerItem, len(matches))
	for i, match := range matches {
		items[i] = pickerItem{
			note:           m.notes[match.Index],
			matchedIndexes: match.MatchedIndexes,
		}
	}
	m.filtered = items
}

func (m pickerModel) View() string {
	var b strings.Builder

	b.WriteString(promptStyle.Render("> "))
	b.WriteString(m.input)
	b.WriteString("\n")

	end := m.offset + maxVisible
	if end > len(m.filtered) {
		end = len(m.filtered)
	}
	visible := m.filtered[m.offset:end]

	for i, item := range visible {
		idx := m.offset + i
		n := item.note

		cursor := "  "
		if idx == m.cursor {
			cursor = cursorStyle.Render("▸ ")
		}

		slug := strings.TrimSuffix(filepath.Base(n.Path), ".md")
		title := highlightMatches(n.Title, item.matchedIndexes)

		row := cursor + slugStyle.Render(truncate(slug, 24)) + "  " + title
		if len(n.Labels) > 0 {
			row += "  " + tagStyle.Render("["+strings.Join(n.Labels, ", ")+"]")
		}

		if idx == m.cursor {
			row = selectedStyle.Render(row)
		}
		b.WriteString(row + "\n")
	}

	b.WriteString(countStyle.Render(fmt.Sprintf("  %d/%d", len(m.filtered), m.total)))
	return b.String()
}

func highlightMatches(s string, indexes []int) string {
	if len(indexes) == 0 {
		return s
	}
	set := make(map[int]bool, len(indexes))
	for _, idx := range indexes {
		set[idx] = true
	}
	var b strings.Builder
	for i, r := range s {
		if set[i] {
			b.WriteString(matchStyle.Render(string(r)))
		} else {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max-1] + "…"
}
