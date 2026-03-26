package ui

import (
	"encoding/json"
	"fmt"
	"os"
	"time"
)

type Envelope struct {
	OK          bool          `json:"ok"`
	Command     string        `json:"command"`
	Timestamp   int64         `json:"timestamp"`
	Result      interface{}   `json:"result,omitempty"`
	Error       *EnvError     `json:"error,omitempty"`
	Fix         string        `json:"fix,omitempty"`
	NextActions []NextAction  `json:"next_actions"`
}

type EnvError struct {
	Message   string `json:"message"`
	Code      string `json:"code"`
	Retryable bool   `json:"retryable"`
}

type NextAction struct {
	Command     string              `json:"command"`
	Description string              `json:"description"`
	Params      map[string]Param    `json:"params,omitempty"`
}

type Param struct {
	Description string   `json:"description,omitempty"`
	Value       string   `json:"value,omitempty"`
	Default     string   `json:"default,omitempty"`
	Enum        []string `json:"enum,omitempty"`
	Required    bool     `json:"required,omitempty"`
}

func Success(command string, result interface{}, actions []NextAction) Envelope {
	return Envelope{
		OK:          true,
		Command:     command,
		Timestamp:   time.Now().Unix(),
		Result:      result,
		NextActions: actions,
	}
}

func Failure(command string, code string, message string, fix string, actions []NextAction) Envelope {
	return Envelope{
		OK:        false,
		Command:   command,
		Timestamp: time.Now().Unix(),
		Error: &EnvError{
			Message:   message,
			Code:      code,
			Retryable: false,
		},
		Fix:         fix,
		NextActions: actions,
	}
}

func PrintEnvelope(env Envelope) error {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(env)
}

func FailureRetryable(command string, code string, message string, fix string, actions []NextAction) Envelope {
	env := Failure(command, code, message, fix, actions)
	env.Error.Retryable = true
	return env
}

type CommandInfo struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Usage       string `json:"usage"`
}

func CommandTree(version string, commands []CommandInfo) Envelope {
	return Success("nts", map[string]interface{}{
		"description": "Note to self — quick markdown notes from your terminal",
		"version":     version,
		"commands":    commands,
	}, []NextAction{
		{Command: "nts <title>", Description: "Create a new note", Params: map[string]Param{
			"title": {Required: true, Description: "Note title"},
		}},
		{Command: "nts list", Description: "List all notes"},
		{Command: "nts search <query>", Description: "Search notes", Params: map[string]Param{
			"query": {Required: true, Description: "Search query"},
		}},
	})
}

func NoteActions(slug string) []NextAction {
	return []NextAction{
		{Command: fmt.Sprintf("nts show %s", slug), Description: "Show this note"},
		{Command: fmt.Sprintf("nts edit %s", slug), Description: "Edit this note"},
		{Command: fmt.Sprintf("nts append %s <text>", slug), Description: "Append to this note", Params: map[string]Param{
			"text": {Required: true, Description: "Text to append"},
		}},
	}
}

func ListActions() []NextAction {
	return []NextAction{
		{Command: "nts show <slug>", Description: "Show a note", Params: map[string]Param{
			"slug": {Required: true, Description: "Note slug"},
		}},
		{Command: "nts search <query>", Description: "Search notes", Params: map[string]Param{
			"query": {Required: true, Description: "Search query"},
		}},
		{Command: "nts list [--labels <labels>] [--project <project>]", Description: "Filter notes", Params: map[string]Param{
			"labels":  {Description: "Comma-separated labels"},
			"project": {Description: "Project name"},
		}},
	}
}

func SearchActions(query string) []NextAction {
	return []NextAction{
		{Command: "nts show <slug>", Description: "Show a result", Params: map[string]Param{
			"slug": {Required: true, Description: "Note slug"},
		}},
		{Command: fmt.Sprintf("nts search %q [--labels <labels>]", query), Description: "Refine search", Params: map[string]Param{
			"labels": {Description: "Filter by labels"},
		}},
	}
}
