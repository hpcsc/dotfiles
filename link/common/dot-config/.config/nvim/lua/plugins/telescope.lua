return {
	"nvim-telescope/telescope.nvim",
	tag = "v0.2.0",
	opts = function()
		local actions = require("telescope.actions")
		return {
			defaults = {
				path_display = {
					shorten = {
						len = 1,
						exclude = { -3, -2, -1 }, -- display first character of each directory, except for the last 3
					},
				},
				mappings = {
					i = { ["<C-c>"] = actions.close },
					n = { ["q"] = actions.close },
				},
			},
			pickers = {
				find_files = {
					find_command = { "rg", "--files", "--hidden", "-g", "!**/.git/*" },
				},
				live_grep = {
					additional_args = { "--hidden", "-g", "!**/.git/*" },
				},
			},
		}
	end,
	config = function(_, opts)
		require("telescope").setup(opts)
		require("telescope").load_extension("zf-native")
	end,
	dependencies = {
		{ "nvim-lua/plenary.nvim", lazy = true },
	},
	keys = function()
		local lazy_telescope = function(builtin)
			return function(...)
				require("telescope.builtin")[builtin](...)
			end
		end

		return {
			{ "<leader>ff", lazy_telescope("find_files"), desc = "Telescope find files" },
			{ "<leader>fg", lazy_telescope("live_grep"), desc = "Telescope find files by content" },
			{ "<leader>fb", lazy_telescope("buffers"), desc = "Telescope find buffers" },
			{ "<leader>fh", lazy_telescope("help_tags"), desc = "Telescope find help tags" },
		}
	end,
}
