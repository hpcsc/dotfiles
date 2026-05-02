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
		{ "<leader>o", nil, desc = "AI/opencode" },
		{
			"<leader>oo",
			function()
				require("opencode").toggle()
			end,
			desc = "Toggle opencode",
		},
		{
			"<leader>oa",
			function()
				require("opencode").ask()
			end,
			desc = "Ask opencode",
		},
		{
			"<leader>oA",
			function()
				require("opencode").ask("@this: ", { submit = true })
			end,
			mode = { "n", "v" },
			desc = "Ask opencode about this",
		},
		{
			"<leader>op",
			function()
				require("opencode").prompt()
			end,
			desc = "Prompt opencode (with context)",
		},
		{
			"<leader>os",
			function()
				require("opencode").select()
			end,
			desc = "Select opencode prompt/command",
		},
		{
			"<leader>on",
			function()
				require("opencode").command("session.new")
			end,
			desc = "New opencode session",
		},
	},
}
