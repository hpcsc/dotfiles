return {
	"nvim-telescope/telescope.nvim",
	tag = "0.1.8",
	opts = {
		pickers = {
			find_files = {
				find_command = { "rg", "--files", "--hidden", "-g", "!.git" },
			},
		},
		extensions = { "fzf" },
	},
	dependencies = {
		{ "nvim-lua/plenary.nvim", lazy = true },
	},

	init = function()
		local builtin = require("telescope.builtin")
		vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Telescope find files" })
		vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Telescope live grep" })
		vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Telescope buffers" })
		vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Telescope help tags" })
		vim.keymap.set("n", "<leader>;", function()
			require("yazi").yazi()
		end)
	end,
}
