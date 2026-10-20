package main

import tea "github.com/charmbracelet/bubbletea"

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

// app shows one view at a time: the board of the stories under way, or the planner of
// the features of one repo. Tab switches between them.
type app struct {
	board      boardView
	planner    plannerView
	hasPlanner bool // false when the popup did not start in a git repo
	active     viewID
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
		next, _ := a.board.Update(msg)
		a.board = next.(boardView)
		a.planner, _ = a.planner.Update(msg)
		return a, nil
	case routed:
		return a.to(msg.to, msg.msg)
	case tea.KeyMsg:
		if msg.String() == "tab" && !a.board.filtering && a.board.ask == nil {
			return a.switchView()
		}
	}
	return a.to(a.active, msg)
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
	if a.active == plannerID {
		return a.planner.View()
	}
	return a.board.View()
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
