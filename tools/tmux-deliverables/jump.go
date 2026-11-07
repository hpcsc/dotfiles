package main

import (
	"slices"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

// storyRef names one story the same way in both views: by its ticket, or by its key when
// it has none. A key is unique only in its repo, so it comes with the repo.
type storyRef struct {
	root   string
	ticket string
	key    string
	label  string
}

func (r storyRef) holdsTicket(ticket string) bool {
	return r.ticket != "" && strings.EqualFold(r.ticket, ticket)
}

// storyRef is the story of the row under the cursor on the board.
func (m boardView) storyRef() (storyRef, bool) {
	r, ok := m.current()
	if !ok || r.story == nil {
		return storyRef{}, false
	}
	ref := storyRef{label: r.story.label, root: r.story.plans[0].root}
	if r.d != nil {
		ref.root = r.d.plan.root
	}
	for _, p := range r.story.plans {
		ref.ticket = firstOf(ref.ticket, p.Ticket)
		if p.root == ref.root {
			ref.key = firstOf(ref.key, p.StoryID)
		}
	}
	return ref, true
}

// find puts the cursor on the story on the board, once the board has read the stories.
func (m boardView) find(ref storyRef) boardView {
	m.want = &ref
	if !m.loading {
		m.applyWant()
	}
	return m
}

func (m *boardView) applyWant() {
	ref := m.want
	m.want = nil
	for _, r := range m.rows {
		if r.kind != storyRow {
			continue
		}
		for _, p := range r.story.plans {
			if ref.holdsTicket(p.Ticket) || (ref.key != "" && p.StoryID == ref.key && p.root == ref.root) {
				m.selectKey(r.key())
				return
			}
		}
	}
	m.message = ref.label + " is not under way"
}

// storyRef is the story of the row under the cursor in the planner, in the repo it reads.
func (v plannerView) storyRef() (storyRef, bool) {
	r, ok := v.current()
	if v.screen != storyScreen || !ok {
		return storyRef{}, false
	}
	return storyRef{root: v.root, ticket: r.story.Ticket, key: r.story.Key, label: r.story.ID}, true
}

// find opens the feature that holds the story, in the repo of the story, with the cursor
// on it. The planner then reads that repo.
func (v plannerView) find(ref storyRef) (plannerView, tea.Cmd) {
	v.root, v.want = ref.root, &ref
	v.screen, v.message = featureScreen, "finding "+ref.label+"…"
	return v, listFeatures(v.run, v.root)
}

func (v plannerView) featureOf(ref storyRef) (feature, bool) {
	for _, f := range v.features {
		if slices.ContainsFunc(f.StoryTickets, ref.holdsTicket) || (ref.key != "" && slices.Contains(f.StoryKeys, ref.key)) {
			return f, true
		}
	}
	return feature{}, false
}

func (v *plannerView) selectWant() {
	ref := v.want
	v.want = nil
	for _, st := range v.stories {
		if ref.holdsTicket(st.Ticket) || st.Key == ref.key {
			v.selectKey("story " + st.Key)
			return
		}
	}
	v.message = "the feature does not hold " + ref.label
}
