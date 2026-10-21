package main

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/cursor"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
)

const (
	windowsEvery = 3 * time.Second
	storiesEvery = time.Minute
)

type rowKind int

const (
	storyRow rowKind = iota
	deliverableRow
	mergedRow // the merged deliverables of a story that have no window, in one row
	othersRow // the heading over the windows that hold no deliverable
	windowRow
)

type row struct {
	kind   rowKind
	story  *story
	d      *deliverable
	w      *window
	merged []*deliverable
}

func (r row) key() string {
	switch r.kind {
	case storyRow:
		return "story " + r.story.key
	case deliverableRow:
		return "deliverable " + r.d.plan.Path + " " + r.d.ID
	case mergedRow:
		return "merged " + r.story.key
	case windowRow:
		return "window " + r.w.target
	}
	return "others"
}

// question waits for y before it runs a change.
type question struct {
	text string
	yes  tea.Cmd
}

type loadedMsg struct{ s snapshot }

type windowsMsg struct {
	panes  []pane
	rootOf map[string]string
	agents []agent
}

type tickMsg struct{}

type previewMsg struct{ key, text string }

// doneMsg reports an action. `quit` closes the popup, after a switch to a window.
type doneMsg struct {
	text   string
	quit   bool
	reload bool
}

type boardView struct {
	run    runner
	client string
	tick   func() tea.Cmd
	now    func() time.Time

	plans  []*plan
	panes  []pane
	rootOf map[string]string
	agents []agent
	board  board

	folded map[string]bool // what the person folded or opened; other stories take a default
	// showPane makes the preview of a story heading the pane of its orchestrator, not the
	// graph of its deliverables.
	showPane bool
	rows     []row
	cursor   int
	offset   int

	width, height int
	filter        textinput.Model
	filtering     bool
	ask           *question
	message       string
	loading       bool
	loadedAt      time.Time
	preview       previewMsg
}

func newBoardView(run runner, client string) boardView {
	filter := textinput.New()
	filter.Prompt = "/ "
	filter.Cursor.SetMode(cursor.CursorStatic)
	return boardView{
		run:     run,
		client:  client,
		tick:    func() tea.Cmd { return tea.Tick(windowsEvery, func(time.Time) tea.Msg { return tickMsg{} }) },
		now:     time.Now,
		folded:  map[string]bool{},
		filter:  filter,
		loading: true,
		width:   120,
		height:  40,
	}
}

func (m boardView) Init() tea.Cmd {
	return tea.Batch(m.load(), m.tick())
}

func (m boardView) load() tea.Cmd {
	run := m.run
	return func() tea.Msg {
		s, _ := run.snapshot()
		return loadedMsg{s}
	}
}

func (m boardView) readWindows() tea.Cmd {
	run := m.run
	return func() tea.Msg {
		panes, rootOf, agents := run.windows()
		return windowsMsg{panes, rootOf, agents}
	}
}

func (m boardView) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		return m, nil
	case loadedMsg:
		m.plans, m.panes, m.rootOf, m.agents = msg.s.plans, msg.s.panes, msg.s.rootOf, msg.s.agents
		m.loading, m.loadedAt = false, m.now()
		m.rebuild()
		return m, m.readPreview()
	case windowsMsg:
		m.panes, m.rootOf, m.agents = msg.panes, msg.rootOf, msg.agents
		m.rebuild()
		return m, m.readPreview()
	case tickMsg:
		cmds := []tea.Cmd{m.readWindows(), m.tick()}
		if !m.loading && m.now().Sub(m.loadedAt) >= storiesEvery {
			m.loading = true
			cmds = append(cmds, m.load())
		}
		return m, tea.Batch(cmds...)
	case previewMsg:
		m.preview = msg
		return m, nil
	case doneMsg:
		if msg.quit {
			return m, tea.Quit
		}
		m.message = msg.text
		if msg.reload {
			m.loading = true
			return m, m.load()
		}
		return m, nil
	case tea.KeyMsg:
		return m.key(msg)
	}
	return m, nil
}

func (m boardView) key(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if m.ask != nil {
		yes := m.ask.yes
		m.ask = nil
		if msg.String() == "y" {
			return m, yes
		}
		m.message = "nothing changed"
		return m, nil
	}
	if m.filtering {
		switch msg.String() {
		case "enter":
			m.filtering = false
			m.filter.Blur()
		case "esc":
			m.filtering = false
			m.filter.Blur()
			m.filter.SetValue("")
			m.rebuild()
		default:
			var cmd tea.Cmd
			m.filter, cmd = m.filter.Update(msg)
			m.cursor = 0
			m.rebuild()
			return m, cmd
		}
		return m, nil
	}

	m.message = ""
	switch msg.String() {
	case "q", "esc", "ctrl+c":
		return m, tea.Quit
	case "up", "k":
		return m.move(-1)
	case "down", "j":
		return m.move(1)
	case "pgup":
		return m.move(-m.listHeight())
	case "pgdown":
		return m.move(m.listHeight())
	case "left", "h":
		return m.fold(true)
	case "right", "l":
		return m.fold(false)
	case "enter":
		return m.enter()
	case "o":
		return m.openPR()
	case "x":
		return m.askClose()
	case "a":
		return m.askArchive()
	case "t":
		m.showPane = !m.showPane
		if r, ok := m.current(); ok && r.kind == storyRow && r.story.orchestrator == nil {
			m.message = r.story.label + " has no orchestrator"
		}
		return m, m.readPreview()
	case "r":
		m.loading = true
		return m, m.load()
	case "/":
		m.filtering = true
		cmd := m.filter.Focus()
		return m, cmd
	}
	return m, nil
}

func (m boardView) current() (row, bool) {
	if m.cursor < 0 || m.cursor >= len(m.rows) {
		return row{}, false
	}
	return m.rows[m.cursor], true
}

func (m boardView) move(by int) (tea.Model, tea.Cmd) {
	m.cursor = max(0, min(len(m.rows)-1, m.cursor+by))
	m.scroll()
	return m, m.readPreview()
}

func (m boardView) fold(fold bool) (tea.Model, tea.Cmd) {
	r, ok := m.current()
	if !ok || r.story == nil {
		return m, nil
	}
	m.folded[r.story.key] = fold
	m.rebuild()
	if fold {
		m.selectKey("story " + r.story.key)
	}
	return m, m.readPreview()
}

func (m boardView) enter() (tea.Model, tea.Cmd) {
	r, ok := m.current()
	if !ok {
		return m, nil
	}
	switch {
	case r.kind == storyRow && r.story.orchestrator != nil:
		return m, switchTo(m.run, m.client, r.story.orchestrator.target)
	case r.kind == storyRow:
		m.folded[r.story.key] = !m.isFolded(r.story)
		m.rebuild()
		return m, nil
	case r.kind == windowRow:
		return m, switchTo(m.run, m.client, r.w.target)
	case r.kind == deliverableRow:
		return m, goTo(m.run, m.client, r.d)
	}
	return m, nil
}

// goTo goes to the window of the deliverable, or opens or starts it through
// deliverable-open when it has none. Both close the popup.
func goTo(run runner, client string, d *deliverable) tea.Cmd {
	if d.window != nil {
		return switchTo(run, client, d.window.target)
	}
	return func() tea.Msg {
		text, err := run.open(client, d)
		if err != nil {
			return doneMsg{text: err.Error()}
		}
		return doneMsg{text: text, quit: true}
	}
}

func switchTo(run runner, client, target string) tea.Cmd {
	return func() tea.Msg {
		if err := run.switchTo(client, target); err != nil {
			return doneMsg{text: "could not go to " + target + ": " + err.Error()}
		}
		return doneMsg{quit: true}
	}
}

func (m boardView) openPR() (tea.Model, tea.Cmd) {
	r, ok := m.current()
	if !ok || r.kind != deliverableRow || r.d.PR == nil || r.d.PR.URL == "" {
		m.message = "no PR to open"
		return m, nil
	}
	run, url := m.run, r.d.PR.URL
	return m, func() tea.Msg {
		if err := run.openURL(url); err != nil {
			return doneMsg{text: "could not open " + url + ": " + err.Error()}
		}
		return doneMsg{text: "opened " + url}
	}
}

func (m boardView) askClose() (tea.Model, tea.Cmd) {
	r, ok := m.current()
	switch {
	case !ok || r.kind != deliverableRow:
		m.message = "pick a merged deliverable to close its window"
		return m, nil
	case r.d.window == nil:
		m.message = r.d.ID + " has no window"
		return m, nil
	case r.d.State != "merged":
		m.message = r.d.ID + " is not merged"
		return m, nil
	case r.d.window.agent == "working" || r.d.window.agent == "waiting":
		m.message = fmt.Sprintf("the agent in %s is %s: it keeps its window", r.d.window.target, r.d.window.agent)
		return m, nil
	}
	run, d := m.run, r.d
	m.ask = &question{
		text: fmt.Sprintf("Close %s, the window of %s? The worktree and the branch stay.", d.window.target, d.ID),
		yes: func() tea.Msg {
			if err := run.closeWindow(d.plan.root, d.Handle); err != nil {
				return doneMsg{text: "could not close " + d.window.target + ": " + err.Error()}
			}
			return doneMsg{text: "closed " + d.window.target, reload: true}
		},
	}
	return m, nil
}

func (m boardView) askArchive() (tea.Model, tea.Cmd) {
	r, ok := m.current()
	if !ok || r.story == nil {
		m.message = "pick a story to archive"
		return m, nil
	}
	st := r.story
	var open []string
	for _, d := range st.deliverables {
		if d.State != "merged" {
			open = append(open, d.ID+" ("+d.State+")")
		}
	}
	text := fmt.Sprintf("Archive %s? Its folder moves to tasks/completed/.", st.label)
	if len(open) > 0 {
		text = fmt.Sprintf("Archive %s? %s not merged: %s. Its folder moves to tasks/completed/ all the same.",
			st.label, count(len(open), "deliverable is", "deliverables are"), strings.Join(open, ", "))
	}
	run, force, plans := m.run, len(open) > 0, st.plans
	m.ask = &question{
		text: text,
		yes: func() tea.Msg {
			for _, p := range plans {
				if err := run.archive(p.root, p.Path, force); err != nil {
					return doneMsg{text: "could not archive " + st.label + ": " + err.Error(), reload: true}
				}
			}
			return doneMsg{text: "archived " + st.label, reload: true}
		},
	}
	return m, nil
}

// rebuild makes the board and its rows again, and keeps the cursor on the same row.
func (m *boardView) rebuild() {
	keep := ""
	if r, ok := m.current(); ok {
		keep = r.key()
	}
	m.board = newBoard(snapshot{panes: m.panes, rootOf: m.rootOf, plans: m.plans, agents: m.agents})
	m.rows = m.rowsOf(m.board)
	if keep == "" || !m.selectKey(keep) {
		m.cursor = max(0, min(len(m.rows)-1, m.cursor))
	}
	m.scroll()
}

func (m *boardView) selectKey(key string) bool {
	for i, r := range m.rows {
		if r.key() == key {
			m.cursor = i
			m.scroll()
			return true
		}
	}
	return false
}

// isFolded is what the person chose, else folded when nothing in the story needs a look.
func (m boardView) isFolded(st *story) bool {
	if folded, ok := m.folded[st.key]; ok {
		return folded
	}
	return st.rank >= rankIdle
}

func (m boardView) rowsOf(b board) []row {
	term := strings.ToLower(strings.TrimSpace(m.filter.Value()))
	var rows []row
	for _, st := range b.stories {
		if term != "" && !storyMatches(st, term) {
			continue
		}
		rows = append(rows, row{kind: storyRow, story: st})
		if term == "" && m.isFolded(st) {
			continue
		}
		var merged []*deliverable
		for _, d := range st.deliverables {
			if d.State == "merged" && d.window == nil {
				merged = append(merged, d)
				continue
			}
			rows = append(rows, row{kind: deliverableRow, story: st, d: d})
		}
		switch len(merged) {
		case 0:
		case 1:
			rows = append(rows, row{kind: deliverableRow, story: st, d: merged[0]})
		default:
			rows = append(rows, row{kind: mergedRow, story: st, merged: merged})
		}
	}
	var others []row
	for _, w := range b.others {
		if term == "" || strings.Contains(strings.ToLower(w.title+" "+w.target), term) {
			others = append(others, row{kind: windowRow, w: w})
		}
	}
	if len(others) > 0 {
		rows = append(rows, row{kind: othersRow})
		rows = append(rows, others...)
	}
	return rows
}

func storyMatches(st *story, term string) bool {
	if strings.Contains(strings.ToLower(st.label+" "+st.title), term) {
		return true
	}
	for _, d := range st.deliverables {
		if strings.Contains(strings.ToLower(d.ID), term) {
			return true
		}
	}
	return false
}

// readPreview reads what the preview shows for the current row: the end of the agent's
// pane when the row has a window, else what the board knows of the row.
func (m boardView) readPreview() tea.Cmd {
	r, ok := m.current()
	if !ok {
		return nil
	}
	key, run, lines := r.key(), m.run, m.previewHeight()
	switch {
	case r.kind == windowRow:
		pane := r.w.pane
		return func() tea.Msg { return previewMsg{key, run.capture(pane, lines)} }
	case r.kind == storyRow && r.story.orchestrator != nil && m.showPane:
		pane := r.story.orchestrator.pane
		return func() tea.Msg { return previewMsg{key, run.capture(pane, lines)} }
	case r.kind == deliverableRow:
		return previewOf(run, key, r.d, lines)
	}
	text := storyPreview(r)
	return func() tea.Msg { return previewMsg{key, text} }
}

// previewOf is the end of the agent's pane when the deliverable has a window, else what
// clerk knows of it and the start of its task file.
func previewOf(run runner, key string, d *deliverable, lines int) tea.Cmd {
	if d.window != nil {
		pane := d.window.pane
		return func() tea.Msg { return previewMsg{key, run.capture(pane, lines)} }
	}
	return func() tea.Msg {
		return previewMsg{key, deliverablePreview(d) + "\n" + run.readFile(d.TasksFile, lines)}
	}
}

func deliverablePreview(d *deliverable) string {
	lines := []string{
		fmt.Sprintf("%s  %s  %d/%d tasks  %s", d.ID, d.State, d.Done, d.Total, filepath.Base(d.plan.root)),
		"branch:   " + firstOf(d.Alias, d.Branch),
		"worktree: " + firstOf(d.Worktree, "none"),
	}
	if d.PR != nil {
		lines = append(lines, fmt.Sprintf("PR:       #%d %s  %s", d.PR.Number, d.PR.State, d.PR.URL))
	}
	if len(d.BlockedBy) > 0 {
		lines = append(lines, "waits on: "+strings.Join(d.BlockedBy, ", "))
	}
	if d.Evidence != "" {
		lines = append(lines, "merged:   "+d.Evidence)
	}
	if d.TasksFile == "" {
		return strings.Join(lines, "\n") + "\n"
	}
	return strings.Join(append(lines, "tasks:    "+d.TasksFile), "\n") + "\n"
}

func storyPreview(r row) string {
	switch r.kind {
	case storyRow:
		lines := []string{r.story.label + "  " + r.story.title, "repos: " + strings.Join(r.story.repos, ", "), ""}
		lines = append(lines, dependencyGraph(r.story.deliverables, len(r.story.repos) > 1)...)
		lines = append(lines, "")
		for _, p := range r.story.plans {
			lines = append(lines, "plan: "+p.Path)
		}
		return strings.Join(lines, "\n")
	case mergedRow:
		var lines []string
		for _, d := range r.merged {
			lines = append(lines, d.ID+": "+firstOf(d.Evidence, "merged"))
		}
		return strings.Join(lines, "\n")
	}
	return ""
}

// fixedLines are the header, the line over the preview, and the footer.
const fixedLines = 3

func previewHeightOf(height int) int { return max(3, (height-fixedLines)*2/5) }

func listHeightOf(height int) int { return max(1, height-fixedLines-previewHeightOf(height)) }

// scrolled is the first row to show so that the cursor stays in view.
func scrolled(cursor, offset, rows, height int) int {
	if cursor < offset {
		offset = cursor
	}
	if cursor >= offset+height {
		offset = cursor - height + 1
	}
	return max(0, min(offset, max(0, rows-height)))
}

func (m boardView) previewHeight() int { return previewHeightOf(m.height) }

func (m boardView) listHeight() int { return listHeightOf(m.height) }

func (m *boardView) scroll() { m.offset = scrolled(m.cursor, m.offset, len(m.rows), m.listHeight()) }

var (
	bold      = lipgloss.NewStyle().Bold(true)
	dimmed    = lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
	selected  = lipgloss.NewStyle().Foreground(lipgloss.Color("212"))
	asking    = lipgloss.NewStyle().Foreground(lipgloss.Color("0")).Background(lipgloss.Color("212")).Bold(true)
	rankStyle = map[int]lipgloss.Style{
		rankAnswer: lipgloss.NewStyle().Foreground(lipgloss.Color("5")).Bold(true),
		rankAct:    lipgloss.NewStyle().Foreground(lipgloss.Color("1")),
		rankClose:  lipgloss.NewStyle().Foreground(lipgloss.Color("2")),
		rankBusy:   lipgloss.NewStyle().Foreground(lipgloss.Color("6")),
	}
	markOf = map[string]string{
		"merged":         lipgloss.NewStyle().Foreground(lipgloss.Color("2")).Render("✓"),
		"awaiting-merge": lipgloss.NewStyle().Foreground(lipgloss.Color("6")).Render("●"),
		"in-progress":    lipgloss.NewStyle().Foreground(lipgloss.Color("3")).Render("●"),
		"scaffolded":     lipgloss.NewStyle().Foreground(lipgloss.Color("3")).Render("●"),
		"ready":          "○",
		"blocked":        dimmed.Render("◌"),
	}
	iconOf = map[string]string{"waiting": "💬", "working": "🤖", "done": "✅"}
)

func mark(state string) string { return firstOf(markOf[state], " ") }

func icon(agent string) string { return firstOf(iconOf[agent], "  ") }

func paint(n need, text string) string {
	if s, ok := rankStyle[n.rank]; ok {
		return s.Render(text)
	}
	return dimmed.Render(text)
}

// cell cuts or pads text to `width` cells.
func cell(text string, width int) string {
	text = ansi.Truncate(text, width, "…")
	return text + strings.Repeat(" ", max(0, width-ansi.StringWidth(text)))
}

func count(n int, one, many string) string {
	if n == 1 {
		return "1 " + one
	}
	return fmt.Sprintf("%d %s", n, many)
}

func (m boardView) View() string {
	var b strings.Builder
	header := bold.Render(fmt.Sprintf("deliverables · %d need you", m.board.needsYou()))
	switch {
	case m.loading:
		header += dimmed.Render(" · reading the stories…")
	case !m.loadedAt.IsZero():
		header += dimmed.Render(fmt.Sprintf(" · stories read %s ago", m.now().Sub(m.loadedAt).Round(time.Second)))
	}
	if m.message != "" {
		header += " · " + m.message
	}
	b.WriteString(ansi.Truncate(header, m.width, "…") + "\n")

	h := m.listHeight()
	for i := m.offset; i < m.offset+h; i++ {
		if i < len(m.rows) {
			b.WriteString(m.renderRow(m.rows[i], i == m.cursor))
		}
		b.WriteString("\n")
	}
	b.WriteString(dimmed.Render(strings.Repeat("─", max(0, m.width))) + "\n")

	preview := ""
	if r, ok := m.current(); ok && m.preview.key == r.key() {
		preview = m.preview.text
	}
	lines := strings.Split(preview, "\n")
	for i := 0; i < m.previewHeight(); i++ {
		if i < len(lines) {
			b.WriteString(ansi.Truncate(lines[i], m.width, "…"))
		}
		b.WriteString("\n")
	}

	switch {
	case m.ask != nil:
		b.WriteString(ansi.Truncate(asking.Render(m.ask.text+" [y/N]"), m.width, "…"))
	case m.filtering || m.filter.Value() != "":
		b.WriteString(m.filter.View())
	default:
		b.WriteString(dimmed.Render(ansi.Truncate(
			"enter go, start, or go to the orchestrator · o open the PR · x close a merged window · a archive the story · t graph or orchestrator · ←/→ fold · / filter · tab features · r reload · q quit",
			m.width, "…")))
	}
	return b.String()
}

func (m boardView) renderRow(r row, current bool) string {
	gutter := "  "
	if current {
		gutter = selected.Render("▌ ")
	}
	var text string
	switch r.kind {
	case storyRow:
		st := r.story
		text = bold.Render(st.label) + "  " + cell(st.title, 70) + "  " + dimmed.Render(strings.Join(st.repos, ", "))
		text += orchestratorNote(st.orchestrator)
		if m.isFolded(st) && m.filter.Value() == "" {
			text += dimmed.Render("  · " + foldedSummary(st))
		}
	case deliverableRow:
		text = deliverableLine(r.d, len(r.story.repos) > 1)
	case mergedRow:
		ids := make([]string, len(r.merged))
		for i, d := range r.merged {
			ids[i] = d.ID
		}
		text = "  " + mark("merged") + " " + cell("merged", 15) +
			dimmed.Render(ansi.Truncate(fmt.Sprintf("%d deliverables: %s", len(r.merged), strings.Join(ids, ", ")), 80, "…"))
	case othersRow:
		text = bold.Render("Other windows")
	case windowRow:
		w := r.w
		text = "  " + cell(w.target, 9) + icon(w.agent) + "  " + paint(w.need, cell(w.need.text, 24)) +
			cell(w.title, 40) + "  " + dimmed.Render(filepath.Base(w.root))
	}
	return ansi.Truncate(gutter+text, m.width, "…")
}

func deliverableLine(d *deliverable, withRepo bool) string {
	pr := ""
	switch {
	case d.PR != nil:
		pr = fmt.Sprintf("#%d", d.PR.Number)
	case d.State == "awaiting-merge" && d.plan.PRError != "":
		pr = "PR ?"
	case d.State == "awaiting-merge":
		pr = "no PR"
	}
	target, agent := "-", ""
	if d.window != nil {
		target, agent = d.window.target, d.window.agent
	}
	text := "  " + mark(d.State) + " " + cell(d.State, 15) + cell(d.ID, 30) + cell(fmt.Sprintf("%d/%d", d.Done, d.Total), 6) +
		cell(pr, 7) + cell(target, 9) + icon(agent) + "  " + paint(d.need, d.need.text)
	if d.stacksOn != "" {
		text += dimmed.Render("  · on " + d.stacksOn)
	}
	if withRepo {
		text += "  " + dimmed.Render(filepath.Base(d.plan.root))
	}
	return text
}

// dependencyGraph is the deliverables of a story by wave: what each one depends on, and the
// sibling that its branch stacks on.
func dependencyGraph(ds []*deliverable, withRepo bool) []string {
	sorted := append([]*deliverable(nil), ds...)
	sort.SliceStable(sorted, func(i, j int) bool {
		if sorted[i].Wave != sorted[j].Wave {
			return sorted[i].Wave < sorted[j].Wave
		}
		return sorted[i].ID < sorted[j].ID
	})
	deps := make([]string, len(sorted))
	idWidth, depsWidth := 0, 0
	for i, d := range sorted {
		if len(d.DependsOn) > 0 {
			deps[i] = "<- " + strings.Join(d.DependsOn, ", ")
		}
		idWidth, depsWidth = max(idWidth, len(d.ID)), max(depsWidth, len(deps[i]))
	}
	lines := make([]string, len(sorted))
	for i, d := range sorted {
		label := ""
		if i == 0 || sorted[i-1].Wave != d.Wave {
			label = fmt.Sprintf("wave %d", d.Wave)
		}
		line := cell(label, 8) + mark(d.State) + " " + cell(d.ID, idWidth+2) + cell(d.State, 16) + cell(deps[i], depsWidth+2)
		if d.stacksOn != "" {
			line += "on " + d.stacksOn
		}
		if withRepo {
			line += "  " + filepath.Base(d.plan.root)
		}
		lines[i] = strings.TrimRight(line, " ")
	}
	return lines
}

// orchestratorNote names the window of the orchestrator and the state of its agent, and
// what it needs when it waits.
func orchestratorNote(w *window) string {
	if w == nil {
		return ""
	}
	note := "  · " + w.target + " " + icon(w.agent)
	if n := orchestratorNeed(w); n.rank <= rankAct {
		note += " " + paint(n, n.text)
	}
	return note
}

func foldedSummary(st *story) string {
	counts := map[string]int{}
	var order []string
	for _, d := range st.deliverables {
		if counts[d.State] == 0 {
			order = append(order, d.State)
		}
		counts[d.State]++
	}
	parts := make([]string, len(order))
	for i, state := range order {
		parts[i] = fmt.Sprintf("%d %s", counts[state], state)
	}
	return strings.Join(parts, ", ")
}
