package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

const stubTmux = `#!/usr/bin/env bash
case "$1" in
  list-panes)   printf '%b' "${PANES:-}" ;;
  capture-pane) printf 'line one\n\nthe question\n\n\n' ;;
  display-message) echo Work ;;
  list-windows) printf '%b' "${WINDOWS:-}" ;;
  *)            echo "tmux $*" >> "$LOG" ;;
esac
`

const stubClerk = `#!/usr/bin/env bash
echo "clerk $* in $PWD" >> "$LOG"
[ "$2" = archive ] && exit 0
[ "$1" = project ] && { cat "$PWD/project.json"; exit; }
cat "$PWD/story.json" 2>/dev/null || exit 2
`

const stubWorkmux = `#!/usr/bin/env bash
case "$1" in
  status) cat "$PWD/agents.json" 2>/dev/null || echo '[]' ;;
  *)      echo "workmux $* in $PWD" >> "$LOG" ;;
esac
`

const stubDeliverableOpen = `#!/usr/bin/env bash
for a in "$@"; do echo "deliverable-open arg: $a" >> "$LOG"; done
echo "deliverable-open in $PWD" >> "$LOG"
if [ -n "${OPEN_REFUSES:-}" ]; then echo "fresh is blocked by asks" >&2; exit 1; fi
echo "starting fresh"
`

// withStubs puts tmux, clerk, workmux and deliverable-open stubs first on PATH. Each
// writes what it gets to the log file it returns.
func withStubs(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	for name, script := range map[string]string{
		"tmux": stubTmux, "clerk": stubClerk, "workmux": stubWorkmux, "deliverable-open": stubDeliverableOpen,
	} {
		require.NoError(t, os.WriteFile(filepath.Join(dir, name), []byte(script), 0o755))
	}
	log := filepath.Join(dir, "log")
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("LOG", log)
	return log
}

func logOf(t *testing.T, log, prefix string) []string {
	t.Helper()
	data, _ := os.ReadFile(log)
	var lines []string
	for _, l := range strings.Split(strings.TrimSpace(string(data)), "\n") {
		if strings.HasPrefix(l, prefix) {
			lines = append(lines, l)
		}
	}
	return lines
}

func gitRepo(t *testing.T) string {
	t.Helper()
	dir, err := filepath.EvalSymlinks(t.TempDir())
	require.NoError(t, err)
	for _, args := range [][]string{
		{"init", "-q", "-b", "main"},
		{"-c", "user.email=t@t", "-c", "user.name=T", "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "seed"},
	} {
		out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).CombinedOutput()
		require.NoError(t, err, string(out))
	}
	return dir
}

func writeFile(t *testing.T, path, text string) {
	t.Helper()
	require.NoError(t, os.MkdirAll(filepath.Dir(path), 0o755))
	require.NoError(t, os.WriteFile(path, []byte(text), 0o644))
}

func TestCommands(t *testing.T) {
	t.Run("reading", func(t *testing.T) {
		t.Run("clerk is asked once in each repo with a pane and each project repo with a live plan, without a fetch", func(t *testing.T) {
			log := withStubs(t)
			withPane := gitRepo(t)
			projects, err := filepath.EvalSymlinks(t.TempDir())
			require.NoError(t, err)
			writeFile(t, filepath.Join(projects, "planned", "tasks", "s", "plan.yaml"), "story: S\n")
			writeFile(t, filepath.Join(projects, "archived", "tasks", "completed", "s", "plan.yaml"), "story: S\n")
			require.NoError(t, os.MkdirAll(filepath.Join(projects, "no-tasks"), 0o755))
			t.Setenv("PANES", "Work:1\tmain\t%1\t"+withPane+"\nWork:2\tsub\t%2\t"+withPane+"/lib\n")

			_, err = newCommands([]string{projects}).snapshot()

			require.NoError(t, err)
			asked := logOf(t, log, "clerk")
			sort.Strings(asked)
			require.Equal(t, []string{
				"clerk story --no-fetch --breakdowns in " + withPane,
				"clerk story --no-fetch --breakdowns in " + filepath.Join(projects, "planned"),
			}, asked)
		})

		t.Run("a project repo with a breakdown and its task record is asked too, and one with a markdown file alone is not", func(t *testing.T) {
			log := withStubs(t)
			projects, err := filepath.EvalSymlinks(t.TempDir())
			require.NoError(t, err)
			writeFile(t, filepath.Join(projects, "decomposed", "tasks", "faster-search.md"), "# Faster search\n")
			writeFile(t, filepath.Join(projects, "decomposed", "tasks", "faster-search.json"), `{"tasks": []}`)
			writeFile(t, filepath.Join(projects, "notes", "tasks", "handoff.md"), "# Handoff\n")

			_, err = newCommands([]string{projects}).snapshot()

			require.NoError(t, err)
			require.Equal(t, []string{"clerk story --no-fetch --breakdowns in " + filepath.Join(projects, "decomposed")}, logOf(t, log, "clerk"))
		})

		t.Run("each story carries the repo it came from", func(t *testing.T) {
			withStubs(t)
			repo := gitRepo(t)
			writeFile(t, filepath.Join(repo, "story.json"), `[{"plan": "p.yaml", "story_slug": "s", "deliverables": []}]`)
			t.Setenv("PANES", "Work:1\tmain\t%1\t"+repo+"\n")

			s, err := newCommands(nil).snapshot()

			require.NoError(t, err)
			require.Len(t, s.plans, 1)
			require.Equal(t, repo, s.plans[0].root)
		})

		t.Run("a pane in a worktree belongs to the main repo of that worktree", func(t *testing.T) {
			withStubs(t)
			repo := gitRepo(t)
			worktree := filepath.Join(repo, ".worktrees", "wt")
			out, err := exec.Command("git", "-C", repo, "worktree", "add", "-q", "-b", "wt", worktree).CombinedOutput()
			require.NoError(t, err, string(out))
			t.Setenv("PANES", "Work:2\twt\t%2\t"+worktree+"/lib\n")
			require.NoError(t, os.MkdirAll(worktree+"/lib", 0o755))

			_, rootOf, _ := newCommands(nil).windows()

			require.Equal(t, map[string]string{worktree + "/lib": repo}, rootOf)
		})

		t.Run("the orchestrator mark of a pane comes with it, one plan for each colon", func(t *testing.T) {
			withStubs(t)
			repo := gitRepo(t)
			t.Setenv("PANES", "Work:4\tmain\t%4\t"+repo+"\t/p/one/plan.yaml:/p/two/plan.yaml\nWork:5\tsub\t%5\t"+repo+"\t\n")

			panes, _, _ := newCommands(nil).windows()

			require.Equal(t, [][]string{{"/p/one/plan.yaml", "/p/two/plan.yaml"}, nil}, [][]string{panes[0].orchestrates, panes[1].orchestrates})
		})

		t.Run("the agents come from workmux, in each repo with a pane", func(t *testing.T) {
			withStubs(t)
			one, two := gitRepo(t), gitRepo(t)
			writeFile(t, filepath.Join(one, "agents.json"), `[{"pane_id": "%1", "status": "waiting"}]`)
			writeFile(t, filepath.Join(two, "agents.json"), `[{"pane_id": "%2", "status": "working", "title": "✳ Other"}]`)
			t.Setenv("PANES", "Work:1\tone\t%1\t"+one+"\nWork:2\ttwo\t%2\t"+two+"\n")

			_, _, agents := newCommands(nil).windows()

			sort.Slice(agents, func(i, j int) bool { return agents[i].Pane < agents[j].Pane })
			require.Equal(t, []agent{{Pane: "%1", Status: "waiting"}, {Pane: "%2", Status: "working", Title: "✳ Other"}}, agents)
		})

		t.Run("a snapshot carries the agents from workmux with the stories", func(t *testing.T) {
			withStubs(t)
			repo := gitRepo(t)
			writeFile(t, filepath.Join(repo, "agents.json"), `[{"pane_id": "%1", "status": "waiting"}]`)
			writeFile(t, filepath.Join(repo, "story.json"), `[{"plan": "p.yaml", "story_slug": "s", "deliverables": []}]`)
			t.Setenv("PANES", "Work:1\tmain\t%1\t"+repo+"\n")

			s, err := newCommands(nil).snapshot()

			require.NoError(t, err)
			require.Equal(t, []agent{{Pane: "%1", Status: "waiting"}}, s.agents)
		})

		t.Run("the features are the stories files with ticket lines, titled by their first heading", func(t *testing.T) {
			root := gitRepo(t)
			writeFile(t, filepath.Join(root, ".scratches/write-user-story/sign-in/sign-in.md"), "intro\n# Sign in\n\n### US-001: Ask\n\n**Ticket:** AGE-1\n")
			writeFile(t, filepath.Join(root, "user-stories/pay.md"), "# Pay\n**Ticket:** AGE-2\n")
			writeFile(t, filepath.Join(root, "user-stories/notes.md"), "# Notes\nno tickets here\n")

			found := newCommands(nil).features(root)

			require.Equal(t, []feature{
				{path: ".scratches/write-user-story/sign-in/sign-in.md", title: "Sign in"},
				{path: "user-stories/pay.md", title: "Pay"},
			}, found)
		})

		t.Run("a project is what clerk project prints for the feature, in its repo", func(t *testing.T) {
			log := withStubs(t)
			root := gitRepo(t)
			writeFile(t, filepath.Join(root, "project.json"), `{"running": ["s/a"], "stories": [{"id": "US-001", "ticket": "AGE-1", "state": "ready"}]}`)

			p, err := newCommands(nil).project(root, "user-stories/pay.md")

			require.NoError(t, err)
			require.Equal(t, []string{"s/a"}, p.Running)
			require.Equal(t, "US-001 AGE-1 ready", p.Stories[0].ID+" "+p.Stories[0].Ticket+" "+p.Stories[0].State)
			require.Equal(t, []string{"clerk project user-stories/pay.md in " + root}, logOf(t, log, "clerk"))
		})

		t.Run("a capture keeps the end of the pane, without the blank lines under it", func(t *testing.T) {
			withStubs(t)

			text := newCommands(nil).capture("%1", 2)

			require.Equal(t, "\nthe question", text)
		})
	})

	t.Run("acting", func(t *testing.T) {
		t.Run("going to a window selects it and switches the client to its session", func(t *testing.T) {
			log := withStubs(t)

			require.NoError(t, newCommands(nil).switchTo("/dev/ttys004", "Work:7"))

			require.Equal(t, []string{"tmux select-window -t Work:7", "tmux switch-client -c /dev/ttys004 -t Work"}, logOf(t, log, "tmux"))
		})

		t.Run("a deliverable opens through deliverable-open, in its own repo", func(t *testing.T) {
			log := withStubs(t)
			repo := gitRepo(t)
			d := &deliverable{ID: "fresh", raw: []byte(`{"id":"fresh"}`), plan: &plan{Slug: "age-1-story", root: repo}}

			text, err := newCommands(nil).open("/dev/ttys004", d)

			require.NoError(t, err)
			require.Equal(t, "starting fresh", text)
			require.Equal(t, []string{
				"deliverable-open arg: --window",
				"deliverable-open arg: --client",
				"deliverable-open arg: /dev/ttys004",
				"deliverable-open arg: age-1-story",
				`deliverable-open arg: {"id":"fresh"}`,
				"deliverable-open in " + repo,
			}, logOf(t, log, "deliverable-open"))
		})

		t.Run("when deliverable-open refuses, the error is the last line it wrote to stderr", func(t *testing.T) {
			withStubs(t)
			t.Setenv("OPEN_REFUSES", "1")
			d := &deliverable{ID: "fresh", raw: []byte(`{}`), plan: &plan{Slug: "s", root: gitRepo(t)}}

			_, err := newCommands(nil).open("", d)

			require.EqualError(t, err, "fresh is blocked by asks")
		})

		t.Run("a window closes with workmux close, in the repo of the deliverable", func(t *testing.T) {
			log := withStubs(t)
			repo := gitRepo(t)

			require.NoError(t, newCommands(nil).closeWindow(repo, "age-8-gone"))

			require.Equal(t, []string{"workmux close age-8-gone in " + repo}, logOf(t, log, "workmux"))
		})

		t.Run("a Claude window opens in the session of the client, with the prompt quoted", func(t *testing.T) {
			log := withStubs(t)
			root := gitRepo(t)

			target, err := newCommands(nil).claudeWindow("/dev/ttys004", root, "age-1-plan", "/deliver-story AGE-1: the story's section")

			require.NoError(t, err)
			require.Equal(t, "Work:age-1-plan", target)
			require.Equal(t, []string{
				"tmux new-window -d -t Work: -n age-1-plan -c " + root,
				`tmux send-keys -t Work:age-1-plan -l claude '/deliver-story AGE-1: the story'\''s section'`,
				"tmux send-keys -t Work:age-1-plan Enter",
			}, logOf(t, log, "tmux"))
		})

		t.Run("a Claude window that is open already is used again", func(t *testing.T) {
			log := withStubs(t)
			t.Setenv("WINDOWS", "zsh\nage-1-plan\n")

			target, err := newCommands(nil).claudeWindow("", gitRepo(t), "age-1-plan", "/deliver-story AGE-1")

			require.NoError(t, err)
			require.Equal(t, "Work:age-1-plan", target)
			require.Empty(t, logOf(t, log, "tmux"))
		})

		t.Run("a start runs deliverable-open in a background window, with gears when asked", func(t *testing.T) {
			log := withStubs(t)
			repo := gitRepo(t)
			d := &deliverable{ID: "next", raw: []byte(`{"id":"next"}`), plan: &plan{Slug: "age-3-story", root: repo}}

			text, err := newCommands(nil).start(d, true)

			require.NoError(t, err)
			require.Equal(t, "starting fresh", text)
			require.Equal(t, []string{
				"deliverable-open arg: --window",
				"deliverable-open arg: --background",
				"deliverable-open arg: --gears",
				"deliverable-open arg: age-3-story",
				`deliverable-open arg: {"id":"next"}`,
				"deliverable-open in " + repo,
			}, logOf(t, log, "deliverable-open"))
		})

		t.Run("an archive passes --force only when asked", func(t *testing.T) {
			log := withStubs(t)
			repo := gitRepo(t)
			c := newCommands(nil)

			require.NoError(t, c.archive(repo, "/p/one.yaml", false))
			require.NoError(t, c.archive(repo, "/p/two.yaml", true))

			require.Equal(t, []string{
				"clerk story archive /p/one.yaml --no-fetch in " + repo,
				"clerk story archive /p/two.yaml --no-fetch --force in " + repo,
			}, logOf(t, log, "clerk"))
		})
	})
}
