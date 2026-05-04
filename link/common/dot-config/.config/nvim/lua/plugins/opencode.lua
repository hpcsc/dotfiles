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
	end,
	keys = {
		{ "<leader>a", nil, desc = "AI" },
		{
			"<leader>ao",
			function()
				require("opencode").toggle()
			end,
			desc = "Toggle AI panel",
		},
		{
			"<leader>af",
			function()
				require("opencode").toggle()
			end,
			desc = "Focus AI panel",
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
