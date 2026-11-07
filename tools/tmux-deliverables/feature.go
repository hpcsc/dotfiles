package main

import "encoding/json"

// feature is what `feature list` prints for each feature of a repo and, for the feature
// that is open, what `feature <path>` prints: its stories and the runs under way.
type feature struct {
	Path          string         `json:"feature"`
	Title         string         `json:"title"`
	State         string         `json:"state"`
	Evidence      string         `json:"evidence"`
	StoriesFiles  []string       `json:"stories_files"`
	StoriesTotal  int            `json:"stories_total"`
	StoriesMerged int            `json:"stories_merged"`
	GoalsTotal    int            `json:"goals_total"`
	GoalsDone     int            `json:"goals_done"`
	StoryKeys     []string       `json:"story_keys"`
	StoryTickets  []string       `json:"story_tickets"`
	Stories       []featureStory `json:"stories"`
	Running       []string       `json:"running"`
}

type featureStory struct {
	ID           string            `json:"id"`
	Key          string            `json:"key"`
	Title        string            `json:"title"`
	Ticket       string            `json:"ticket"`
	StoriesFile  string            `json:"stories_file"`
	Goals        []string          `json:"goals"`
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
	orchestrator *window
}
