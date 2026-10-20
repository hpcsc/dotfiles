package main

import (
	"errors"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
	"github.com/stretchr/testify/require"
)

// popup drives the view the way Bubble Tea does: a key goes to Update, and each command
// that Update returns runs, and its message goes back to Update.
type popup struct {
	t    *testing.T
	m    boardView
	now  time.Time
	quit bool
}

func open(t *testing.T, f *fakeRunner) *popup {
	t.Helper()
	p := &popup{t: t, now: time.Date(2026, 10, 20, 9, 0, 0, 0, time.UTC)}
	p.m = newBoardView(f, "/dev/ttys004")
	p.m.tick = func() tea.Cmd { return nil }
	p.m.now = func() time.Time { return p.now }
	p.m.width, p.m.height = 220, 80
	p.run(p.m.Init())
	return p
}

func (p *popup) send(msg tea.Msg) {
	next, cmd := p.m.Update(msg)
	p.m = next.(boardView)
	p.run(cmd)
}

func (p *popup) run(cmd tea.Cmd) {
	if cmd == nil {
		return
	}
	switch msg := cmd().(type) {
	case nil:
	case tea.BatchMsg:
		for _, c := range msg {
			p.run(c)
		}
	case tea.QuitMsg:
		p.quit = true
	default:
		p.send(msg)
	}
}

func (p *popup) press(keys ...string) {
	for _, k := range keys {
		switch k {
		case "enter":
			p.send(tea.KeyMsg{Type: tea.KeyEnter})
		case "esc":
			p.send(tea.KeyMsg{Type: tea.KeyEsc})
		case "up":
			p.send(tea.KeyMsg{Type: tea.KeyUp})
		case "down":
			p.send(tea.KeyMsg{Type: tea.KeyDown})
		case "left":
			p.send(tea.KeyMsg{Type: tea.KeyLeft})
		case "right":
			p.send(tea.KeyMsg{Type: tea.KeyRight})
		default:
			p.send(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(k)})
		}
	}
}

// to moves the cursor down to the first row that contains `text`.
func (p *popup) to(text string) {
	p.t.Helper()
	for i := 0; i < len(p.m.rows); i++ {
		if strings.Contains(p.rows()[p.m.cursor-p.m.offset], text) {
			return
		}
		p.press("down")
	}
	p.t.Fatalf("no row contains %q", text)
}

func (p *popup) lines() []string { return strings.Split(ansi.Strip(p.m.View()), "\n") }

func (p *popup) header() string { return p.lines()[0] }

func (p *popup) footer() string { l := p.lines(); return l[len(l)-1] }

// rows are the lines of the list, without the gutter, the indent and the blank lines under it.
func (p *popup) rows() []string {
	var rows []string
	for _, l := range p.lines()[1:] {
		if strings.HasPrefix(l, "─") {
			break
		}
		if strings.TrimSpace(l) != "" {
			rows = append(rows, strings.TrimSpace(strings.TrimPrefix(l, "▌ ")))
		}
	}
	return rows
}

// row is the row of a deliverable or a window, found by its id or target.
func (p *popup) row(name string) string {
	p.t.Helper()
	for _, r := range p.rows() {
		if strings.Contains(r, " "+name+" ") || strings.HasPrefix(r, name+" ") {
			return r
		}
	}
	p.t.Fatalf("no row for %q in:\n%s", name, strings.Join(p.rows(), "\n"))
	return ""
}

func (p *popup) preview() string {
	l := p.lines()
	for i, line := range l {
		if strings.HasPrefix(line, "─") {
			return strings.TrimSpace(strings.Join(l[i+1:len(l)-1], "\n"))
		}
	}
	return ""
}

func TestBoardView(t *testing.T) {
	t.Run("showing", func(t *testing.T) {
		t.Run("each deliverable says what it needs", func(t *testing.T) {
			withWorktree := func(state string, done, total int, more ...any) map[string]any {
				return deliverableJSON("one", state, done, total, append([]any{"worktree", worktreeOf("/repos/a", "one")}, more...)...)
			}
			cases := []struct {
				name  string
				d     map[string]any
				agent string // the state of the agent in the window of the deliverable; "" for no window
				prErr string
				need  string
			}{
				{"an agent that waits for an answer needs one", withWorktree("in-progress", 1, 4), "waiting", "", "answer the agent"},
				{"an agent at work needs nothing, whatever its deliverable is", withWorktree("awaiting-merge", 3, 3), "working", "", "working"},
				{"a run that went quiet before its last task stopped", withWorktree("in-progress", 2, 5), "done", "", "the run stopped at 2/5"},
				{"a run with no window that did not finish stopped too", deliverableJSON("one", "in-progress", 6, 11), "", "", "the run stopped at 6/11"},
				{"an empty worktree is a run that stopped before its first task", withWorktree("scaffolded", 0, 4), "done", "", "the run stopped at 0/4"},
				{"a finished deliverable with no PR needs one", deliverableJSON("one", "awaiting-merge", 3, 3), "", "", "open a PR"},
				{"a PR that gh could not read is unknown, not missing", deliverableJSON("one", "awaiting-merge", 3, 3), "", "HTTP 502", "PR unknown: HTTP 502"},
				{"a draft PR needs to be marked ready", deliverableJSON("one", "awaiting-merge", 3, 3, "pr", prJSON(8, "open", true, "", "")), "", "", "PR #8 is a draft: mark it ready"},
				{"failing checks come before an approval", deliverableJSON("one", "awaiting-merge", 3, 3, "pr", prJSON(9, "open", false, "approved", "fail")), "", "", "PR #9: checks fail"},
				{"changes asked for come before a draft", deliverableJSON("one", "awaiting-merge", 3, 3, "pr", prJSON(9, "open", true, "changes-requested", "")), "", "", "PR #9: changes requested"},
				{"an approved PR needs a merge", deliverableJSON("one", "awaiting-merge", 3, 3, "pr", prJSON(10, "open", false, "approved", "pass")), "", "", "PR #10 is approved: merge it"},
				{"a PR in review waits on others", deliverableJSON("one", "awaiting-merge", 3, 3, "pr", prJSON(11, "open", false, "review-required", "pending")), "", "", "PR #11 is in review"},
				{"a PR closed without a merge needs a decision", deliverableJSON("one", "awaiting-merge", 3, 3, "pr", prJSON(12, "closed", false, "", "")), "", "", "PR #12 is closed, not merged"},
				{"a merged PR with commits after it needs another one", deliverableJSON("one", "awaiting-merge", 3, 3, "pr", prJSON(13, "merged", false, "", "")), "", "", "PR #13 merged, commits after it"},
				{"a merged deliverable with a window open leaves a window to close", withWorktree("merged", 4, 4), "done", "", "merged: close the window"},
				{"a merged deliverable with no window is done", deliverableJSON("one", "merged", 4, 4), "", "", "done"},
			}
			for _, c := range cases {
				t.Run(c.name, func(t *testing.T) {
					p := planIn("/repos/a", "AGE-1", "age-1-story", c.d, deliverableJSON("other", "awaiting-merge", 1, 1))
					p.PRError = c.prErr
					var panes []pane
					var agents []agent
					if c.agent != "" {
						panes = []pane{inWorktree("W:1", "%1", "/repos/a", "one")}
						agents = []agent{{Pane: "%1", Status: c.agent}}
					}

					shown := open(t, newFake([]*plan{p}, panes, agents...))

					require.True(t, strings.HasSuffix(shown.row("one"), c.need), shown.row("one"))
				})
			}
		})

		t.Run("the ready and the blocked deliverables say so when their story is opened", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-1", "age-1-story",
				deliverableJSON("first", "ready", 0, 2), deliverableJSON("second", "blocked", 0, 3, "blocked_by", []string{"first", "other"}))
			shown := open(t, newFake([]*plan{p}, nil))

			shown.press("right")

			require.Equal(t, []string{"start it", "waits on first, other"},
				[]string{lastField(shown.row("first"), "start it"), lastField(shown.row("second"), "waits on first, other")})
		})

		t.Run("each story is a heading over its deliverables, and the stories that need you come first", func(t *testing.T) {
			plans := []*plan{
				planIn("/repos/a", "AGE-2", "age-2-review", deliverableJSON("reviewed", "awaiting-merge", 3, 3, "pr", prJSON(4, "open", false, "review-required", ""))),
				planIn("/repos/a", "AGE-3", "age-3-urgent",
					deliverableJSON("ready-one", "ready", 0, 1), deliverableJSON("no-pr", "awaiting-merge", 3, 3)),
			}

			shown := open(t, newFake(plans, nil))

			require.Equal(t, []string{"AGE-3", "no-pr", "ready-one", "AGE-2", "reviewed"}, names(shown.rows()))
		})

		t.Run("one ticket in two repos is one story, and each row names its repo", func(t *testing.T) {
			plans := []*plan{
				planIn("/repos/portal", "AGE-7", "age-7-sign-in", deliverableJSON("ask", "awaiting-merge", 2, 2)),
				planIn("/repos/platform", "AGE-7", "age-7-sign-in", deliverableJSON("send", "awaiting-merge", 3, 3)),
			}

			shown := open(t, newFake(plans, nil))

			require.Equal(t, []string{"AGE-7", "ask", "send"}, names(shown.rows()))
			require.True(t, strings.HasSuffix(shown.rows()[0], "platform, portal"), shown.rows()[0])
			require.True(t, strings.HasSuffix(shown.row("send"), "open a PR  platform"), shown.row("send"))
		})

		t.Run("a deliverable row shows its state, tasks, PR, window, agent and need", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-1", "age-1-story",
				deliverableJSON("no-pr", "awaiting-merge", 3, 3, "worktree", worktreeOf("/repos/a", "no-pr")))

			shown := open(t, newFake([]*plan{p}, []pane{inWorktree("W:3", "%3", "/repos/a", "no-pr")}, agent{Pane: "%3", Status: "done"}))

			require.Equal(t, strings.Join(strings.Fields("● awaiting-merge no-pr 3/3 no PR W:3 ✅ open a PR"), " "),
				strings.Join(strings.Fields(shown.row("no-pr")), " "))
		})

		t.Run("a pane deeper in the worktree still holds the deliverable", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-1", "age-1-story", deliverableJSON("one", "in-progress", 1, 3, "worktree", worktreeOf("/repos/a", "one")))
			deeper := pane{window: "W:2", id: "%2", path: worktreeOf("/repos/a", "one") + "/internal/api"}

			shown := open(t, newFake([]*plan{p}, []pane{deeper}, agent{Pane: "%2", Status: "working"}))

			require.Contains(t, shown.row("one"), " W:2 ")
		})

		t.Run("a worktree whose name only starts the same is another worktree", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-1", "age-1-story", deliverableJSON("one", "in-progress", 1, 3, "worktree", worktreeOf("/repos/a", "one")))
			sibling := pane{window: "W:3", id: "%3", path: worktreeOf("/repos/a", "one-more")}

			shown := open(t, newFake([]*plan{p}, []pane{sibling}, agent{Pane: "%3", Status: "working"}))

			require.NotContains(t, shown.row("one"), "W:3")
		})

		t.Run("a story with every deliverable merged and no window open is not shown", func(t *testing.T) {
			plans := []*plan{
				planIn("/repos/a", "AGE-9", "age-9-done", deliverableJSON("old", "merged", 3, 3)),
				planIn("/repos/a", "AGE-1", "age-1-open", deliverableJSON("live", "awaiting-merge", 1, 1)),
			}

			shown := open(t, newFake(plans, nil))

			require.Equal(t, []string{"AGE-1", "live"}, names(shown.rows()))
		})

		t.Run("a story with every deliverable merged stays while a window is open", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-8", "age-8-landed", deliverableJSON("gone", "merged", 4, 4, "worktree", worktreeOf("/repos/a", "gone")))

			shown := open(t, newFake([]*plan{p}, []pane{inWorktree("W:8", "%8", "/repos/a", "gone")}, agent{Pane: "%8", Status: "done"}))

			require.Equal(t, []string{"AGE-8", "gone"}, names(shown.rows()))
		})

		t.Run("the merged deliverables with no window share one row", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-1", "age-1-story",
				deliverableJSON("live", "awaiting-merge", 1, 1), deliverableJSON("old-one", "merged", 2, 2), deliverableJSON("old-two", "merged", 2, 2))

			shown := open(t, newFake([]*plan{p}, nil))

			require.Equal(t, "✓ merged         2 deliverables: old-one, old-two", shown.rows()[2])
		})

		t.Run("a story where nothing needs a look is folded, with a count of its states", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-5", "age-5-backlog",
				deliverableJSON("first", "ready", 0, 2), deliverableJSON("next", "blocked", 0, 2, "blocked_by", []string{"first"}))

			shown := open(t, newFake([]*plan{p}, nil))

			require.Len(t, shown.rows(), 1)
			require.True(t, strings.HasSuffix(shown.rows()[0], "· 1 ready, 1 blocked"), shown.rows()[0])
		})

		t.Run("windows with an agent and no deliverable come last, under Other windows", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-1", "age-1-story", deliverableJSON("live", "awaiting-merge", 1, 1))
			panes := []pane{{window: "W:1", name: "zsh", id: "%1", path: "/repos/dotfiles"}, {window: "W:4", name: "shell", id: "%4", path: "/elsewhere"}}

			shown := open(t, newFake([]*plan{p}, panes, agent{Pane: "%1", Status: "working", Title: "✳ Plan the rollout"}))

			require.Equal(t, []string{"AGE-1", "live", "Other", "W:1"}, names(shown.rows()))
			require.Equal(t, strings.Join(strings.Fields("W:1 🤖 working Plan the rollout dotfiles"), " "),
				strings.Join(strings.Fields(shown.row("W:1")), " "))
		})

		t.Run("other windows come in order of need, then of window number", func(t *testing.T) {
			panes := []pane{
				{window: "W:10", id: "%10", path: "/repos/a"}, {window: "W:9", id: "%9", path: "/repos/a"}, {window: "W:2", id: "%2", path: "/repos/a"},
			}

			shown := open(t, newFake(nil, panes, agent{Pane: "%10", Status: "done"}, agent{Pane: "%9", Status: "done"}, agent{Pane: "%2", Status: "waiting"}))

			require.Equal(t, []string{"Other", "W:2", "W:9", "W:10"}, names(shown.rows()))
		})

		t.Run("the header counts the deliverables and windows that wait on a person", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-1", "age-1-story",
				deliverableJSON("no-pr", "awaiting-merge", 2, 2), deliverableJSON("later", "ready", 0, 2),
				deliverableJSON("asks", "in-progress", 1, 2, "worktree", worktreeOf("/repos/a", "asks")))
			panes := []pane{inWorktree("W:1", "%1", "/repos/a", "asks"), {window: "W:2", id: "%2", path: "/repos/a"}}

			shown := open(t, newFake([]*plan{p}, panes, agent{Pane: "%1", Status: "waiting"}, agent{Pane: "%2", Status: "waiting"}))

			require.True(t, strings.HasPrefix(shown.header(), "deliverables · 3 need you"), shown.header())
		})
	})

	t.Run("previewing", func(t *testing.T) {
		t.Run("a row with a window shows the end of the agent's pane", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-1", "age-1-story", deliverableJSON("asks", "in-progress", 1, 2, "worktree", worktreeOf("/repos/a", "asks")))
			f := newFake([]*plan{p}, []pane{inWorktree("W:1", "%1", "/repos/a", "asks")}, agent{Pane: "%1", Status: "waiting"})
			f.captured["%1"] = "Do you want to make this edit?\n❯ 1. Yes"
			shown := open(t, f)

			shown.to("asks")

			require.Equal(t, "Do you want to make this edit?\n❯ 1. Yes", shown.preview())
		})

		t.Run("a deliverable with no window shows its branch, its PR and its task file", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-1", "age-1-story", deliverableJSON("draft", "awaiting-merge", 3, 3, "pr", prJSON(8, "open", true, "", "")))
			f := newFake([]*plan{p}, nil)
			f.files["/tasks/draft.md"] = "## Task 1: Draft it"
			shown := open(t, f)

			shown.to("draft")

			require.Equal(t, strings.Join([]string{
				"draft  awaiting-merge  3/3 tasks  a",
				"branch:   br-draft",
				"worktree: none",
				"PR:       #8 open  https://example.test/pull/8",
				"tasks:    /tasks/draft.md",
				"",
				"## Task 1: Draft it",
			}, "\n"), shown.preview())
		})
	})

	t.Run("folding", func(t *testing.T) {
		twoStories := func() *fakeRunner {
			return newFake([]*plan{
				planIn("/repos/a", "AGE-1", "age-1-story", deliverableJSON("one", "awaiting-merge", 1, 1), deliverableJSON("two", "awaiting-merge", 1, 1)),
				planIn("/repos/a", "AGE-2", "age-2-story", deliverableJSON("three", "awaiting-merge", 1, 1)),
			}, nil)
		}

		t.Run("left folds the story of the row and moves to its heading", func(t *testing.T) {
			shown := open(t, twoStories())
			shown.to("two")

			shown.press("left")

			require.Equal(t, []string{"AGE-1", "AGE-2", "three"}, names(shown.rows()))
			require.Equal(t, 0, shown.m.cursor)
		})

		t.Run("right opens it again", func(t *testing.T) {
			shown := open(t, twoStories())
			shown.press("left")

			shown.press("right")

			require.Equal(t, []string{"AGE-1", "one", "two", "AGE-2", "three"}, names(shown.rows()))
		})

		t.Run("enter on a heading folds the story, and a second enter opens it", func(t *testing.T) {
			shown := open(t, twoStories())

			shown.press("enter")
			folded := names(shown.rows())
			shown.press("enter")

			require.Equal(t, [][]string{{"AGE-1", "AGE-2", "three"}, {"AGE-1", "one", "two", "AGE-2", "three"}},
				[][]string{folded, names(shown.rows())})
		})
	})

	t.Run("going", func(t *testing.T) {
		t.Run("enter on a deliverable with a window goes to that window and closes the popup", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-1", "age-1-story", deliverableJSON("asks", "in-progress", 1, 2, "worktree", worktreeOf("/repos/a", "asks")))
			f := newFake([]*plan{p}, []pane{inWorktree("W:1", "%1", "/repos/a", "asks")}, agent{Pane: "%1", Status: "waiting"})
			shown := open(t, f)
			shown.to("asks")

			shown.press("enter")

			require.Equal(t, []string{"switch /dev/ttys004 to W:1"}, f.actions())
			require.True(t, shown.quit)
		})

		t.Run("enter on a deliverable with no window opens or starts it in its repo, and closes the popup", func(t *testing.T) {
			f := newFake([]*plan{planIn("/repos/platform", "AGE-1", "age-1-story", deliverableJSON("fresh", "awaiting-merge", 0, 2))}, nil)
			shown := open(t, f)
			shown.to("fresh")

			shown.press("enter")

			require.Equal(t, []string{"deliverable-open /dev/ttys004 fresh in /repos/platform"}, f.actions())
			require.True(t, shown.quit)
		})

		t.Run("when it cannot start, the popup stays and says why", func(t *testing.T) {
			f := newFake([]*plan{planIn("/repos/a", "AGE-1", "age-1-story", deliverableJSON("fresh", "awaiting-merge", 0, 2))}, nil)
			f.openErr = errors.New("fresh is blocked by asks — finish those first, or start one of them.")
			shown := open(t, f)
			shown.to("fresh")

			shown.press("enter")

			require.False(t, shown.quit)
			require.True(t, strings.HasSuffix(shown.header(), "fresh is blocked by asks — finish those first, or start one of them."), shown.header())
		})

		t.Run("enter on another window goes to it", func(t *testing.T) {
			f := newFake(nil, []pane{{window: "W:2", id: "%2", path: "/repos/a"}}, agent{Pane: "%2", Status: "done"})
			shown := open(t, f)
			shown.to("W:2")

			shown.press("enter")

			require.Equal(t, []string{"switch /dev/ttys004 to W:2"}, f.actions())
		})
	})

	t.Run("opening the PR", func(t *testing.T) {
		t.Run("o opens the PR of the deliverable in the browser", func(t *testing.T) {
			f := newFake([]*plan{planIn("/repos/a", "AGE-1", "age-1-story", deliverableJSON("draft", "awaiting-merge", 3, 3, "pr", prJSON(8, "open", true, "", "")))}, nil)
			shown := open(t, f)
			shown.to("draft")

			shown.press("o")

			require.Equal(t, []string{"open https://example.test/pull/8"}, f.actions())
		})

		t.Run("with no PR, o says so", func(t *testing.T) {
			f := newFake([]*plan{planIn("/repos/a", "AGE-1", "age-1-story", deliverableJSON("no-pr", "awaiting-merge", 3, 3))}, nil)
			shown := open(t, f)
			shown.to("no-pr")

			shown.press("o")

			require.Empty(t, f.actions())
			require.True(t, strings.HasSuffix(shown.header(), "no PR to open"), shown.header())
		})
	})

	t.Run("closing a window", func(t *testing.T) {
		merged := func(agentState string) *fakeRunner {
			p := planIn("/repos/b", "AGE-8", "age-8-landed", deliverableJSON("gone", "merged", 4, 4, "worktree", worktreeOf("/repos/b", "gone")))
			return newFake([]*plan{p}, []pane{inWorktree("W:8", "%8", "/repos/b", "gone")}, agent{Pane: "%8", Status: agentState})
		}

		t.Run("x asks before it closes the window of a merged deliverable", func(t *testing.T) {
			f := merged("done")
			shown := open(t, f)
			shown.to("gone")

			shown.press("x")

			require.Equal(t, "Close W:8, the window of gone? The worktree and the branch stay. [y/N]", shown.footer())
			require.Empty(t, f.actions())
		})

		t.Run("y closes it in its repo, and the stories are read again", func(t *testing.T) {
			f := merged("done")
			shown := open(t, f)
			shown.to("gone")

			shown.press("x", "y")

			require.Equal(t, []string{"snapshot", "close h-gone in /repos/b", "snapshot"}, withoutWindows(f.calls))
			require.True(t, strings.HasSuffix(shown.header(), "closed W:8"), shown.header())
		})

		t.Run("any other answer changes nothing", func(t *testing.T) {
			f := merged("done")
			shown := open(t, f)
			shown.to("gone")

			shown.press("x", "n")

			require.Empty(t, f.actions())
			require.True(t, strings.HasSuffix(shown.header(), "nothing changed"), shown.header())
		})

		t.Run("x keeps the window of an agent that works", func(t *testing.T) {
			f := merged("working")
			shown := open(t, f)
			shown.to("gone")

			shown.press("x")

			require.True(t, strings.HasSuffix(shown.header(), "the agent in W:8 is working: it keeps its window"), shown.header())
		})

		t.Run("x on a deliverable that is not merged says so, and asks nothing", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-1", "age-1-story", deliverableJSON("asks", "in-progress", 1, 2, "worktree", worktreeOf("/repos/a", "asks")))
			shown := open(t, newFake([]*plan{p}, []pane{inWorktree("W:1", "%1", "/repos/a", "asks")}, agent{Pane: "%1", Status: "done"}))
			shown.to("asks")

			shown.press("x")

			require.True(t, strings.HasSuffix(shown.header(), "asks is not merged"), shown.header())
			require.NotContains(t, shown.footer(), "[y/N]")
		})
	})

	t.Run("archiving a story", func(t *testing.T) {
		unfinished := func() *fakeRunner {
			return newFake([]*plan{
				planIn("/repos/portal", "AGE-7", "age-7-sign-in", deliverableJSON("ask", "merged", 2, 2), deliverableJSON("check", "in-progress", 1, 3)),
				planIn("/repos/platform", "AGE-7", "age-7-sign-in", deliverableJSON("send", "blocked", 0, 3, "blocked_by", []string{"check"})),
			}, nil)
		}

		t.Run("a asks before it archives, and names the deliverables that are not merged", func(t *testing.T) {
			f := unfinished()
			shown := open(t, f)

			shown.press("a")

			require.Equal(t, "Archive AGE-7? 2 deliverables are not merged: check (in-progress), send (blocked). Its folder moves to tasks/completed/ all the same. [y/N]",
				shown.footer())
			require.Empty(t, f.actions())
		})

		t.Run("y archives the plan of the story in each repo, with --force while work is not merged", func(t *testing.T) {
			f := unfinished()
			shown := open(t, f)
			shown.to("send")

			shown.press("a", "y")

			require.Equal(t, []string{
				"archive /repos/portal/tasks/age-7-sign-in/plan.yaml in /repos/portal force=true",
				"archive /repos/platform/tasks/age-7-sign-in/plan.yaml in /repos/platform force=true",
			}, f.actions())
			require.True(t, strings.HasSuffix(shown.header(), "archived AGE-7"), shown.header())
		})

		t.Run("a story with every deliverable merged is archived without --force", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-8", "age-8-landed", deliverableJSON("gone", "merged", 4, 4, "worktree", worktreeOf("/repos/a", "gone")))
			f := newFake([]*plan{p}, []pane{inWorktree("W:8", "%8", "/repos/a", "gone")}, agent{Pane: "%8", Status: "done"})
			shown := open(t, f)

			shown.press("a")
			question := shown.footer()
			shown.press("y")

			require.Equal(t, "Archive AGE-8? Its folder moves to tasks/completed/. [y/N]", question)
			require.Equal(t, []string{"archive /repos/a/tasks/age-8-landed/plan.yaml in /repos/a force=false"}, f.actions())
		})

		t.Run("when clerk refuses, the popup says why", func(t *testing.T) {
			f := unfinished()
			f.fails = errors.New("not archived, because /repos/portal/tasks/completed/age-7-sign-in/plan.yaml is in the archive already")
			shown := open(t, f)

			shown.press("a", "y")

			require.Contains(t, shown.header(), "could not archive AGE-7: not archived, because")
		})
	})

	t.Run("filtering", func(t *testing.T) {
		stories := func() *fakeRunner {
			return newFake([]*plan{
				planIn("/repos/a", "AGE-1083", "age-1083-choose", deliverableJSON("check-the-facts", "awaiting-merge", 5, 5)),
				planIn("/repos/a", "AGE-1055", "age-1055-address", deliverableJSON("single-host", "ready", 0, 6)),
			}, nil)
		}

		t.Run("/ and a word show only the stories that match, opened", func(t *testing.T) {
			shown := open(t, stories())

			shown.press("/", "h", "o", "s", "t")

			require.Equal(t, []string{"AGE-1055", "single-host"}, names(shown.rows()))
		})

		t.Run("esc clears the filter", func(t *testing.T) {
			shown := open(t, stories())
			shown.press("/", "h", "o", "s", "t")

			shown.press("esc")

			require.Equal(t, []string{"AGE-1083", "check-the-facts", "AGE-1055"}, names(shown.rows()))
		})
	})

	t.Run("refreshing", func(t *testing.T) {
		t.Run("a tick reads the windows again, and the cursor stays on its row", func(t *testing.T) {
			p := planIn("/repos/a", "AGE-1", "age-1-story",
				deliverableJSON("asks", "in-progress", 1, 2, "worktree", worktreeOf("/repos/a", "asks")), deliverableJSON("later", "awaiting-merge", 1, 1))
			f := newFake([]*plan{p}, []pane{inWorktree("W:1", "%1", "/repos/a", "asks")}, agent{Pane: "%1", Status: "working"})
			shown := open(t, f)
			shown.to("asks")
			f.snap.agents = []agent{{Pane: "%1", Status: "waiting"}}

			shown.send(tickMsg{})

			require.True(t, strings.HasSuffix(shown.row("asks"), "answer the agent"), shown.row("asks"))
			require.Equal(t, shown.row("asks"), shown.rows()[shown.m.cursor])
		})

		t.Run("a minute after the last read, a tick reads the stories again", func(t *testing.T) {
			f := newFake([]*plan{planIn("/repos/a", "AGE-1", "age-1-story", deliverableJSON("one", "awaiting-merge", 1, 1))}, nil)
			shown := open(t, f)

			shown.now = shown.now.Add(30 * time.Second)
			shown.send(tickMsg{})
			early := withoutWindows(f.calls)
			shown.now = shown.now.Add(30 * time.Second)
			shown.send(tickMsg{})

			require.Equal(t, [][]string{{"snapshot"}, {"snapshot", "snapshot"}}, [][]string{early, withoutWindows(f.calls)})
		})
	})
}

// names are the first words of the rows: the label of a story, the id of a deliverable,
// the target of a window.
func names(rows []string) []string {
	out := make([]string, 0, len(rows))
	for _, r := range rows {
		f := strings.Fields(r)
		switch {
		case len(f) >= 3 && strings.ContainsAny(f[0], "●○◌✓"):
			out = append(out, f[2])
		case len(f) > 0:
			out = append(out, f[0])
		}
	}
	return out
}

func lastField(row, want string) string {
	if strings.HasSuffix(row, want) {
		return want
	}
	return row
}

func withoutWindows(calls []string) []string {
	var out []string
	for _, c := range calls {
		if c != "windows" {
			out = append(out, c)
		}
	}
	return out
}
