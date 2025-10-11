return {
	"mikavilpas/yazi.nvim",
	dependencies = {
		{ "nvim-lua/plenary.nvim", lazy = true },
	},
	keys = {
		{ "<leader>;", mode = { "n", "v" }, "<cmd>Yazi<cr>", desc = "Open Yazi file manager" },
	},
}
