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

// lines are the lines of the view, under the tab bar.
func (s *screen) lines() []string { return strings.Split(ansi.Strip(s.m.View()), "\n")[1:] }

func (s *screen) tabBar() string { return strings.Split(ansi.Strip(s.m.View()), "\n")[0] }

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
	t.Run("the tab bar", func(t *testing.T) {
		t.Run("names both views and marks the one that shows", func(t *testing.T) {
			s := startApp(t, newFake(nil, nil), "/repos/a", boardID)

			before := s.tabBar()
			s.press("tab")

			require.Equal(t, "[under way]  features    tab switches", before)
			require.Equal(t, " under way  [features]   tab switches", s.tabBar())
		})

		t.Run("leaves the view its own height, so the last line still shows", func(t *testing.T) {
			s := startApp(t, newFake(nil, nil), "/repos/a", boardID)

			require.LessOrEqual(t, len(strings.Split(s.m.View(), "\n")), 80)
		})
	})

	t.Run("jumping between the views", func(t *testing.T) {
		underWay := func(root, ticket, slug string) *plan {
			return planIn(root, ticket, slug, deliverableJSON("building", "in-progress", 1, 3))
		}

		t.Run("f on a story under way opens its feature in the planner, with the cursor on the story", func(t *testing.T) {
			f := newFake([]*plan{underWay("/repos/a", "AGE-3", "age-3-under-way")}, nil)
			f.featureList = []feature{twoFeatures()[0], signInSummary()}
			f.opened = signIn()
			s := startApp(t, f, "/repos/a", boardID)
			s.to("AGE-3")

			s.press("f")

			require.Equal(t, []string{"feature docs/proposals/sign-in.md in /repos/a"}, featureCalls(f))
			require.True(t, strings.HasPrefix(s.header(), "deliver · Sign in"), s.header())
			require.Contains(t, s.selected(), "US-003")
		})

		t.Run("f finds a story with no ticket by its key, in the repo of the story", func(t *testing.T) {
			p := underWay("/repos/b", "", "sign-in-us-001")
			p.StoryID = "sign-in/US-001"
			f := newFake([]*plan{p}, nil)
			f.featureList = []feature{signInSummary()}
			f.opened = signIn()
			f.opened.Stories[0].Ticket = ""
			s := startApp(t, f, "/repos/a", boardID)
			s.to("sign-in-us-001")

			s.press("f")

			require.Equal(t, []string{"feature docs/proposals/sign-in.md in /repos/b"}, featureCalls(f))
			require.Contains(t, s.selected(), "US-001")
		})

		t.Run("f on a story that no feature holds says so, and shows the features", func(t *testing.T) {
			f := newFake([]*plan{underWay("/repos/a", "AGE-9", "age-9-lost")}, nil)
			f.featureList = twoFeatures()
			s := startApp(t, f, "/repos/a", boardID)
			s.to("AGE-9")

			s.press("f")

			require.True(t, strings.HasSuffix(s.header(), "no feature here holds AGE-9"), s.header())
			require.Len(t, s.rows(), 2)
		})

		t.Run("f with no story under the cursor says what it needs", func(t *testing.T) {
			s := startApp(t, newFake(nil, nil), "/repos/a", boardID)

			s.press("f")

			require.True(t, strings.HasSuffix(s.header(), "f opens the feature of a story: put the cursor on a story or a deliverable"), s.header())
		})

		t.Run("u on a story in the planner puts the cursor of the board on it", func(t *testing.T) {
			f := newFake([]*plan{underWay("/repos/a", "AGE-0", "age-0-first"), underWay("/repos/a", "AGE-3", "age-3-under-way")}, nil)
			f.featureList = []feature{signInSummary()}
			f.opened = signIn()
			s := startApp(t, f, "/repos/a", plannerID)
			s.to("US-003")

			s.press("u")

			require.True(t, strings.HasPrefix(s.header(), "deliverables"), s.header())
			require.Contains(t, s.selected(), "AGE-3")
		})

		t.Run("u on a story that is not under way says so on the board", func(t *testing.T) {
			f := newFake([]*plan{underWay("/repos/a", "AGE-3", "age-3-under-way")}, nil)
			f.featureList = []feature{signInSummary()}
			f.opened = signIn()
			s := startApp(t, f, "/repos/a", plannerID)

			s.press("u")

			require.True(t, strings.HasSuffix(s.header(), "US-001 is not under way"), s.header())
		})
	})

	t.Run("switching", func(t *testing.T) {
		t.Run("tab shows the planner, and reads the features of the repo", func(t *testing.T) {
			f := newFake(nil, nil)
			f.featureList = twoFeatures()
			s := startApp(t, f, "/repos/a", boardID)

			s.press("tab")

			require.Len(t, s.rows(), 2)
			require.True(t, strings.HasSuffix(s.rows()[1], "Second  user-stories/b.md"), s.rows()[1])
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

// signInSummary is signIn as `feature list` prints it.
func signInSummary() feature {
	full := signIn()
	f := feature{Path: full.Path, Title: full.Title, State: full.State}
	for _, st := range full.Stories {
		f.StoryKeys = append(f.StoryKeys, st.Key)
		if st.Ticket != "" {
			f.StoryTickets = append(f.StoryTickets, st.Ticket)
		}
	}
	return f
}
