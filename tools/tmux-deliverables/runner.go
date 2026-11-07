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

	// features are what `feature list` prints for a repo: each proposal, and each stories
	// file that names no proposal.
	features(root string) ([]feature, error)
	// feature is what `feature <path>` prints for one feature.
	feature(root, path string) (feature, error)
	// claudeWindow opens a window named `name` in the session of the client, with Claude
	// started on `prompt`, unless one with that name is open already. It returns the target.
	claudeWindow(client, root, name, prompt string) (string, error)
	// start starts a deliverable in a background window, and says what it did.
	start(d *deliverable, gears bool) (string, error)
}
