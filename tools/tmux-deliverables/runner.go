package main

// runner reads the windows, agents and stories, and acts on them. The views call it
// from commands, away from the update loop, because each call starts other programs.
type runner interface {
	// snapshot reads everything: the panes, the agents and every story under way.
	snapshot() (snapshot, error)
	// windows reads the part that changes from second to second: the panes and the agents.
	windows() ([]pane, map[string]string, []agent)
	capture(pane string, lines int) string
	readFile(path string, lines int) string
	switchTo(client, target string) error
	// open opens or starts a deliverable that has no window, and says what it did.
	open(client string, d *deliverable) (string, error)
	openURL(url string) error
	closeWindow(root, handle string) error
	archive(root, planPath string, force bool) error

	// features are the stories files of a repo: a Markdown file with **Ticket:** lines.
	features(root string) []feature
	// project is what `clerk project` says of the stories of one feature.
	project(root, feature string) (project, error)
	// claudeWindow opens a window named `name` in the session of the client, with Claude
	// started on `prompt`, unless one with that name is open already. It returns the target.
	claudeWindow(client, root, name, prompt string) (string, error)
	// start starts a deliverable in a background window, and says what it did.
	start(d *deliverable, gears bool) (string, error)
}
