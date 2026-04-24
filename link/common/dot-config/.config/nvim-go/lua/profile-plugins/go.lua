return {
	"ray-x/go.nvim",
	ft = { "go", "gomod", "gosum", "gowork", "gotmpl" },
	dependencies = {
		"ray-x/guihua.lua",
		"neovim/nvim-lspconfig",
		"nvim-treesitter/nvim-treesitter",
	},
	build = ':lua require("go.install").update_all_sync()',
	config = function()
		require("go").setup({
			lsp_cfg = {
				capabilities = vim.lsp.protocol.make_client_capabilities(),
				settings = {
					gopls = {
						analyses = {
							unusedparams = true,
							shadow = true,
							nilness = true,
							unusedwrite = true,
							useany = true,
						},
						staticcheck = true,
						gofumpt = true,
						usePlaceholders = true,
						completeUnimported = true,
						hints = {
							assignVariableTypes = true,
							compositeLiteralFields = true,
							compositeLiteralTypes = true,
							constantValues = true,
							functionTypeParameters = true,
							parameterNames = true,
							rangeVariableTypes = true,
						},
					},
				},
			},
			lsp_keymaps = false,
			lsp_inlay_hints = {
				enable = true,
			},
			dap_debug = true,
			dap_debug_keymap = false,
			dap_debug_gui = true,
			trouble = false,
			test_runner = "go",
			run_in_floaterm = false,
			icons = false,
		})

		local format_sync_grp = vim.api.nvim_create_augroup("GoFormat", { clear = true })
		vim.api.nvim_create_autocmd("BufWritePre", {
			pattern = "*.go",
			callback = function()
				require("go.format").goimports()
			end,
			group = format_sync_grp,
		})

		vim.api.nvim_create_autocmd("LspAttach", {
			group = vim.api.nvim_create_augroup("GoLspAttach", { clear = true }),
			callback = function(args)
				local client = vim.lsp.get_client_by_id(args.data.client_id)
				if not client or client.name ~= "gopls" then
					return
				end

				local map = vim.keymap.set
				local bufopts = { buffer = args.buf }
				map("n", "gd", vim.lsp.buf.definition, bufopts)
				map("n", "gr", vim.lsp.buf.references, bufopts)
				map("n", "gi", vim.lsp.buf.implementation, bufopts)
				map("n", "K", vim.lsp.buf.hover, bufopts)
				map("n", "<leader>rn", vim.lsp.buf.rename, bufopts)
				map("n", "<leader>ca", vim.lsp.buf.code_action, bufopts)
				map("n", "<leader>f", function()
					vim.lsp.buf.format({ async = true })
				end, bufopts)
				map("n", "[d", vim.diagnostic.goto_prev, bufopts)
				map("n", "]d", vim.diagnostic.goto_next, bufopts)
				map("n", "<leader>e", vim.diagnostic.open_float, bufopts)

				map("n", "<leader>gt", ":GoTest<cr>", bufopts)
				map("n", "<leader>gT", ":GoTestFunc<cr>", bufopts)
				map("n", "<leader>gc", ":GoCoverage<cr>", bufopts)
				map("n", "<leader>gr", ":GoRun<cr>", bufopts)
				map("n", "<leader>gi", ":GoImpl<cr>", bufopts)
				map("n", "<leader>gfs", ":GoFillStruct<cr>", bufopts)
				map("n", "<leader>gie", ":GoIfErr<cr>", bufopts)
				map("n", "<leader>gat", ":GoAddTag<cr>", bufopts)
				map("n", "<leader>grt", ":GoRmTag<cr>", bufopts)
				map("n", "<leader>ga", ":GoAlt<cr>", bufopts)
			end,
		})
	end,
}
