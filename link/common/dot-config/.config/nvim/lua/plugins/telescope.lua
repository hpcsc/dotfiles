return {
	"nvim-telescope/telescope.nvim",
	tag = "v0.2.0",
	opts = function()
		local actions = require("telescope.actions")
		return {
			defaults = {
				path_display = {
					filename_first = {
						reverse_directories = false,
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
			extensions = {
				live_grep_args = {
					mappings = {
						i = {
							["<C-k>"] = require("telescope-live-grep-args.actions").quote_prompt(),
						},
					},
				},
			},
		}
	end,
	config = function(_, opts)
		require("telescope").setup(opts)
		require("telescope").load_extension("zf-native")
		require("telescope").load_extension("live_grep_args")
	end,
	dependencies = {
		{ "nvim-lua/plenary.nvim", lazy = true },
		{ "nvim-telescope/telescope-live-grep-args.nvim", lazy = true },
	},
	keys = function()
		local lazy_telescope = function(builtin)
			return function(...)
				require("telescope.builtin")[builtin](...)
			end
		end

		return {
			{ "<leader>ff", lazy_telescope("find_files"), desc = "Telescope find files" },
			{ "<leader>fg", function()
				require("telescope").extensions.live_grep_args.live_grep_args()
			end, desc = "Telescope live grep (args)" },
			{ "<leader>fb", lazy_telescope("buffers"), desc = "Telescope find buffers" },
			{ "<leader>fh", lazy_telescope("help_tags"), desc = "Telescope find help tags" },
			{ "<leader>fc", lazy_telescope("git_bcommits"), desc = "Telescope git commits for buffer" },
			{ "<leader>?", lazy_telescope("keymaps"), desc = "Telescope keymaps" },
		}
	end,
}
