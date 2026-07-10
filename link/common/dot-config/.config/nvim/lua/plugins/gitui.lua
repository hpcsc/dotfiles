return {
	"aspeddro/gitui.nvim",
	keys = {
		{
			"<leader>gg",
			function()
				require("gitui").open()
			end,
			desc = "Open GitUI",
		},
	},
}
