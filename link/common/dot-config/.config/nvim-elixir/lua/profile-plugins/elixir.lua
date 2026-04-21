return {
	"elixir-tools/elixir-tools.nvim",
	version = "*",
	event = { "BufReadPre", "BufNewFile" },
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
				settings = elixirls.settings({
					dialyzerEnabled = true,
					enableTestLenses = true,
					fetchDeps = false,
				}),
				on_attach = function(client, bufnr)
					local map = vim.keymap.set
					local bufopts = { buffer = bufnr }
					map("n", "gd", vim.lsp.buf.definition, bufopts)
					map("n", "gr", vim.lsp.buf.references, bufopts)
					map("n", "K", vim.lsp.buf.hover, bufopts)
					map("n", "<leader>rn", vim.lsp.buf.rename, bufopts)
					map("n", "<leader>ca", vim.lsp.buf.code_action, bufopts)
					map("n", "<leader>f", function()
						vim.lsp.buf.format({ async = true })
					end, bufopts)
					map("n", "[d", vim.diagnostic.goto_prev, bufopts)
					map("n", "]d", vim.diagnostic.goto_next, bufopts)
					map("n", "<leader>e", vim.diagnostic.open_float, bufopts)
					map("n", "<leader>fp", ":ElixirFromPipe<cr>", bufopts)
					map("n", "<leader>tp", ":ElixirToPipe<cr>", bufopts)
					map("v", "<leader>em", ":ElixirExpandMacro<cr>", bufopts)
				end,
			},
		})
	end,
}
