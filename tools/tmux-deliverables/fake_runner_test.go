package main

import (
	"encoding/json"
	"fmt"
	"strings"
)

// fakeRunner answers with a fixed snapshot and records each action.
type fakeRunner struct {
	snap     snapshot
	captured map[string]string // pane -> its text
	files    map[string]string
	openText string
	openErr  error
	fails    error // what closeWindow and archive return
	calls    []string

	featureList []feature
	planned     project
}

func (f *fakeRunner) snapshot() (snapshot, error) {
	f.calls = append(f.calls, "snapshot")
	return f.snap, nil
}

func (f *fakeRunner) windows() ([]pane, map[string]string, []agent) {
	f.calls = append(f.calls, "windows")
	return f.snap.panes, f.snap.rootOf, f.snap.agents
}

func (f *fakeRunner) capture(pane string, _ int) string  { return f.captured[pane] }
func (f *fakeRunner) readFile(path string, _ int) string { return f.files[path] }
func (f *fakeRunner) openURL(url string) error           { f.record("open " + url); return nil }
func (f *fakeRunner) closeWindow(root, handle string) error {
	f.record("close " + handle + " in " + root)
	return f.fails
}
func (f *fakeRunner) switchTo(client, target string) error {
	f.record("switch " + client + " to " + target)
	return nil
}
func (f *fakeRunner) record(call string) { f.calls = append(f.calls, call) }

func (f *fakeRunner) open(client string, d *deliverable) (string, error) {
	f.record(fmt.Sprintf("deliverable-open %s %s in %s", client, d.ID, d.plan.root))
	return f.openText, f.openErr
}

func (f *fakeRunner) archive(root, planPath string, force bool) error {
	f.record(fmt.Sprintf("archive %s in %s force=%t", planPath, root, force))
	return f.fails
}

func (f *fakeRunner) features(string) []feature { return f.featureList }

func (f *fakeRunner) project(root, feature string) (project, error) {
	f.calls = append(f.calls, "project "+feature+" in "+root)
	return f.planned, nil
}

func (f *fakeRunner) claudeWindow(client, root, name, prompt string) (string, error) {
	f.record(fmt.Sprintf("claude window %s in %s: %s", name, root, prompt))
	return "Work:" + name, nil
}

func (f *fakeRunner) start(d *deliverable, gears bool) (string, error) {
	f.record(fmt.Sprintf("start %s in %s gears=%t", d.ID, d.plan.root, gears))
	return "started " + d.ID, nil
}

// actions are the calls that change something, without the reads.
func (f *fakeRunner) actions() []string {
	var acts []string
	for _, c := range f.calls {
		if c != "snapshot" && c != "windows" && !strings.HasPrefix(c, "project ") {
			acts = append(acts, c)
		}
	}
	return acts
}

func deliverableJSON(id, state string, done, total int, more ...any) map[string]any {
	d := map[string]any{
		"id": id, "state": state, "done": done, "total": total, "wave": 1, "handle": "h-" + id,
		"branch": "br-" + id, "tasks_file": "/tasks/" + id + ".md", "blocked_by": []string{},
	}
	for i := 0; i+1 < len(more); i += 2 {
		d[more[i].(string)] = more[i+1]
	}
	return d
}

func prJSON(number int, state string, draft bool, review, checks string) map[string]any {
	return map[string]any{"number": number, "state": state, "draft": draft, "review": review, "checks": checks,
		"url": fmt.Sprintf("https://example.test/pull/%d", number)}
}

func planIn(root, ticket, slug string, deliverables ...map[string]any) *plan {
	p := &plan{Path: root + "/tasks/" + slug + "/plan.yaml", Story: "The story " + slug, Slug: slug, Ticket: ticket, root: root}
	for _, d := range deliverables {
		raw, err := json.Marshal(d)
		if err != nil {
			panic(err)
		}
		p.Deliverables = append(p.Deliverables, raw)
	}
	return p
}

// inWorktree is a pane in the worktree that clerk reports for a deliverable.
func inWorktree(window, id, root, deliverable string) pane {
	return pane{window: window, name: deliverable, id: id, path: root + "/.worktrees/" + deliverable}
}

func worktreeOf(root, deliverable string) string { return root + "/.worktrees/" + deliverable }

func newFake(plans []*plan, panes []pane, agents ...agent) *fakeRunner {
	rootOf := map[string]string{}
	for _, p := range panes {
		if root, _, ok := strings.Cut(strings.TrimPrefix(p.path, "/repos/"), "/"); ok || strings.HasPrefix(p.path, "/repos/") {
			rootOf[p.path] = "/repos/" + root
		}
	}
	return &fakeRunner{snap: snapshot{panes: panes, rootOf: rootOf, plans: plans, agents: agents},
		captured: map[string]string{}, files: map[string]string{}}
}
