package main

import "encoding/json"

// feature is a stories file: Markdown from write-user-story, with a **Ticket:** line for
// each story.
type feature struct {
	path  string // under the repo root
	title string
}

// project is what `clerk project` prints for one feature.
type project struct {
	Stories []projectStory `json:"stories"`
	Running []string       `json:"running"`
}

type projectStory struct {
	ID           string            `json:"id"`
	Title        string            `json:"title"`
	Ticket       string            `json:"ticket"`
	State        string            `json:"state"`
	Step         int               `json:"step"`
	Critical     bool              `json:"critical"`
	Unblocks     int               `json:"unblocks"`
	DependsOn    []string          `json:"depends_on"`
	BlockedBy    []string          `json:"blocked_by"`
	Dependents   []string          `json:"dependents"`
	Evidence     string            `json:"evidence"`
	Plans        []string          `json:"plans"`
	Deliverables []json.RawMessage `json:"deliverables"`

	deliverables []*deliverable
}
