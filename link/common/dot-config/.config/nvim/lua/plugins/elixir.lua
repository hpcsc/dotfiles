return {
	"elixir-tools/elixir-tools.nvim",
	version = "*",
	ft = { "elixir", "eelixir", "heex" },
	dependencies = {
		"nvim-lua/plenary.nvim",
	},
	config = function()
		local elixir = require("elixir")
		local elixirls = require("elixir.elixirls")

		elixir.setup({
			nextls = { enable = false },
			elixirls = {
				enable = true,
				-- elixir-tools installs ElixirLS v0.22.0 by default, which does not support Elixir 1.20
				tag = "v0.31.1",
				settings = elixirls.settings({
					dialyzerEnabled = true,
					enableTestLenses = true,
					fetchDeps = false,
				}),
				on_attach = function(client, bufnr)
					require("config.lsp").on_attach(client, bufnr)

					local map = vim.keymap.set
					map("n", "<leader>ef", ":ElixirFromPipe<cr>", { buffer = bufnr, desc = "Elixir: from pipe" })
					map("n", "<leader>et", ":ElixirToPipe<cr>", { buffer = bufnr, desc = "Elixir: to pipe" })
					map("v", "<leader>em", ":ElixirExpandMacro<cr>", { buffer = bufnr, desc = "Elixir: expand macro" })
				end,
			},
		})
	end,
}
