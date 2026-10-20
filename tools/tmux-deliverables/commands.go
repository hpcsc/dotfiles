package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
)

var _ runner = (*commands)(nil)

// commands runs tmux, git, clerk, workmux and deliverable-open, the way a person does
// from a shell.
type commands struct {
	// projectRoots hold one repo in each folder. A repo there with a live plan is read
	// even when no pane is in it, because a story is under way before its first window.
	projectRoots []string
}

func newCommands(projectRoots []string) *commands {
	return &commands{projectRoots: projectRoots}
}

func (c *commands) snapshot() (snapshot, error) {
	panes, rootOf, agents := c.windows()
	seen := map[string]bool{}
	var repos []string
	for _, root := range rootOf {
		if !seen[root] {
			seen[root] = true
			repos = append(repos, root)
		}
	}
	for _, root := range c.reposWithPlans() {
		if !seen[root] {
			seen[root] = true
			repos = append(repos, root)
		}
	}
	sort.Strings(repos)

	plansOf := make([][]*plan, len(repos))
	var wg sync.WaitGroup
	for i, root := range repos {
		wg.Add(1)
		go func() {
			defer wg.Done()
			plansOf[i] = storiesIn(root)
		}()
	}
	wg.Wait()

	s := snapshot{panes: panes, rootOf: rootOf, agents: agents}
	for _, plans := range plansOf {
		s.plans = append(s.plans, plans...)
	}
	return s, nil
}

func (c *commands) windows() ([]pane, map[string]string, []agent) {
	out, err := run("", "tmux", "list-panes", "-a", "-F",
		"#{session_name}:#{window_index}\t#{window_name}\t#{pane_id}\t#{pane_current_path}")
	if err != nil {
		return nil, map[string]string{}, nil
	}
	var panes []pane
	rootOf := map[string]string{}
	looked := map[string]bool{}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		f := strings.Split(line, "\t")
		if len(f) != 4 {
			continue
		}
		panes = append(panes, pane{window: f[0], name: f[1], id: f[2], path: f[3]})
		if !looked[f[3]] {
			looked[f[3]] = true
			if root := mainRoot(f[3]); root != "" {
				rootOf[f[3]] = root
			}
		}
	}

	seen := map[string]bool{}
	var roots []string
	for _, root := range rootOf {
		if !seen[root] {
			seen[root] = true
			roots = append(roots, root)
		}
	}
	agentsOf := make([][]agent, len(roots))
	var wg sync.WaitGroup
	for i, root := range roots {
		wg.Add(1)
		go func() {
			defer wg.Done()
			out, err := run(root, "workmux", "status", "--json")
			if err == nil {
				_ = json.Unmarshal(out, &agentsOf[i])
			}
		}()
	}
	wg.Wait()
	var agents []agent
	for _, a := range agentsOf {
		agents = append(agents, a...)
	}
	return panes, rootOf, agents
}

// reposWithPlans are the repos under the project roots with a plan outside tasks/completed/.
func (c *commands) reposWithPlans() []string {
	var repos []string
	for _, root := range c.projectRoots {
		entries, err := os.ReadDir(root)
		if err != nil {
			continue
		}
		for _, e := range entries {
			dir := filepath.Join(root, e.Name())
			if e.IsDir() && hasLivePlan(filepath.Join(dir, "tasks")) {
				if real, err := filepath.EvalSymlinks(dir); err == nil {
					repos = append(repos, real)
				}
			}
		}
	}
	return repos
}

func hasLivePlan(tasks string) bool {
	found := errors.New("found")
	err := filepath.WalkDir(tasks, func(path string, e os.DirEntry, err error) error {
		switch {
		case err != nil:
			return filepath.SkipDir
		case e.IsDir() && e.Name() == "completed":
			return filepath.SkipDir
		case !e.IsDir() && (e.Name() == "plan.yaml" || e.Name() == "plan.yml"):
			return found
		}
		return nil
	})
	return errors.Is(err, found)
}

// storiesIn asks clerk for the stories of one repo. `--no-fetch` because a PR merged on
// GitHub reaches clerk through gh, and a fetch on each read costs seconds.
func storiesIn(root string) []*plan {
	out, err := run(root, "clerk", "story", "--no-fetch")
	if err != nil {
		return nil
	}
	var plans []*plan
	if json.Unmarshal(out, &plans) != nil {
		return nil
	}
	for _, p := range plans {
		p.root = root
	}
	return plans
}

func mainRoot(path string) string {
	out, err := run(path, "git", "rev-parse", "--path-format=absolute", "--git-common-dir")
	if err != nil {
		return ""
	}
	return filepath.Dir(strings.TrimSpace(string(out)))
}

func (c *commands) capture(pane string, lines int) string {
	out, err := run("", "tmux", "capture-pane", "-ep", "-t", pane)
	if err != nil {
		return ""
	}
	return lastLines(string(out), lines)
}

func (c *commands) readFile(path string, lines int) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	var b strings.Builder
	scanner := bufio.NewScanner(f)
	for n := 0; n < lines && scanner.Scan(); n++ {
		b.WriteString(scanner.Text() + "\n")
	}
	return b.String()
}

func (c *commands) switchTo(client, target string) error {
	if _, err := run("", "tmux", "select-window", "-t", target); err != nil {
		return err
	}
	session, _, _ := strings.Cut(target, ":")
	args := []string{"switch-client", "-t", session}
	if client != "" {
		args = []string{"switch-client", "-c", client, "-t", session}
	}
	_, err := run("", "tmux", args...)
	return err
}

func (c *commands) open(client string, d *deliverable) (string, error) {
	args := []string{"--window"}
	if client != "" {
		args = append(args, "--client", client)
	}
	args = append(args, d.plan.Slug, string(d.raw))
	out, err := run(d.plan.root, "deliverable-open", args...)
	return lastLine(string(out)), err
}

func (c *commands) openURL(url string) error {
	opener := "xdg-open"
	if runtime.GOOS == "darwin" {
		opener = "open"
	}
	_, err := run("", opener, url)
	return err
}

func (c *commands) closeWindow(root, handle string) error {
	_, err := run(root, "workmux", "close", handle)
	return err
}

func (c *commands) archive(root, planPath string, force bool) error {
	args := []string{"story", "archive", planPath, "--no-fetch"}
	if force {
		args = append(args, "--force")
	}
	_, err := run(root, "clerk", args...)
	return err
}

// run returns stdout. On a failure the error carries the last line the program wrote to
// stderr, which is where clerk, workmux and deliverable-open say why.
func run(dir, name string, args ...string) ([]byte, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err == nil {
		return out, nil
	}
	if line := firstOf(lastLine(stderr.String()), lastLine(string(out))); line != "" {
		return out, errors.New(line)
	}
	return out, err
}

func lastLine(text string) string {
	lines := strings.Split(strings.TrimRight(text, "\n "), "\n")
	return strings.TrimSpace(lines[len(lines)-1])
}

// lastLines keeps the last `n` lines, without the blank lines under the text.
func lastLines(text string, n int) string {
	lines := strings.Split(strings.TrimRight(text, "\n "), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}
