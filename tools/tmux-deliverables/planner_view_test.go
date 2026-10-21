package main

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// plannedJSON is one deliverable as `clerk project` prints it: what `clerk story` says of
// it, with its plan and story slug.
func plannedJSON(slug, id, state string, done, total int, more ...any) json.RawMessage {
	d := deliverableJSON(id, state, done, total, append([]any{"plan", "/repos/a/tasks/" + slug + "/plan.yaml", "story_slug", slug}, more...)...)
	raw, err := json.Marshal(d)
	if err != nil {
		panic(err)
	}
	return raw
}

// signIn is a feature of four stories, one in each state that has a next step, and one
// that is blocked.
func signIn() project {
	return project{
		Running: []string{"age-3-under-way/building"},
		Stories: []projectStory{
			{ID: "US-001", Title: "Plan me", Ticket: "AGE-1", State: "ready", Step: 1, Critical: true, Unblocks: 2,
				Dependents: []string{"US-004"}, Evidence: "no plan names AGE-1"},
			{ID: "US-002", Title: "Approve me", Ticket: "AGE-2", State: "planned", Step: 1,
				Plans: []string{"/repos/a/tasks/age-2-planned/plan.yaml"}, Evidence: "no approved: line"},
			{ID: "US-003", Title: "Under way", Ticket: "AGE-3", State: "in-progress", Step: 1,
				Plans: []string{"/repos/a/tasks/age-3-under-way/plan.yaml"}, Evidence: "1 in-progress, 1 ready",
				Deliverables: []json.RawMessage{
					plannedJSON("age-3-under-way", "building", "in-progress", 1, 3, "worktree", "/repos/a/.worktrees/building"),
					plannedJSON("age-3-under-way", "next", "ready", 0, 2),
				}},
			{ID: "US-004", Title: "Wait for me", Ticket: "AGE-4", State: "blocked", Step: 2, Critical: true,
				DependsOn: []string{"US-001"}, BlockedBy: []string{"US-001"}, Evidence: "US-001 not merged"},
		},
	}
}

func plannerOn(t *testing.T, p project, panes []pane, agents ...agent) (*screen, *fakeRunner) {
	t.Helper()
	f := newFake(nil, panes, agents...)
	f.featureList = []feature{{path: "user-stories/sign-in.md", title: "Sign in"}}
	f.planned = p
	return startApp(t, f, "/repos/a", plannerID), f
}

func TestPlannerView(t *testing.T) {
	t.Run("features", func(t *testing.T) {
		t.Run("with one stories file, its stories open at once", func(t *testing.T) {
			s, f := plannerOn(t, signIn(), nil)

			require.True(t, strings.HasPrefix(s.header(), "deliver · Sign in"), s.header())
			require.Contains(t, f.calls, "project user-stories/sign-in.md in /repos/a")
		})

		t.Run("with two, the planner lists them, and enter opens the one under the cursor", func(t *testing.T) {
			f := newFake(nil, nil)
			f.featureList = []feature{{path: "user-stories/a.md", title: "First"}, {path: "user-stories/b.md", title: "Second"}}
			f.planned = signIn()
			s := startApp(t, f, "/repos/a", plannerID)

			s.press("down", "enter")

			require.Equal(t, []string{"project user-stories/b.md in /repos/a"}, projectCalls(f))
			require.True(t, strings.HasPrefix(s.header(), "deliver · Second"), s.header())
		})

		t.Run("p starts /deliver-project on the feature in a window of its own, and goes there", func(t *testing.T) {
			f := newFake(nil, nil)
			f.featureList = []feature{{path: "user-stories/a.md", title: "First"}, {path: "user-stories/b.md", title: "Second"}}
			s := startApp(t, f, "/repos/a", plannerID)

			s.press("p")

			require.Equal(t, []string{
				"claude window deliver-a in /repos/a: /deliver-project /repos/a/user-stories/a.md",
				"switch /dev/ttys004 to Work:deliver-a",
			}, f.actions())
			require.True(t, s.quit)
		})

		t.Run("b on the stories goes back to the list", func(t *testing.T) {
			f := newFake(nil, nil)
			f.featureList = []feature{{path: "user-stories/a.md", title: "First"}, {path: "user-stories/b.md", title: "Second"}}
			s := startApp(t, f, "/repos/a", plannerID)
			s.press("enter")

			s.press("b")

			require.Equal(t, []string{"First  user-stories/a.md", "Second  user-stories/b.md"}, s.rows())
		})

		t.Run("with no stories file, the planner says where it looked", func(t *testing.T) {
			s := startApp(t, newFake(nil, nil), "/repos/a", plannerID)

			require.True(t, strings.HasSuffix(s.header(), "no stories file with **Ticket:** lines under .scratches/write-user-story or user-stories"), s.header())
		})
	})

	t.Run("stories", func(t *testing.T) {
		t.Run("a story row shows its state, ID, ticket, the stories it unblocks, its title and what blocks it", func(t *testing.T) {
			s, _ := plannerOn(t, signIn(), nil)

			require.Contains(t, s.rows(), "blocked        US-004  AGE-4     ↑0   Wait for me  [blocked by US-001]")
		})

		t.Run("a story under way shows its deliverables under it, with what each needs", func(t *testing.T) {
			s, _ := plannerOn(t, signIn(), nil)

			require.Equal(t, []string{"US-001", "US-002", "US-003", "building", "next", "US-004"}, plannedNames(s.rows()))
			require.True(t, strings.HasSuffix(s.rows()[3], "the run stopped at 1/3"), s.rows()[3])
		})

		t.Run("a deliverable in a window shows the window and its agent", func(t *testing.T) {
			s, _ := plannerOn(t, signIn(), []pane{inWorktree("W:5", "%5", "/repos/a", "building")}, agent{Pane: "%5", Status: "working"})

			require.Equal(t, strings.Join(strings.Fields("● in-progress building 1/3 W:5 🤖 working"), " "),
				strings.Join(strings.Fields(s.rows()[3]), " "))
		})

		t.Run("the header names the feature and the runs under way against the limit", func(t *testing.T) {
			s, _ := plannerOn(t, signIn(), nil)

			require.Equal(t, "deliver · Sign in · runs 1 (limit 2)", s.header())
		})
	})

	t.Run("orchestrators", func(t *testing.T) {
		gate := pane{window: "W:4", name: "repo", id: "%4", path: "/repos/a", orchestrates: []string{"/repos/a/tasks/age-2-planned/plan.yaml"}}

		t.Run("a story row names the window of its orchestrator", func(t *testing.T) {
			s, _ := plannerOn(t, signIn(), []pane{gate}, agent{Pane: "%4", Status: "waiting"})

			require.True(t, strings.HasSuffix(s.rows()[1], "Approve me  · W:4 💬 answer the orchestrator"), s.rows()[1])
		})

		t.Run("enter on a story with an orchestrator goes there", func(t *testing.T) {
			s, f := plannerOn(t, signIn(), []pane{gate}, agent{Pane: "%4", Status: "waiting"})
			s.to("US-002")

			s.press("enter")

			require.Equal(t, []string{"switch /dev/ttys004 to W:4"}, f.actions())
		})

		t.Run("n on a planned story goes to its orchestrator, and opens no window for the gate", func(t *testing.T) {
			s, f := plannerOn(t, signIn(), []pane{gate}, agent{Pane: "%4", Status: "waiting"})
			s.to("US-002")

			s.press("n")

			require.Equal(t, []string{"switch /dev/ttys004 to W:4"}, f.actions())
		})
	})

	t.Run("previewing", func(t *testing.T) {
		t.Run("a story shows what it waits on and what waits on it, with their states", func(t *testing.T) {
			s, _ := plannerOn(t, signIn(), nil)

			preview := s.preview()

			require.Contains(t, preview, "US-001  AGE-1  ready  step 1  critical path")
			require.Contains(t, preview, "waited on by:  US-004 blocked")
			require.Contains(t, preview, "unblocks:      2 stories in all")
		})

		t.Run("a story lists its deliverables by wave, with what each depends on and stacks on", func(t *testing.T) {
			p := signIn()
			p.Stories[2].Deliverables = []json.RawMessage{
				plannedJSON("age-3-under-way", "building", "in-progress", 1, 3, "base", "main"),
				plannedJSON("age-3-under-way", "next", "ready", 0, 2, "wave", 2, "base", "building", "depends_on", []string{"building"}),
			}
			s, _ := plannerOn(t, p, nil)
			s.to("US-003")

			require.Contains(t, s.preview(), strings.Join([]string{
				"deliverables:",
				"  wave 1  ● building  in-progress",
				"  wave 2  ○ next      ready           <- building  on building",
			}, "\n"))
		})

		t.Run("t shows the feature by step, with the critical path, and t again shows the story", func(t *testing.T) {
			s, _ := plannerOn(t, signIn(), nil)

			s.press("t")
			graph := s.preview()
			s.press("t")

			require.Equal(t, strings.Join([]string{
				"step 1  * US-001  ready",
				"          US-002  planned",
				"          US-003  in-progress",
				"step 2  * US-004  blocked        <- US-001",
				"",
				"* critical path: 2 steps · t: back to the story",
			}, "\n"), graph)
			require.True(t, strings.HasPrefix(s.preview(), "US-001  AGE-1  ready"), s.preview())
		})
	})

	t.Run("the next step", func(t *testing.T) {
		t.Run("a ready story gets a window that plans it from its section of the stories file", func(t *testing.T) {
			s, f := plannerOn(t, signIn(), nil)

			s.press("n")

			require.Equal(t, []string{
				"claude window age-1-plan in /repos/a: /deliver-story AGE-1: deliver story US-001 of /repos/a/user-stories/sign-in.md. Read its section, from its ### heading to the next heading, as the story.",
				"switch /dev/ttys004 to Work:age-1-plan",
			}, f.actions())
			require.True(t, s.quit)
		})

		t.Run("a planned story gets a window that takes its plan through the gate", func(t *testing.T) {
			s, f := plannerOn(t, signIn(), nil)
			s.to("US-002")

			s.press("n")

			require.Equal(t, []string{
				"claude window age-2-gate in /repos/a: /deliver-story /repos/a/tasks/age-2-planned/plan.yaml",
				"switch /dev/ttys004 to Work:age-2-gate",
			}, f.actions())
		})

		t.Run("a story under way starts its ready deliverables only, in the background, and reads the stories again", func(t *testing.T) {
			s, f := plannerOn(t, signIn(), nil)
			s.to("US-003")

			s.press("n")

			require.Equal(t, []string{"start next in /repos/a gears=false"}, f.actions())
			require.Len(t, projectCalls(f), 2)
			require.True(t, strings.HasSuffix(s.header(), "started next"), s.header())
		})

		t.Run("a blocked story has no next step, and says so", func(t *testing.T) {
			s, f := plannerOn(t, signIn(), nil)
			s.to("US-004")

			s.press("n")

			require.Empty(t, f.actions())
			require.True(t, strings.HasSuffix(s.header(), "US-004 is blocked: no next step here"), s.header())
		})
	})

	t.Run("starting a deliverable", func(t *testing.T) {
		t.Run("s starts the deliverable in the background", func(t *testing.T) {
			s, f := plannerOn(t, signIn(), nil)
			s.to("next")

			s.press("s")

			require.Equal(t, []string{"start next in /repos/a gears=false"}, f.actions())
		})

		t.Run("g starts it with gears", func(t *testing.T) {
			s, f := plannerOn(t, signIn(), nil)
			s.to("next")

			s.press("g")

			require.Equal(t, []string{"start next in /repos/a gears=true"}, f.actions())
		})

		t.Run("enter on a deliverable with a window goes to that window", func(t *testing.T) {
			s, f := plannerOn(t, signIn(), []pane{inWorktree("W:5", "%5", "/repos/a", "building")}, agent{Pane: "%5", Status: "working"})
			s.to("building")

			s.press("enter")

			require.Equal(t, []string{"switch /dev/ttys004 to W:5"}, f.actions())
			require.True(t, s.quit)
		})
	})
}

func projectCalls(f *fakeRunner) []string {
	var calls []string
	for _, c := range f.calls {
		if strings.HasPrefix(c, "project ") {
			calls = append(calls, c)
		}
	}
	return calls
}

// plannedNames are the IDs of the stories and the deliverables, in the order shown.
func plannedNames(rows []string) []string {
	out := make([]string, 0, len(rows))
	for _, r := range rows {
		f := strings.Fields(r)
		switch {
		case len(f) >= 3 && strings.ContainsAny(f[0], "●○◌✓"):
			out = append(out, f[2])
		case len(f) >= 2:
			out = append(out, f[1])
		}
	}
	return out
}
