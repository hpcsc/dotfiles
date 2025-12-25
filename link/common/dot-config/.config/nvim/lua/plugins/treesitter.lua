return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	build = ":TSUpdate",
	lazy = false,
	config = function()
		require("nvim-treesitter").install({ "bash", "javascript", "typescript", "lua" })

		vim.api.nvim_create_autocmd("FileType", {
			callback = function()
				pcall(vim.treesitter.start)

				if vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil then
					vim.wo[0][0].foldmethod = "expr"
					vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
				else
					vim.wo[0][0].foldmethod = "syntax"
				end
			end,
		})
	end,
}
