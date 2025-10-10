return {
	"aspeddro/gitui.nvim",
	keys = {
		{
			"<leader>g",
			function()
				require("gitui").open()
			end,
			desc = "Open GitUI",
		},
	},
}
