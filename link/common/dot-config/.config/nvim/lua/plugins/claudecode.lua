-- Enabled only when NVIM_CLAUDECODE=1 is set in the environment.
return {
	"coder/claudecode.nvim",
	enabled = function()
		return vim.env.NVIM_CLAUDECODE == "1"
	end,
	dependencies = { "folke/snacks.nvim" },
	opts = {
		diff_opts = {
			open_in_new_tab = true,
			keep_terminal_focus = true,
		},
		terminal = {
			snacks_win_opts = {
				keys = {
					term_normal = false,
					-- vim-tmux-navigator's global tnoremap <C-j> swallows Claude
					-- Code's newline key; this buffer-local expr map shadows it and
					-- sends the key through to the terminal instead.
					claude_newline = {
						"<C-j>",
						function()
							return "<C-j>"
						end,
						mode = "t",
						expr = true,
						desc = "Insert newline (passthrough)",
					},
				},
			},
		},
	},
	cmd = {
		"ClaudeCode",
		"ClaudeCodeFocus",
		"ClaudeCodeSend",
		"ClaudeCodeDiffAccept",
		"ClaudeCodeDiffDeny",
	},
	keys = {
		{ "<leader>a", nil, desc = "AI" },
		{ "<leader>ao", "<cmd>ClaudeCode<cr>", desc = "Toggle AI panel" },
		{ "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus AI panel" },
		{ "<leader>aa", "<cmd>ClaudeCode<cr>", desc = "Ask AI" },
		{ "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send selection to AI" },
		{ "<leader>ay", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
		{ "<leader>aN", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny diff" },
	},
}
