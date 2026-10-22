package main

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

// The order in which the board shows what a deliverable or a window needs.
const (
	rankAnswer  = iota // an agent waits for an answer
	rankAct            // a person must act: a stopped run, a PR to open, fix or merge
	rankClose          // a merged deliverable whose window is still open
	rankBusy           // an agent or a reviewer works on it
	rankIdle           // nothing runs and nothing blocks it
	rankBlocked        // it waits on another deliverable
	rankDone           // merged, with no window
)

type pane struct {
	window string // session:index
	name   string // the name of the window
	id     string
	path   string
	// orchestrates are the plans that the session in this pane drives, from the mark that
	// the deliver-story driver puts on its pane.
	orchestrates []string
}

type agent struct {
	Pane   string `json:"pane_id"`
	Status string `json:"status"`
	Title  string `json:"title"`
}

type pullRequest struct {
	Number int    `json:"number"`
	State  string `json:"state"`
	Draft  bool   `json:"draft"`
	Review string `json:"review"`
	Checks string `json:"checks"`
	URL    string `json:"url"`
}

// plan is one story as `clerk story` prints it, with the repo it came from.
type plan struct {
	Path         string            `json:"plan"`
	Story        string            `json:"story"`
	Slug         string            `json:"story_slug"`
	Ticket       string            `json:"ticket"`
	PRError      string            `json:"pr_error"`
	Deliverables []json.RawMessage `json:"deliverables"`
	root         string
}

type need struct {
	rank int
	text string
}

type deliverable struct {
	ID        string       `json:"id"`
	State     string       `json:"state"`
	Wave      int          `json:"wave"`
	Done      int          `json:"done"`
	Total     int          `json:"total"`
	Branch    string       `json:"branch"`
	Alias     string       `json:"branch_alias"`
	Worktree  string       `json:"worktree"`
	Handle    string       `json:"handle"`
	TasksFile string       `json:"tasks_file"`
	BlockedBy []string     `json:"blocked_by"`
	Evidence  string       `json:"evidence"`
	PR        *pullRequest `json:"pr"`
	PlanPath  string       `json:"plan"`
	StorySlug string       `json:"story_slug"`
	DependsOn []string     `json:"depends_on"`
	Base      string       `json:"base"`

	raw      json.RawMessage // what deliverable-open reads
	plan     *plan
	window   *window
	need     need
	stacksOn string // the sibling whose branch this branch starts from, when the base names one
}

type story struct {
	key          string
	label        string
	title        string
	repos        []string
	plans        []*plan
	rank         int
	deliverables []*deliverable
	orchestrator *window
}

type window struct {
	target       string
	title        string
	root         string
	agent        string // waiting, working, done, or "" when no agent is in it
	pane         string // the pane to preview
	orchestrates []string
	claimed      bool
	need         need
}

type snapshot struct {
	panes  []pane
	rootOf map[string]string // pane path -> the main checkout of its repo
	plans  []*plan
	agents []agent
}

type board struct {
	stories []*story
	others  []*window
}

func newBoard(s snapshot) board {
	windows := windowsOf(s.panes, s.agents, s.rootOf)
	byKey := map[string]*story{}
	var stories []*story
	for _, p := range s.plans {
		key := strings.ToLower(firstOf(p.Ticket, p.Slug))
		st := byKey[key]
		if st == nil {
			st = &story{key: key, label: firstOf(p.Ticket, p.Slug), title: p.Story}
			byKey[key] = st
			stories = append(stories, st)
		}
		st.plans = append(st.plans, p)
		first := len(st.deliverables)
		for _, raw := range p.Deliverables {
			d := &deliverable{Wave: 1}
			if json.Unmarshal(raw, d) != nil {
				continue
			}
			d.raw, d.plan = raw, p
			d.window = windowOfWorktree(d.Worktree, s.panes, windows)
			if d.window != nil {
				d.window.claimed = true
			}
			d.need = needOf(d)
			st.deliverables = append(st.deliverables, d)
		}
		markStacks(st.deliverables[first:])
	}

	var b board
	for _, st := range stories {
		if !underWay(st) {
			continue
		}
		st.repos = reposOf(st.plans)
		st.orchestrator = orchestratorOf(st.plans, windows)
		st.rank = rankDone
		if st.orchestrator != nil {
			st.orchestrator.claimed = true
			st.rank = orchestratorNeed(st.orchestrator).rank
		}
		for _, d := range st.deliverables {
			st.rank = min(st.rank, d.need.rank)
		}
		// A story and a deliverable keep their place when their need changes, so that a person
		// finds them where they were.
		sort.SliceStable(st.deliverables, func(i, j int) bool {
			a, c := st.deliverables[i], st.deliverables[j]
			if a.Wave != c.Wave {
				return a.Wave < c.Wave
			}
			return a.ID < c.ID
		})
		b.stories = append(b.stories, st)
	}
	sort.SliceStable(b.stories, func(i, j int) bool {
		return lessKey(b.stories[i].key, b.stories[j].key)
	})

	for _, w := range windows {
		if w.agent == "" || w.claimed {
			continue
		}
		w.need = windowNeed(w)
		b.others = append(b.others, w)
	}
	sort.SliceStable(b.others, func(i, j int) bool {
		if b.others[i].need.rank != b.others[j].need.rank {
			return b.others[i].need.rank < b.others[j].need.rank
		}
		return lessTarget(b.others[i].target, b.others[j].target)
	})
	return b
}

// needsYou counts what waits on a person: an answer, or an action.
func (b board) needsYou() int {
	n := 0
	for _, st := range b.stories {
		if st.orchestrator != nil && orchestratorNeed(st.orchestrator).rank <= rankAct {
			n++
		}
		for _, d := range st.deliverables {
			if d.need.rank <= rankAct {
				n++
			}
		}
	}
	for _, w := range b.others {
		if w.need.rank <= rankAct {
			n++
		}
	}
	return n
}

// A story stays on the board while a deliverable is not merged, or a window is still open.
func underWay(st *story) bool {
	for _, d := range st.deliverables {
		if d.State != "merged" || d.window != nil {
			return true
		}
	}
	return false
}

func windowsOf(panes []pane, agents []agent, rootOf map[string]string) []*window {
	agentOf := map[string]agent{}
	for _, a := range agents {
		agentOf[a.Pane] = a
	}
	var targets []string
	panesOf := map[string][]pane{}
	for _, p := range panes {
		if _, ok := panesOf[p.window]; !ok {
			targets = append(targets, p.window)
		}
		panesOf[p.window] = append(panesOf[p.window], p)
	}

	windows := make([]*window, 0, len(targets))
	for _, target := range targets {
		w := &window{target: target, title: panesOf[target][0].name, pane: panesOf[target][0].id}
		var found []agent
		for _, p := range panesOf[target] {
			if w.root == "" {
				w.root = rootOf[p.path]
			}
			w.orchestrates = append(w.orchestrates, p.orchestrates...)
			if a, ok := agentOf[p.id]; ok {
				found = append(found, a)
			}
		}
		w.agent = stateOf(found)
		if waiting := firstWith(found, "waiting"); waiting != nil {
			w.pane = waiting.Pane
		} else if len(found) > 0 {
			w.pane = found[0].Pane
		}
		for _, a := range found {
			if t := withoutStatusMark(a.Title); t != "" {
				w.title = t
				break
			}
		}
		windows = append(windows, w)
	}
	return windows
}

// stateOf is the state of the agent that most needs a look: one that waits, then one that
// works.
func stateOf(agents []agent) string {
	switch {
	case firstWith(agents, "waiting") != nil:
		return "waiting"
	case firstWith(agents, "working") != nil:
		return "working"
	case len(agents) > 0:
		return "done"
	}
	return ""
}

func firstWith(agents []agent, status string) *agent {
	for i := range agents {
		if agents[i].Status == status {
			return &agents[i]
		}
	}
	return nil
}

// windowOfWorktree is the first window with a pane inside the worktree. A pane's path
// drifts into subfolders as a run works, so a path under the worktree counts too.
func windowOfWorktree(worktree string, panes []pane, windows []*window) *window {
	if worktree == "" {
		return nil
	}
	for _, p := range panes {
		if p.path == worktree || strings.HasPrefix(p.path, worktree+"/") {
			for _, w := range windows {
				if w.target == p.window {
					return w
				}
			}
		}
	}
	return nil
}

// markStacks notes each deliverable whose base is a sibling: its branch starts from that
// sibling's branch, and its PR targets it.
func markStacks(siblings []*deliverable) {
	for _, d := range siblings {
		for _, s := range siblings {
			if s != d && s.plan == d.plan && s.ID == d.Base {
				d.stacksOn = s.ID
			}
		}
	}
}

func needOf(d *deliverable) need {
	agent := ""
	if d.window != nil {
		agent = d.window.agent
	}
	switch {
	case agent == "waiting":
		return need{rankAnswer, "answer the agent"}
	case agent == "working":
		return need{rankBusy, "working"}
	case d.State == "merged" && d.window != nil:
		return need{rankClose, "merged: close the window"}
	case d.State == "merged":
		return need{rankDone, "done"}
	case d.State == "in-progress" || d.State == "scaffolded":
		return need{rankAct, fmt.Sprintf("the run stopped at %d/%d", d.Done, d.Total)}
	case d.State == "awaiting-merge":
		return prNeed(d.PR, d.plan.PRError)
	case d.State == "blocked":
		return need{rankBlocked, "waits on " + strings.Join(d.BlockedBy, ", ")}
	case d.State == "ready":
		return need{rankIdle, "start it"}
	}
	return need{rankDone, d.State}
}

func prNeed(pr *pullRequest, prError string) need {
	if pr == nil && prError != "" {
		return need{rankAct, "PR unknown: " + prError}
	}
	if pr == nil {
		return need{rankAct, "open a PR"}
	}
	n := fmt.Sprintf("PR #%d", pr.Number)
	switch {
	case pr.State == "merged":
		return need{rankAct, n + " merged, commits after it"}
	case pr.State == "closed":
		return need{rankAct, n + " is closed, not merged"}
	case pr.Checks == "fail":
		return need{rankAct, n + ": checks fail"}
	case pr.Review == "changes-requested":
		return need{rankAct, n + ": changes requested"}
	case pr.Draft:
		return need{rankAct, n + " is a draft: mark it ready"}
	case pr.Review == "approved":
		return need{rankAct, n + " is approved: merge it"}
	}
	return need{rankBusy, n + " is in review"}
}

func windowNeed(w *window) need {
	switch {
	case w.agent == "waiting":
		return need{rankAnswer, "answer the agent"}
	case w.agent == "working":
		return need{rankBusy, "working"}
	case len(w.orchestrates) > 0:
		return need{rankClose, "done: close the window"}
	}
	return need{rankIdle, "idle"}
}

func orchestratorNeed(w *window) need {
	switch w.agent {
	case "waiting":
		return need{rankAnswer, "answer the orchestrator"}
	case "working":
		return need{rankBusy, "the orchestrator works"}
	}
	return need{rankIdle, "the orchestrator is idle"}
}

// orchestratorOf is the first window whose mark names one of the plans.
func orchestratorOf(plans []*plan, windows []*window) *window {
	for _, w := range windows {
		for _, marked := range w.orchestrates {
			for _, p := range plans {
				if p.Path == marked {
					return w
				}
			}
		}
	}
	return nil
}

func reposOf(plans []*plan) []string {
	seen := map[string]bool{}
	var repos []string
	for _, p := range plans {
		name := filepath.Base(p.root)
		if !seen[name] {
			seen[name] = true
			repos = append(repos, name)
		}
	}
	sort.Strings(repos)
	return repos
}

// withoutStatusMark drops the mark that Claude Code puts before its title: ✳ when idle,
// and a spinner frame when it works.
func withoutStatusMark(title string) string {
	trimmed := strings.TrimLeftFunc(title, func(r rune) bool { return !unicode.IsLetter(r) && !unicode.IsDigit(r) })
	return strings.TrimSpace(trimmed)
}

// lessTarget orders session:index targets by session, then by index as a number, so
// that W:10 comes after W:9.
func lessTarget(a, b string) bool {
	as, ai, _ := strings.Cut(a, ":")
	bs, bi, _ := strings.Cut(b, ":")
	if as != bs {
		return as < bs
	}
	an, _ := strconv.Atoi(ai)
	bn, _ := strconv.Atoi(bi)
	return an < bn
}

// lessKey orders the tickets of one team by number, so that age-10 comes after age-9.
func lessKey(a, b string) bool {
	ai, bi := strings.LastIndex(a, "-"), strings.LastIndex(b, "-")
	if ai >= 0 && bi >= 0 && a[:ai] == b[:bi] {
		an, aerr := strconv.Atoi(a[ai+1:])
		bn, berr := strconv.Atoi(b[bi+1:])
		if aerr == nil && berr == nil && an != bn {
			return an < bn
		}
	}
	return a < b
}

func firstOf(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
