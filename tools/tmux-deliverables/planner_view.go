package main

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"sort"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
)

type plannerScreen int

const (
	featureScreen plannerScreen = iota
	storyScreen
)

type plannerRow struct {
	story *projectStory
	d     *deliverable // nil on the row of the story
}

func (r plannerRow) key() string {
	if r.d != nil {
		return "deliverable " + r.d.PlanPath + " " + r.d.ID
	}
	return "story " + r.story.ID
}

type featuresMsg struct{ features []feature }

type projectMsg struct {
	p   project
	err error
}

// plannerView is the stories of one feature, in the order `clerk project` gives, with the
// deliverables of each story under it. It is where a story is planned, approved and
// started; the board view is where the work under way is followed.
type plannerView struct {
	run    runner
	client string
	root   string
	limit  int // the runs at the same time that a person wants, shown beside the runs under way
	tick   func() tea.Cmd
	now    func() time.Time

	screen        plannerScreen
	features      []feature
	featureCursor int
	feature       feature

	data    project
	panes   []pane
	rootOf  map[string]string
	agents  []agent
	stories []*projectStory

	folded map[string]bool
	rows   []plannerRow
	cursor int
	offset int

	graph         bool
	width, height int
	message       string
	loading       bool
	loadedAt      time.Time
	preview       previewMsg
}

func newPlannerView(run runner, client, root string, limit int) plannerView {
	return plannerView{
		run:    run,
		client: client,
		root:   root,
		limit:  limit,
		tick:   func() tea.Cmd { return tea.Tick(windowsEvery, func(time.Time) tea.Msg { return tickMsg{} }) },
		now:    time.Now,
		folded: map[string]bool{},
		width:  120,
		height: 40,
	}
}

func (v plannerView) Init() tea.Cmd {
	run, root := v.run, v.root
	return tea.Batch(func() tea.Msg { return featuresMsg{run.features(root)} }, v.tick())
}

func (v plannerView) load() tea.Cmd {
	run, root, path := v.run, v.root, v.feature.path
	return func() tea.Msg {
		p, err := run.project(root, path)
		return projectMsg{p, err}
	}
}

func (v plannerView) readWindows() tea.Cmd {
	run := v.run
	return func() tea.Msg {
		panes, rootOf, agents := run.windows()
		return windowsMsg{panes, rootOf, agents}
	}
}

func (v plannerView) Update(msg tea.Msg) (plannerView, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		v.width, v.height = msg.Width, msg.Height
	case featuresMsg:
		v.features = msg.features
		switch len(v.features) {
		case 0:
			v.message = "no stories file with **Ticket:** lines under .scratches/write-user-story or user-stories"
		case 1:
			return v.open(v.features[0])
		}
		return v, v.readPreview()
	case projectMsg:
		v.loading, v.loadedAt = false, v.now()
		if msg.err != nil {
			v.message = "clerk project: " + msg.err.Error()
			return v, nil
		}
		v.data = msg.p
		v.rebuild()
		return v, v.readPreview()
	case windowsMsg:
		v.panes, v.rootOf, v.agents = msg.panes, msg.rootOf, msg.agents
		v.rebuild()
		return v, v.readPreview()
	case tickMsg:
		cmds := []tea.Cmd{v.tick()}
		if v.screen == storyScreen {
			cmds = append(cmds, v.readWindows())
			if !v.loading && v.now().Sub(v.loadedAt) >= storiesEvery {
				v.loading = true
				cmds = append(cmds, v.load())
			}
		}
		return v, tea.Batch(cmds...)
	case previewMsg:
		v.preview = msg
	case doneMsg:
		if msg.quit {
			return v, tea.Quit
		}
		v.message = msg.text
		if msg.reload && v.screen == storyScreen {
			v.loading = true
			return v, v.load()
		}
	case tea.KeyMsg:
		return v.key(msg)
	}
	return v, nil
}

func (v plannerView) open(f feature) (plannerView, tea.Cmd) {
	v.screen, v.feature, v.loading = storyScreen, f, true
	v.data, v.rows, v.cursor, v.offset, v.message = project{}, nil, 0, 0, ""
	return v, tea.Batch(v.load(), v.readWindows())
}

func (v plannerView) key(msg tea.KeyMsg) (plannerView, tea.Cmd) {
	v.message = ""
	if v.screen == featureScreen {
		return v.featureKey(msg)
	}
	switch msg.String() {
	case "q", "esc", "ctrl+c":
		return v, tea.Quit
	case "up", "k":
		return v.move(-1)
	case "down", "j":
		return v.move(1)
	case "pgup":
		return v.move(-listHeightOf(v.height))
	case "pgdown":
		return v.move(listHeightOf(v.height))
	case "left", "h":
		return v.fold(true)
	case "right", "l":
		return v.fold(false)
	case "enter":
		r, ok := v.current()
		switch {
		case !ok:
		case r.d != nil:
			return v, goTo(v.run, v.client, r.d)
		case r.story.orchestrator != nil:
			return v, switchTo(v.run, v.client, r.story.orchestrator.target)
		default:
			v.folded[r.story.ID] = !v.isFolded(r.story)
			v.rebuild()
		}
		return v, nil
	case "n":
		if r, ok := v.current(); ok {
			return v.nextStep(r.story)
		}
	case "s", "g":
		return v.start(msg.String() == "g")
	case "t":
		v.graph = !v.graph
		return v, v.readPreview()
	case "b", "backspace":
		if len(v.features) > 1 {
			v.screen = featureScreen
			return v, v.readPreview()
		}
		v.message = "this repo has one feature"
	case "r":
		v.loading = true
		return v, v.load()
	}
	return v, nil
}

func (v plannerView) featureKey(msg tea.KeyMsg) (plannerView, tea.Cmd) {
	switch msg.String() {
	case "q", "esc", "ctrl+c":
		return v, tea.Quit
	case "up", "k":
		v.featureCursor = max(0, v.featureCursor-1)
		return v, v.readPreview()
	case "down", "j":
		v.featureCursor = max(0, min(len(v.features)-1, v.featureCursor+1))
		return v, v.readPreview()
	case "enter":
		if v.featureCursor < len(v.features) {
			return v.open(v.features[v.featureCursor])
		}
	case "p":
		if v.featureCursor < len(v.features) {
			f := v.features[v.featureCursor]
			name := "deliver-" + strings.TrimSuffix(filepath.Base(f.path), ".md")
			return v, v.claude(name, "/deliver-project "+filepath.Join(v.root, f.path))
		}
	case "r":
		run, root := v.run, v.root
		return v, func() tea.Msg { return featuresMsg{run.features(root)} }
	}
	return v, nil
}

func (v plannerView) current() (plannerRow, bool) {
	if v.cursor < 0 || v.cursor >= len(v.rows) {
		return plannerRow{}, false
	}
	return v.rows[v.cursor], true
}

func (v plannerView) move(by int) (plannerView, tea.Cmd) {
	v.cursor = max(0, min(len(v.rows)-1, v.cursor+by))
	v.offset = scrolled(v.cursor, v.offset, len(v.rows), listHeightOf(v.height))
	return v, v.readPreview()
}

func (v plannerView) fold(fold bool) (plannerView, tea.Cmd) {
	r, ok := v.current()
	if !ok {
		return v, nil
	}
	v.folded[r.story.ID] = fold
	v.rebuild()
	if fold {
		v.selectKey("story " + r.story.ID)
	}
	return v, v.readPreview()
}

// nextStep is what the state of a story calls for: a window that plans it, a window that
// takes its plan through the gate (its orchestrator, when it has one), or a start of its
// ready deliverables.
func (v plannerView) nextStep(st *projectStory) (plannerView, tea.Cmd) {
	slug := strings.ToLower(st.Ticket)
	switch st.State {
	case "ready":
		return v, v.claude(slug+"-plan", fmt.Sprintf(
			"/deliver-story %s: deliver story %s of %s. Read its section, from its ### heading to the next heading, as the story.",
			st.Ticket, st.ID, filepath.Join(v.root, v.feature.path)))
	case "planned":
		if st.orchestrator != nil {
			return v, switchTo(v.run, v.client, st.orchestrator.target)
		}
		if len(st.Plans) > 0 {
			return v, v.claude(slug+"-gate", "/deliver-story "+st.Plans[0])
		}
	case "approved", "in-progress":
		var ready []*deliverable
		for _, d := range st.deliverables {
			if d.State == "ready" {
				ready = append(ready, d)
			}
		}
		if len(ready) == 0 {
			v.message = st.ID + " has no ready deliverable"
			return v, nil
		}
		run := v.run
		return v, func() tea.Msg {
			var said []string
			for _, d := range ready {
				text, err := run.start(d, false)
				if err != nil {
					text = err.Error()
				}
				said = append(said, text)
			}
			return doneMsg{text: strings.Join(said, "; "), reload: true}
		}
	}
	v.message = fmt.Sprintf("%s is %s: no next step here", st.ID, st.State)
	return v, nil
}

func (v plannerView) start(gears bool) (plannerView, tea.Cmd) {
	r, ok := v.current()
	if !ok || r.d == nil {
		v.message = "pick a deliverable to start"
		return v, nil
	}
	run, d := v.run, r.d
	return v, func() tea.Msg {
		text, err := run.start(d, gears)
		if err != nil {
			return doneMsg{text: err.Error()}
		}
		return doneMsg{text: text, reload: true}
	}
}

// claude opens a window with Claude on a prompt, goes to it, and closes the popup.
func (v plannerView) claude(name, prompt string) tea.Cmd {
	run, client, root := v.run, v.client, v.root
	return func() tea.Msg {
		target, err := run.claudeWindow(client, root, name, prompt)
		if err != nil {
			return doneMsg{text: "could not open " + name + ": " + err.Error()}
		}
		return switchTo(run, client, target)()
	}
}

func (v *plannerView) rebuild() {
	keep := ""
	if r, ok := v.current(); ok {
		keep = r.key()
	}
	windows := windowsOf(v.panes, v.agents, v.rootOf)
	plans := map[string]*plan{}
	v.stories = nil
	for i := range v.data.Stories {
		st := &v.data.Stories[i]
		st.deliverables = nil
		var stPlans []*plan
		for _, path := range st.Plans {
			stPlans = append(stPlans, &plan{Path: path})
		}
		st.orchestrator = orchestratorOf(stPlans, windows)
		for _, raw := range st.Deliverables {
			d := &deliverable{Wave: 1}
			if json.Unmarshal(raw, d) != nil {
				continue
			}
			if plans[d.PlanPath] == nil {
				plans[d.PlanPath] = &plan{Path: d.PlanPath, Slug: d.StorySlug, root: v.root}
			}
			d.raw, d.plan = raw, plans[d.PlanPath]
			d.window = windowOfWorktree(d.Worktree, v.panes, windows)
			d.need = needOf(d)
			st.deliverables = append(st.deliverables, d)
		}
		v.stories = append(v.stories, st)
	}
	v.rows = nil
	for _, st := range v.stories {
		v.rows = append(v.rows, plannerRow{story: st})
		if v.isFolded(st) {
			continue
		}
		for _, d := range st.deliverables {
			v.rows = append(v.rows, plannerRow{story: st, d: d})
		}
	}
	if keep == "" || !v.selectKey(keep) {
		v.cursor = max(0, min(len(v.rows)-1, v.cursor))
	}
	v.offset = scrolled(v.cursor, v.offset, len(v.rows), listHeightOf(v.height))
}

func (v *plannerView) selectKey(key string) bool {
	for i, r := range v.rows {
		if r.key() == key {
			v.cursor = i
			v.offset = scrolled(v.cursor, v.offset, len(v.rows), listHeightOf(v.height))
			return true
		}
	}
	return false
}

// isFolded is what the person chose, else folded when the story has no deliverable to
// show or every one of them is merged.
func (v plannerView) isFolded(st *projectStory) bool {
	if folded, ok := v.folded[st.ID]; ok {
		return folded
	}
	return len(st.deliverables) == 0 || st.State == "merged"
}

func (v plannerView) currentKey() string {
	if v.screen == featureScreen {
		if v.featureCursor < len(v.features) {
			return "feature " + filepath.Join(v.root, v.features[v.featureCursor].path)
		}
		return ""
	}
	if r, ok := v.current(); ok {
		return r.key()
	}
	return ""
}

func (v plannerView) readPreview() tea.Cmd {
	lines, run := previewHeightOf(v.height), v.run
	if v.screen == featureScreen {
		if v.featureCursor >= len(v.features) {
			return nil
		}
		path := filepath.Join(v.root, v.features[v.featureCursor].path)
		key := "feature " + path
		return func() tea.Msg { return previewMsg{key, run.readFile(path, lines)} }
	}
	r, ok := v.current()
	if !ok {
		return nil
	}
	if r.d != nil {
		return previewOf(run, r.key(), r.d, lines)
	}
	text := v.storyText(r.story)
	if v.graph {
		text = v.graphText()
	}
	key := r.key()
	return func() tea.Msg { return previewMsg{key, text} }
}

func (v plannerView) storyText(st *projectStory) string {
	critical := ""
	if st.Critical {
		critical = "  critical path"
	}
	lines := []string{
		fmt.Sprintf("%s  %s  %s  step %d%s", st.ID, st.Ticket, st.State, st.Step, critical),
		st.Title,
		"",
		"waits on:      " + v.statesOf(st.DependsOn),
		"waited on by:  " + v.statesOf(st.Dependents),
		fmt.Sprintf("unblocks:      %d stories in all", st.Unblocks),
		"evidence:      " + st.Evidence,
	}
	if len(st.deliverables) > 0 {
		lines = append(lines, "", "deliverables:")
		for _, d := range st.deliverables {
			lines = append(lines, fmt.Sprintf("  %s %-15sw%d  %d/%d  %s", mark(d.State), d.State, d.Wave, d.Done, d.Total, d.ID))
		}
	}
	if len(st.Plans) > 0 {
		lines = append(lines, "", "plans:")
		for _, p := range st.Plans {
			lines = append(lines, "  "+p)
		}
	}
	return strings.Join(lines, "\n")
}

func (v plannerView) statesOf(ids []string) string {
	var parts []string
	for _, id := range ids {
		for _, st := range v.stories {
			if st.ID == id {
				parts = append(parts, id+" "+st.State)
			}
		}
	}
	return firstOf(strings.Join(parts, ", "), "nothing")
}

// graphText is the feature by step, with the critical path marked.
func (v plannerView) graphText() string {
	stories := append([]*projectStory(nil), v.stories...)
	sort.SliceStable(stories, func(i, j int) bool { return stories[i].Step < stories[j].Step })
	var lines []string
	longest := 0
	for i, st := range stories {
		label := ""
		if i == 0 || stories[i-1].Step != st.Step {
			label = fmt.Sprintf("step %d", st.Step)
		}
		marker := "  "
		if st.Critical {
			marker = "* "
		}
		line := cell(label, 8) + marker + cell(st.ID, 8) + cell(st.State, 15)
		if len(st.DependsOn) > 0 {
			line += "<- " + strings.Join(st.DependsOn, ", ")
		}
		lines = append(lines, strings.TrimRight(line, " "))
		longest = max(longest, st.Step)
	}
	return strings.Join(append(lines, "", fmt.Sprintf("* critical path: %d steps · t: back to the story", longest)), "\n")
}

var stateStyle = map[string]lipgloss.Style{
	"merged":         lipgloss.NewStyle().Foreground(lipgloss.Color("2")),
	"awaiting-merge": lipgloss.NewStyle().Foreground(lipgloss.Color("6")),
	"in-progress":    lipgloss.NewStyle().Foreground(lipgloss.Color("3")),
	"scaffolded":     lipgloss.NewStyle().Foreground(lipgloss.Color("3")),
	"approved":       lipgloss.NewStyle().Foreground(lipgloss.Color("4")),
	"planned":        lipgloss.NewStyle().Foreground(lipgloss.Color("5")),
	"ready":          bold,
	"blocked":        dimmed,
}

func storyLine(st *projectStory) string {
	state := cell(st.State, 15)
	if s, ok := stateStyle[st.State]; ok {
		state = s.Render(state)
	}
	text := state + cell(st.ID, 8) + cell(st.Ticket, 10) + cell(fmt.Sprintf("↑%d", st.Unblocks), 5) + st.Title
	if len(st.BlockedBy) > 0 {
		text += "  " + dimmed.Render("[blocked by "+strings.Join(st.BlockedBy, ", ")+"]")
	}
	return text + orchestratorNote(st.orchestrator)
}

func (v plannerView) View() string {
	var b strings.Builder
	header := bold.Render("deliver · pick a feature")
	if v.screen == storyScreen {
		header = bold.Render("deliver · "+v.feature.title) +
			dimmed.Render(fmt.Sprintf(" · runs %d (limit %d)", len(v.data.Running), v.limit))
		if v.loading {
			header += dimmed.Render(" · reading the stories…")
		}
	}
	if v.message != "" {
		header += " · " + v.message
	}
	b.WriteString(ansi.Truncate(header, v.width, "…") + "\n")

	h := listHeightOf(v.height)
	var lines []string
	cursor, offset := v.cursor, v.offset
	if v.screen == featureScreen {
		for _, f := range v.features {
			lines = append(lines, f.title+"  "+dimmed.Render(f.path))
		}
		cursor, offset = v.featureCursor, scrolled(v.featureCursor, 0, len(v.features), h)
	} else {
		for _, r := range v.rows {
			if r.d != nil {
				lines = append(lines, deliverableLine(r.d, false))
			} else {
				lines = append(lines, storyLine(r.story))
			}
		}
	}
	for i := offset; i < offset+h; i++ {
		if i < len(lines) {
			gutter := "  "
			if i == cursor {
				gutter = selected.Render("▌ ")
			}
			b.WriteString(ansi.Truncate(gutter+lines[i], v.width, "…"))
		}
		b.WriteString("\n")
	}
	b.WriteString(dimmed.Render(strings.Repeat("─", max(0, v.width))) + "\n")

	preview := ""
	if v.preview.key == v.currentKey() {
		preview = v.preview.text
	}
	previewLines := strings.Split(preview, "\n")
	for i := 0; i < previewHeightOf(v.height); i++ {
		if i < len(previewLines) {
			b.WriteString(ansi.Truncate(previewLines[i], v.width, "…"))
		}
		b.WriteString("\n")
	}

	keys := "enter go, start, or go to the orchestrator · n next step · s start · g start with gears · t graph · b features · tab under way · r reload · q quit"
	if v.screen == featureScreen {
		keys = "enter open · p /deliver-project in a window · tab under way · r reload · q quit"
	}
	b.WriteString(dimmed.Render(ansi.Truncate(keys, v.width, "…")))
	return b.String()
}
