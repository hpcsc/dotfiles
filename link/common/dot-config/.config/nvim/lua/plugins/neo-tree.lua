return {
	"nvim-neo-tree/neo-tree.nvim",
	branch = "v3.x",

	cmd = "Neotree",

	keys = {
		{ "<leader>t", "<cmd>Neotree toggle<cr>", desc = "Neo-tree toggle" },
		{ "<leader>m", "<cmd>Neotree reveal<cr>", desc = "Neo-tree reveal current file" },
	},

	-- `nvim <dir>` should open neo-tree as a left sidebar next to an empty
	-- buffer, not full-window netrw. neo-tree is lazy-loaded, so nothing
	-- hijacks the directory on startup unless we trigger it here; the
	-- `:Neotree` call below loads the plugin on demand.
	init = function()
		vim.api.nvim_create_autocmd("StdinReadPre", {
			callback = function()
				vim.g.neotree_stdin = true
			end,
		})

		vim.api.nvim_create_autocmd("VimEnter", {
			callback = function()
				local first = vim.fn.argv(0)
				if
					vim.fn.argc() == 1
					and type(first) == "string"
					and vim.fn.isdirectory(first) == 1
					and not vim.g.neotree_stdin
				then
					vim.cmd("enew")
					vim.cmd("Neotree show left dir=" .. vim.fn.fnameescape(vim.fn.fnamemodify(first, ":p")))
					-- neo-tree grabs focus as it opens (async); hand it back to
					-- the empty editor buffer so the cursor starts there.
					vim.schedule(function()
						for _, w in ipairs(vim.api.nvim_list_wins()) do
							if vim.bo[vim.api.nvim_win_get_buf(w)].filetype ~= "neo-tree" then
								vim.api.nvim_set_current_win(w)
								break
							end
						end
					end)
				end
			end,
		})
	end,

	dependencies = {
		{ "nvim-lua/plenary.nvim", lazy = true },
		{ "MunifTanjim/nui.nvim", lazy = true },
		{ "nvim-tree/nvim-web-devicons", lazy = true },
	},

	opts = {
		close_if_last_window = true,
		popup_border_style = "rounded",
		enable_git_status = true,
		enable_diagnostics = false,
		sources = { "filesystem", "buffers", "git_status" },

		default_component_configs = {
			git_status = {
				symbols = {
					added = "✚",
					modified = "",
					deleted = "✖",
					renamed = "➜",
					untracked = "★",
					ignored = "◌",
					unstaged = "󰄱",
					staged = "",
					conflict = "",
				},
			},
		},

		window = {
			width = 34,
			mappings = {
				-- keep <space> as <leader> inside the tree
				["<space>"] = "none",
				["l"] = "open", -- expand folder / open file
				["h"] = "close_node", -- collapse folder
			},
		},

		filesystem = {
			bind_to_cwd = false,
			follow_current_file = { enabled = true, leave_dirs_open = true },
			use_libuv_file_watcher = true,
			hijack_netrw_behavior = "open_current",

			-- Showing gitignored files in the tree (hide_gitignored = false)
			-- makes neo-tree pass --no-ignore to fd, which also drags them
			-- into the `/` fuzzy finder. Strip that flag so search respects
			-- .gitignore; the tree's dimming of ignored files is a separate
			-- code path and stays intact.
			find_args = function(cmd, _path, _glob, args)
				if cmd == "fd" or cmd == "fdfind" then
					args = vim.tbl_filter(function(a)
						return a ~= "--no-ignore"
					end, args)
				end
				return args
			end,

			filtered_items = {
				visible = false,
				hide_dotfiles = false, -- show dotfiles
				hide_gitignored = false, -- show gitignored files, dimmed + ignored icon
				hide_hidden = false,
				never_show = { ".DS_Store", ".git" },
			},
		},
	},
}
