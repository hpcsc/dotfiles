package main

import (
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
	"github.com/stretchr/testify/require"
)

// screen drives the app the way Bubble Tea does: a key goes to Update, each command that
// Update returns runs, and its message goes back to Update.
type screen struct {
	t    *testing.T
	m    tea.Model
	quit bool
}

func startApp(t *testing.T, f *fakeRunner, root string, active viewID) *screen {
	t.Helper()
	now := time.Date(2026, 10, 20, 9, 0, 0, 0, time.UTC)
	board := newBoardView(f, "/dev/ttys004")
	board.tick, board.now = func() tea.Cmd { return nil }, func() time.Time { return now }
	planner := newPlannerView(f, "/dev/ttys004", root, 2)
	planner.tick, planner.now = func() tea.Cmd { return nil }, func() time.Time { return now }
	s := &screen{t: t, m: newApp(board, planner, root != "", active)}
	s.send(tea.WindowSizeMsg{Width: 220, Height: 80})
	s.run(s.m.Init())
	return s
}

func (s *screen) send(msg tea.Msg) {
	next, cmd := s.m.Update(msg)
	s.m = next
	s.run(cmd)
}

func (s *screen) run(cmd tea.Cmd) {
	if cmd == nil {
		return
	}
	switch msg := cmd().(type) {
	case nil:
	case tea.BatchMsg:
		for _, c := range msg {
			s.run(c)
		}
	case tea.QuitMsg:
		s.quit = true
	default:
		s.send(msg)
	}
}

func (s *screen) press(keys ...string) {
	for _, k := range keys {
		switch k {
		case "enter":
			s.send(tea.KeyMsg{Type: tea.KeyEnter})
		case "tab":
			s.send(tea.KeyMsg{Type: tea.KeyTab})
		case "down":
			s.send(tea.KeyMsg{Type: tea.KeyDown})
		case "right":
			s.send(tea.KeyMsg{Type: tea.KeyRight})
		default:
			s.send(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(k)})
		}
	}
}

func (s *screen) lines() []string { return strings.Split(ansi.Strip(s.m.View()), "\n") }

func (s *screen) header() string { return s.lines()[0] }

// rows are the lines of the list, without the gutter, the indent and the blank lines.
func (s *screen) rows() []string {
	var rows []string
	for _, l := range s.lines()[1:] {
		if strings.HasPrefix(l, "─") {
			break
		}
		if strings.TrimSpace(l) != "" {
			rows = append(rows, strings.TrimSpace(strings.TrimPrefix(l, "▌ ")))
		}
	}
	return rows
}

// selected is the row under the cursor.
func (s *screen) selected() string {
	for _, l := range s.lines()[1:] {
		if strings.HasPrefix(l, "▌ ") {
			return strings.TrimSpace(strings.TrimPrefix(l, "▌ "))
		}
	}
	return ""
}

// to moves the cursor down to the first row that contains `text`.
func (s *screen) to(text string) {
	s.t.Helper()
	for i := 0; i < 50; i++ {
		if strings.Contains(s.selected(), text) {
			return
		}
		s.press("down")
	}
	s.t.Fatalf("no row contains %q in:\n%s", text, strings.Join(s.rows(), "\n"))
}

func (s *screen) preview() string {
	l := s.lines()
	for i, line := range l {
		if strings.HasPrefix(line, "─") {
			return strings.TrimSpace(strings.Join(l[i+1:len(l)-1], "\n"))
		}
	}
	return ""
}

func TestApp(t *testing.T) {
	t.Run("switching", func(t *testing.T) {
		t.Run("tab shows the planner, and reads the features of the repo", func(t *testing.T) {
			f := newFake(nil, nil)
			f.featureList = []feature{{path: "user-stories/sign-in.md", title: "Sign in"}, {path: "user-stories/pay.md", title: "Pay"}}
			s := startApp(t, f, "/repos/a", boardID)

			s.press("tab")

			require.Equal(t, []string{"Sign in  user-stories/sign-in.md", "Pay  user-stories/pay.md"}, s.rows())
		})

		t.Run("tab again shows the board, as it was", func(t *testing.T) {
			f := newFake([]*plan{planIn("/repos/a", "AGE-1", "age-1-story", deliverableJSON("one", "awaiting-merge", 1, 1))}, nil)
			s := startApp(t, f, "/repos/a", boardID)
			s.press("tab")

			s.press("tab")

			require.Equal(t, []string{"snapshot"}, withoutWindows(f.calls))
			require.True(t, strings.HasPrefix(s.header(), "deliverables · 1 need you"), s.header())
		})

		t.Run("outside a git repo, tab says that the planner needs one", func(t *testing.T) {
			s := startApp(t, newFake(nil, nil), "", boardID)

			s.press("tab")

			require.True(t, strings.HasSuffix(s.header(), "the planner needs a git repo: open the popup from a pane in one"), s.header())
		})

		t.Run("tab goes into the filter while the filter is open", func(t *testing.T) {
			s := startApp(t, newFake(nil, nil), "/repos/a", boardID)
			s.press("/")

			s.press("tab")

			require.True(t, strings.HasPrefix(s.header(), "deliverables"), s.header())
		})
	})

	t.Run("routing", func(t *testing.T) {
		t.Run("the result of a read reaches the view that asked for it, whichever view shows", func(t *testing.T) {
			f := newFake(nil, nil)
			s := startApp(t, f, "/repos/a", boardID)
			s.press("tab")
			later := snapshot{plans: []*plan{planIn("/repos/a", "AGE-2", "age-2-later", deliverableJSON("late", "awaiting-merge", 1, 1))}}

			s.send(routed{to: boardID, msg: loadedMsg{later}})
			s.press("tab")

			require.Equal(t, []string{"AGE-2", "late"}, names(s.rows()))
		})
	})
}
