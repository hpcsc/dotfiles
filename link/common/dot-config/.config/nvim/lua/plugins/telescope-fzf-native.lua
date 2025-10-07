return {
	"nvim-telescope/telescope-fzf-native.nvim",
	branch = "main",
	build = "make",
	dependencies = {
		{ "nvim-telescope/telescope.nvim", lazy = true },
	},
}
