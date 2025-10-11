local wezterm = require("wezterm")
local mux = wezterm.mux

function file_exists(file_path)
	local f = io.open(file_path, "r")
	if f ~= nil then
		io.close(f)
		return true
	else
		return false
	end
end

wezterm.on("gui-attached", function(domain)
	local is_work_machine = file_exists(os.getenv("HOME") .. "/.gitconfig-work")
	local workspace = mux.get_active_workspace()
	for _, window in ipairs(mux.all_windows()) do
		if window:get_workspace() == workspace then
			if is_work_machine then
				window:active_pane():send_text("tmux new-session -As Work -c ~/Workspace/Code\n")
			else
				window:active_pane():send_text("tmux new-session -As Personal -c ~/Personal/Code\n")
			end
		end
	end
end)

local config = wezterm.config_builder()
require("custom").apply_to_config(config)
return config
