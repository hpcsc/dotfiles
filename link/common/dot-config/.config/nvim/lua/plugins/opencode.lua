-- Enabled only when NVIM_OPENCODE=1 is set in the environment.
-- snacks.nvim is already pulled in by claudecode.nvim; reused here.
return {
	"NickvanDyke/opencode.nvim",
	enabled = function()
		return vim.env.NVIM_OPENCODE == "1"
	end,
	dependencies = { "folke/snacks.nvim" },
	config = function()
		vim.g.opencode_opts = {}
		-- opencode writes to disk; let Neovim pick up external changes
		vim.o.autoread = true

		-- vim-tmux-navigator's global tnoremap <C-j> swallows opencode's
		-- newline key; this buffer-local map shadows it and sends the key
		-- through to the terminal instead.
		vim.api.nvim_create_autocmd("TermOpen", {
			pattern = "term://*:opencode*",
			callback = function(ev)
				vim.keymap.set("t", "<C-j>", "<C-j>", {
					buffer = ev.buf,
					desc = "Insert newline (passthrough)",
				})
			end,
		})
	end,
	keys = {
		{ "<leader>a", nil, desc = "AI" },
		{
			"<leader>ao",
			function()
				require("opencode").start()
			end,
			desc = "Start OpenCode server",
		},
		{
			"<leader>aa",
			function()
				require("opencode").ask()
			end,
			desc = "Ask AI",
		},
		{
			"<leader>as",
			function()
				require("opencode").ask("@this: ", { submit = true })
			end,
			mode = { "n", "v" },
			desc = "Send selection to AI",
		},
		{
			"<leader>ap",
			function()
				require("opencode").prompt()
			end,
			desc = "Prompt AI (with context)",
		},
		{
			"<leader>aS",
			function()
				require("opencode").select()
			end,
			desc = "Select AI prompt/command",
		},
		{
			"<leader>an",
			function()
				require("opencode").command("session.new")
			end,
			desc = "New AI session",
		},
	},
}
