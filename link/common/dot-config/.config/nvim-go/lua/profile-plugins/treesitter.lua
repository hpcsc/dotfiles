return {
	"nvim-treesitter/nvim-treesitter",
	opts = function(_, opts)
		vim.list_extend(opts.languages, { "go", "gomod", "gosum", "gowork" })
	end,
}
