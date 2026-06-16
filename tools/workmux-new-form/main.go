// workmux-new-form renders the "New session" form for the tmux workmux menu as
// a small gitui/tig-style multi-panel TUI: a repository list on the left, and
// the name + two toggles on the right. Panels are navigated vim-style and the
// focused panel is highlighted.
//
// Repository directories are passed as arguments. On submit it prints a
// tab-separated line to stdout:
//
//	<repo-dir>\t<name>\t<worktree:yes|no>\t<mode:window|session>
//
// The TUI renders on stderr, so the caller can capture the result with $(...).
// A cancel (q/esc) or empty name yields no stdout, which the caller treats as
// "cancelled".
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	accent = lipgloss.Color("212")
	dim    = lipgloss.Color("240")
	muted  = lipgloss.Color("252")

	titleFocused = lipgloss.NewStyle().Foreground(lipgloss.Color("0")).Background(accent).Bold(true)
	titleBlurred = lipgloss.NewStyle().Foreground(dim).Bold(true)
	radioOn      = lipgloss.NewStyle().Foreground(accent)
	radioOff     = lipgloss.NewStyle().Foreground(muted)
	helpStyle    = lipgloss.NewStyle().Foreground(dim)
	previewStyle = lipgloss.NewStyle().Foreground(accent)
)

type focusArea int

const (
	focusRepo focusArea = iota
	focusName
	focusWorktree
	focusMode
	focusCount
)

var (
	worktreeOpts = []string{"worktree — nvim in a new worktree", "no worktree — nvim at repo root"}
	worktreeVals = []string{"yes", "no"}
	modeOpts     = []string{"tmux session (default)", "tmux window"}
	modeVals     = []string{"session", "window"}
)

type repoItem struct{ path string }

func (r repoItem) FilterValue() string { return filepath.Base(r.path) }
func (r repoItem) Title() string       { return filepath.Base(r.path) }
func (r repoItem) Description() string { return "" }

// substringFilter replaces the list's default fuzzy matcher. The query is split
// on whitespace into tokens; an item matches only when it contains every token
// as a case-insensitive substring, in any order. So "platform" keeps only repos
// containing "platform" (not "playground"), and "play go" keeps "go-playground"
// and "playground-go" alike.
func substringFilter(term string, targets []string) []list.Rank {
	tokens := strings.Fields(strings.ToLower(term))
	if len(tokens) == 0 {
		ranks := make([]list.Rank, len(targets))
		for i := range targets {
			ranks[i] = list.Rank{Index: i}
		}
		return ranks
	}

	var ranks []list.Rank
	for i, t := range targets {
		lt := strings.ToLower(t)
		hits := map[int]struct{}{}
		matchedAll := true
		for _, tok := range tokens {
			idx := strings.Index(lt, tok)
			if idx < 0 {
				matchedAll = false
				break
			}
			for j := 0; j < len(tok); j++ {
				hits[idx+j] = struct{}{}
			}
		}
		if !matchedAll {
			continue
		}
		matched := make([]int, 0, len(hits))
		for k := range hits {
			matched = append(matched, k)
		}
		sort.Ints(matched)
		ranks = append(ranks, list.Rank{Index: i, MatchedIndexes: matched})
	}
	return ranks
}

type model struct {
	repos    list.Model
	name     textinput.Model
	worktree int
	mode     int
	focus    focusArea

	width, height int
	leftW, rightW int

	submitted bool
	quitting  bool
}

func initialModel(paths []string) model {
	items := make([]list.Item, len(paths))
	for i, p := range paths {
		items[i] = repoItem{p}
	}

	d := list.NewDefaultDelegate()
	d.ShowDescription = false
	d.SetHeight(1)
	d.SetSpacing(0)
	d.Styles.SelectedTitle = d.Styles.SelectedTitle.Foreground(accent).BorderForeground(accent)
	d.Styles.NormalTitle = d.Styles.NormalTitle.Foreground(muted)

	l := list.New(items, d, 0, 0)
	l.SetShowTitle(false)
	l.SetShowStatusBar(false)
	l.SetShowHelp(false)
	l.SetFilteringEnabled(true)
	l.Filter = substringFilter
	l.DisableQuitKeybindings()

	ti := textinput.New()
	ti.Placeholder = "name…"
	ti.Prompt = "> "
	ti.CharLimit = 80

	return model{repos: l, name: ti, focus: focusRepo}
}

func (m model) Init() tea.Cmd { return nil }

// The right column is three fixed-height panels (Name 4, Start with 5, Open as
// 5 rows including borders/titles); size everything to match so the form stays
// compact rather than stretching to fill a wide popup.
const rightColRows = 4 + 5 + 5

func (m *model) layout() {
	if m.width == 0 {
		return
	}
	// Cap the overall width so the form reads as a panel group, not a full-width sprawl.
	totalW := m.width
	if totalW > 84 {
		totalW = 84
	}
	m.leftW = 30
	if m.leftW > totalW-25 {
		m.leftW = totalW * 40 / 100
	}
	// total = leftW + 2 (border) + 1 (gap) + rightW + 2 (border)
	m.rightW = totalW - m.leftW - 5
	if m.rightW < 22 {
		m.rightW = 22
	}

	listH := rightColRows - 3 // match the right column minus this panel's border+title
	if listH < 4 {
		listH = 4
	}
	m.repos.SetSize(m.leftW, listH)
	m.name.Width = m.rightW - 3
}

func (m *model) syncFocus() tea.Cmd {
	if m.focus == focusName {
		return m.name.Focus()
	}
	m.name.Blur()
	return nil
}

func (m model) next() focusArea { return (m.focus + 1) % focusCount }
func (m model) prev() focusArea { return (m.focus + focusCount - 1) % focusCount }

func (m model) submit() (tea.Model, tea.Cmd) {
	if m.repos.SelectedItem() == nil || strings.TrimSpace(m.name.Value()) == "" {
		// Nudge focus to whatever still needs input.
		if m.repos.SelectedItem() == nil {
			m.focus = focusRepo
		} else {
			m.focus = focusName
		}
		return m, m.syncFocus()
	}
	m.submitted = true
	m.quitting = true
	return m, tea.Quit
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		m.layout()
		return m, nil

	case tea.KeyMsg:
		// While the repo list is filtering it owns every key (typing, esc, enter).
		if m.focus == focusRepo && m.repos.FilterState() == list.Filtering {
			var cmd tea.Cmd
			m.repos, cmd = m.repos.Update(msg)
			return m, cmd
		}

		// The name field captures typing; only structural keys navigate out.
		if m.focus == focusName {
			switch msg.String() {
			case "tab":
				m.focus = m.next()
				return m, m.syncFocus()
			case "shift+tab":
				m.focus = m.prev()
				return m, m.syncFocus()
			case "enter":
				return m.submit()
			case "esc", "ctrl+c":
				m.quitting = true
				return m, tea.Quit
			default:
				var cmd tea.Cmd
				m.name, cmd = m.name.Update(msg)
				return m, cmd
			}
		}

		switch msg.String() {
		case "ctrl+c", "q", "esc":
			m.quitting = true
			return m, tea.Quit
		case "enter":
			return m.submit()
		case "tab":
			m.focus = m.next()
			return m, m.syncFocus()
		case "shift+tab":
			m.focus = m.prev()
			return m, m.syncFocus()
		case "h", "left":
			m.focus = focusRepo
			return m, m.syncFocus()
		case "l", "right":
			if m.focus == focusRepo {
				m.focus = focusName
				return m, m.syncFocus()
			}
		case "/":
			if m.focus == focusRepo {
				var cmd tea.Cmd
				m.repos, cmd = m.repos.Update(msg)
				return m, cmd
			}
		case "j", "down", "k", "up", " ":
			switch m.focus {
			case focusRepo:
				var cmd tea.Cmd
				m.repos, cmd = m.repos.Update(msg)
				return m, cmd
			case focusWorktree:
				m.worktree ^= 1
			case focusMode:
				m.mode ^= 1
			}
			return m, nil
		}
		// Unhandled keys are ignored rather than forwarded blindly.
		return m, nil
	}

	// Non-key, non-resize messages (async filter results, cursor blink) must
	// reach the embedded components so their commands complete — without this
	// the list's FilterMatchesMsg never lands and filtering does nothing.
	var cmds []tea.Cmd
	var cmd tea.Cmd
	m.repos, cmd = m.repos.Update(msg)
	cmds = append(cmds, cmd)
	m.name, cmd = m.name.Update(msg)
	cmds = append(cmds, cmd)
	return m, tea.Batch(cmds...)
}

func panel(title, content string, focused bool, width int) string {
	// A thick border + filled title chip makes the focused panel unmistakable
	// even when the accent/dim colours are close.
	border := lipgloss.RoundedBorder()
	bc := dim
	ts := titleBlurred
	if focused {
		border = lipgloss.ThickBorder()
		bc = accent
		ts = titleFocused
	}
	box := lipgloss.NewStyle().
		Border(border).
		BorderForeground(bc).
		Padding(0, 1).
		Width(width)
	return box.Render(ts.Render(" "+title+" ") + "\n" + content)
}

func radioView(opts []string, sel int) string {
	lines := make([]string, len(opts))
	for i, o := range opts {
		if i == sel {
			lines[i] = radioOn.Render("● " + o)
		} else {
			lines[i] = radioOff.Render("○ " + o)
		}
	}
	return strings.Join(lines, "\n")
}

func sanitize(s string, bad string) string {
	return strings.Map(func(r rune) rune {
		if strings.ContainsRune(bad, r) {
			return '_'
		}
		return r
	}, s)
}

func (m model) sessionPreview() string {
	if m.repos.SelectedItem() == nil {
		return ""
	}
	repo := sanitize(filepath.Base(m.repos.SelectedItem().(repoItem).path), ".:")
	name := strings.TrimSpace(m.name.Value())
	if name == "" {
		return ""
	}
	return repo + "-" + sanitize(name, " .:/")
}

func (m model) View() string {
	if m.quitting {
		return ""
	}

	repoPanel := panel("Repository", m.repos.View(), m.focus == focusRepo, m.leftW)
	namePanel := panel("Name", m.name.View(), m.focus == focusName, m.rightW)
	wtPanel := panel("Start with", radioView(worktreeOpts, m.worktree), m.focus == focusWorktree, m.rightW)
	modePanel := panel("Open as", radioView(modeOpts, m.mode), m.focus == focusMode, m.rightW)

	right := lipgloss.JoinVertical(lipgloss.Left, namePanel, wtPanel, modePanel)
	body := lipgloss.JoinHorizontal(lipgloss.Top, repoPanel, " ", right)

	preview := ""
	if s := m.sessionPreview(); s != "" {
		preview = previewStyle.Render(" session: " + s)
	}
	help := helpStyle.Render(" tab panel · j/k select · h/l column · / filter · ⏎ create · q quit")

	return lipgloss.JoinVertical(lipgloss.Left, body, preview, help)
}

func main() {
	var paths []string
	for _, r := range os.Args[1:] {
		r = strings.TrimRight(strings.TrimSpace(r), "/")
		if r != "" {
			paths = append(paths, r)
		}
	}
	if len(paths) == 0 {
		fmt.Fprintln(os.Stderr, "workmux-new-form: no repositories provided")
		os.Exit(1)
	}

	p := tea.NewProgram(initialModel(paths), tea.WithOutput(os.Stderr), tea.WithAltScreen())
	res, err := p.Run()
	if err != nil {
		fmt.Fprintln(os.Stderr, "workmux-new-form:", err)
		os.Exit(1)
	}

	fm := res.(model)
	if !fm.submitted || fm.repos.SelectedItem() == nil {
		os.Exit(130)
	}
	dir := fm.repos.SelectedItem().(repoItem).path
	name := strings.TrimSpace(fm.name.Value())
	if name == "" {
		os.Exit(130)
	}
	fmt.Printf("%s\t%s\t%s\t%s\n", dir, name, worktreeVals[fm.worktree], modeVals[fm.mode])
}
