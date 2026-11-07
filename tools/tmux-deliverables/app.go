package main

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
)

type viewID int

const (
	boardID viewID = iota
	plannerID
)

// routed carries a message to the view whose command made it. Both views use the same
// message types, so a result for one view must not reach the other.
type routed struct {
	to  viewID
	msg tea.Msg
}

// app shows one view at a time, under a bar that names both: the board of the stories
// under way, or the planner of the features of one repo. Tab switches between them.
type app struct {
	board      boardView
	planner    plannerView
	hasPlanner bool // false when the popup did not start in a git repo
	active     viewID
	width      int
	// bothStarted turns true at the first switch, which starts the other view.
	bothStarted bool
}

func newApp(board boardView, planner plannerView, hasPlanner bool, active viewID) app {
	return app{board: board, planner: planner, hasPlanner: hasPlanner, active: active}
}

func (a app) Init() tea.Cmd {
	if a.active == plannerID {
		return route(plannerID, a.planner.Init())
	}
	return route(boardID, a.board.Init())
}

func (a app) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		a.width = msg.Width
		under := tea.WindowSizeMsg{Width: msg.Width, Height: msg.Height - 1}
		next, _ := a.board.Update(under)
		a.board = next.(boardView)
		a.planner, _ = a.planner.Update(under)
		return a, nil
	case routed:
		return a.to(msg.to, msg.msg)
	case tea.KeyMsg:
		boardTakesKeys := !a.board.filtering && a.board.ask == nil
		switch {
		case msg.String() == "tab" && boardTakesKeys:
			return a.switchView()
		case msg.String() == "f" && a.active == boardID && boardTakesKeys:
			return a.toFeature()
		case msg.String() == "u" && a.active == plannerID && a.planner.screen == storyScreen:
			return a.toBoard()
		}
	}
	return a.to(a.active, msg)
}

// toFeature opens, in the planner, the feature of the story under the cursor on the board.
func (a app) toFeature() (tea.Model, tea.Cmd) {
	ref, ok := a.board.storyRef()
	if !ok {
		a.board.message = "f opens the feature of a story: put the cursor on a story or a deliverable"
		return a, nil
	}
	var cmd tea.Cmd
	a.planner, cmd = a.planner.find(ref)
	a.hasPlanner, a.active = true, plannerID
	if !a.bothStarted {
		a.bothStarted = true
		cmd = tea.Batch(cmd, a.planner.tick())
	}
	return a, route(plannerID, cmd)
}

// toBoard puts the cursor of the board on the story under the cursor in the planner.
func (a app) toBoard() (tea.Model, tea.Cmd) {
	ref, ok := a.planner.storyRef()
	if !ok {
		a.planner.message = "u goes to a story under way: put the cursor on a story"
		return a, nil
	}
	a.active = boardID
	var cmd tea.Cmd
	if !a.bothStarted {
		a.bothStarted = true
		cmd = a.board.Init()
	}
	a.board = a.board.find(ref)
	return a, route(boardID, tea.Batch(cmd, a.board.readPreview()))
}

func (a app) to(id viewID, msg tea.Msg) (tea.Model, tea.Cmd) {
	if id == plannerID {
		var cmd tea.Cmd
		a.planner, cmd = a.planner.Update(msg)
		return a, route(plannerID, cmd)
	}
	next, cmd := a.board.Update(msg)
	a.board = next.(boardView)
	return a, route(boardID, cmd)
}

func (a app) switchView() (tea.Model, tea.Cmd) {
	if !a.hasPlanner {
		a.board.message = "the planner needs a git repo: open the popup from a pane in one"
		return a, nil
	}
	a.active = boardID + plannerID - a.active
	if a.bothStarted {
		return a, nil
	}
	a.bothStarted = true
	if a.active == plannerID {
		return a, route(plannerID, a.planner.Init())
	}
	return a, route(boardID, a.board.Init())
}

func (a app) View() string {
	view := a.board.View()
	if a.active == plannerID {
		view = a.planner.View()
	}
	return ansi.Truncate(tabBar(a.active), a.width, "…") + "\n" + view
}

func tabBar(active viewID) string {
	tabs := []string{"under way", "features"}
	for i, name := range tabs {
		if viewID(i) == active {
			tabs[i] = bold.Render("[" + name + "]")
		} else {
			tabs[i] = dimmed.Render(" " + name + " ")
		}
	}
	return strings.Join(tabs, " ") + dimmed.Render("   tab switches")
}

// route tags each message that a command makes with the view it belongs to. A batch is
// tagged command by command; a quit stays a quit.
func route(to viewID, cmd tea.Cmd) tea.Cmd {
	if cmd == nil {
		return nil
	}
	return func() tea.Msg {
		switch msg := cmd().(type) {
		case nil:
			return nil
		case tea.BatchMsg:
			cmds := make(tea.BatchMsg, len(msg))
			for i, c := range msg {
				cmds[i] = route(to, c)
			}
			return cmds
		case tea.QuitMsg:
			return msg
		default:
			return routed{to, msg}
		}
	}
}
