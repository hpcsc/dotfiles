return {
	"nvim-treesitter/nvim-treesitter",
	ft = { "bash", "javascript", "typescript" },
	build = ":TSUpdate",
	lazy = false,
	config = function()
		require("nvim-treesitter.configs").setup({
			-- Add languages to be installed here that you want installed for treesitter
			ensure_installed = { "bash", "javascript", "typescript" },

			-- Install parsers synchronously (only applied to `ensure_installed`)
			sync_install = false,

			-- Automatically install missing parsers when entering buffer
			-- Recommendation: set to false if you don't have `tree-sitter` CLI installed locally
			auto_install = false,

			highlight = {
				enable = true,
				disable = function(_, bufnr)
					return vim.api.nvim_buf_line_count(bufnr) > 10000
				end,
				additional_vim_regex_highlighting = false,
			},

			indent = {
				enable = true,
			},
		})
	end,
}
