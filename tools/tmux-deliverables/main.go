// tmux-deliverables shows the deliverables of the stories in flight, in two views.
//
// The board shows each story under way, in every repo with a tmux pane and every repo
// under the project roots with a live story: a plan, or a breakdown that no plan holds.
// Each story is a heading over its deliverables, and a breakdown is the one deliverable of
// its story. A row shows the state from `clerk story`, the PR, the tmux window that holds
// the worktree, the state of the agent in that window, and what the deliverable needs from
// a person. Windows with an agent and no deliverable come last.
//
// The planner shows the features of the repo of the pane: each stories file, the stories
// in it with their state from `clerk project`, and the deliverables of each story. There
// a story is planned, taken through its gate, and started. Tab switches the view.
//
//	tmux-deliverables popup <client> [<pane path>] [--features]
//	    open it in a tmux popup on that client; --features opens the planner first
//	tmux-deliverables [--client <name>] [--path <dir>] [--features]
//	    run it in this terminal
//
// TMUX_DELIVERABLES_ROOTS sets the project roots, separated by colons; the default is
// ~/Workspace/Code and ~/Personal/Code. TMUX_DELIVERABLES_LIMIT is the number of runs at
// the same time that the planner shows beside the runs under way; the default is 2.
package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	extendPath()
	if len(os.Args) >= 3 && os.Args[1] == "popup" {
		path, features := ".", false
		for _, arg := range os.Args[3:] {
			if arg == "--features" {
				features = true
			} else {
				path = arg
			}
		}
		if err := openPopup(os.Args[2], path, features); err != nil {
			fmt.Fprintln(os.Stderr, "tmux-deliverables:", err)
			os.Exit(1)
		}
		return
	}
	client := flag.String("client", "", "the tmux client to switch when you go to a window")
	path := flag.String("path", ".", "a folder in the repo whose features the planner shows")
	features := flag.Bool("features", false, "open the planner first")
	flag.Parse()

	run := newCommands(projectRoots())
	root := mainRoot(*path)
	active := boardID
	if *features {
		if root == "" {
			fmt.Fprintln(os.Stderr, "tmux-deliverables: no git repo at", *path)
			os.Exit(1)
		}
		active = plannerID
	}
	a := newApp(newBoardView(run, *client), newPlannerView(run, *client, root, limit()), root != "", active)
	if _, err := tea.NewProgram(a, tea.WithAltScreen()).Run(); err != nil {
		fmt.Fprintln(os.Stderr, "tmux-deliverables:", err)
		os.Exit(1)
	}
}

func openPopup(client, path string, features bool) error {
	self, err := os.Executable()
	if err != nil {
		return err
	}
	command := fmt.Sprintf("%s --client %s --path %s", quoted(self), quoted(client), quoted(path))
	if features {
		command += " --features"
	}
	return exec.Command("tmux", "display-popup", "-c", client, "-d", path, "-E", "-w", "92%", "-h", "85%",
		"-T", " Deliverables ", command).Run()
}

func quoted(s string) string { return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'" }

func projectRoots() []string {
	if roots := os.Getenv("TMUX_DELIVERABLES_ROOTS"); roots != "" {
		return strings.Split(roots, ":")
	}
	home, _ := os.UserHomeDir()
	return []string{filepath.Join(home, "Workspace", "Code"), filepath.Join(home, "Personal", "Code")}
}

func limit() int {
	if n, err := strconv.Atoi(os.Getenv("TMUX_DELIVERABLES_LIMIT")); err == nil && n > 0 {
		return n
	}
	return 2
}

// extendPath adds the tool folders that a tmux key binding lacks: the tmux server's PATH
// has no mise shims, no ~/.local/bin and no Homebrew. They go last, so that a caller's
// own PATH still decides.
func extendPath() {
	home, _ := os.UserHomeDir()
	dirs := []string{
		filepath.Join(home, ".local", "share", "mise", "shims"),
		filepath.Join(home, ".local", "bin"),
		"/opt/homebrew/bin",
	}
	path := os.Getenv("PATH")
	for _, d := range dirs {
		if _, err := os.Stat(d); err == nil {
			path += string(os.PathListSeparator) + d
		}
	}
	os.Setenv("PATH", path)
}
