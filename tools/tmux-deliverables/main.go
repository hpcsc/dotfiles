// tmux-deliverables shows the deliverables of each story under way, in every repo with
// a tmux pane and every repo under the project roots with a live plan. Each story is a
// heading over its deliverables: the state from `clerk story`, the PR, the tmux window
// that holds the worktree, the state of the agent in that window, and what the
// deliverable needs from a person. Windows with an agent and no deliverable come last.
//
//	tmux-deliverables popup <client>    open it in a tmux popup on that client
//	tmux-deliverables [--client <name>] run it in this terminal
//
// TMUX_DELIVERABLES_ROOTS sets the project roots, separated by colons. The default is
// ~/Workspace/Code and ~/Personal/Code.
package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	extendPath()
	if len(os.Args) == 3 && os.Args[1] == "popup" {
		if err := openPopup(os.Args[2]); err != nil {
			fmt.Fprintln(os.Stderr, "tmux-deliverables:", err)
			os.Exit(1)
		}
		return
	}
	client := flag.String("client", "", "the tmux client to switch when you go to a window")
	flag.Parse()

	program := tea.NewProgram(newBoardView(newCommands(projectRoots()), *client), tea.WithAltScreen())
	if _, err := program.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "tmux-deliverables:", err)
		os.Exit(1)
	}
}

func openPopup(client string) error {
	self, err := os.Executable()
	if err != nil {
		return err
	}
	return exec.Command("tmux", "display-popup", "-c", client, "-E", "-w", "92%", "-h", "85%",
		"-T", " Deliverables ", fmt.Sprintf("'%s' --client '%s'", self, client)).Run()
}

func projectRoots() []string {
	if roots := os.Getenv("TMUX_DELIVERABLES_ROOTS"); roots != "" {
		return strings.Split(roots, ":")
	}
	home, _ := os.UserHomeDir()
	return []string{filepath.Join(home, "Workspace", "Code"), filepath.Join(home, "Personal", "Code")}
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
