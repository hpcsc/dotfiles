local M = {}

local function telescope(builtin)
	return function()
		require("telescope.builtin")[builtin]()
	end
end

-- gopls advertises "." as its only trigger character, so `autotrigger` on its own
-- would open the menu after a selector and never while typing a bare identifier.
local function with_identifier_triggers(server_chars)
	local seen = {}
	local chars = {}

	local function add(char)
		if not seen[char] then
			seen[char] = true
			table.insert(chars, char)
		end
	end

	for _, char in ipairs(server_chars or {}) do
		add(char)
	end
	for _, range in ipairs({ { "a", "z" }, { "A", "Z" }, { "0", "9" } }) do
		for byte = string.byte(range[1]), string.byte(range[2]) do
			add(string.char(byte))
		end
	end
	add("_")

	return chars
end

-- Neovim's built-in LSP/diagnostic keymaps (0.11+, set on attach) stay as-is:
--   K           hover
--   grn         rename
--   gra         code action (normal + visual)
--   grx         run code lens
--   <C-s>       signature help (insert / select)
--   gq{motion}  format via LSP, e.g. gggqG  (LSP sets formatexpr)
--   <C-]>       goto definition             (LSP sets tagfunc)
--   <C-x><C-o>  completion                  (LSP sets omnifunc)
--   ]d / [d     next / previous diagnostic
--   <C-W>d      open diagnostic float
--
-- Completion also opens on its own as you type; 'noselect' means nothing is
-- inserted until you pick, with <C-y> to accept and <C-e> to dismiss.
--
-- The maps below shadow the default grr/gri/grt/gO (and add gd) so the same
-- keys open Telescope pickers instead of the quickfix list.
function M.on_attach(client, bufnr)
	local map = vim.keymap.set
	local function opts(desc)
		return { buffer = bufnr, desc = desc }
	end

	map("n", "gd", telescope("lsp_definitions"), opts("LSP definitions"))
	map("n", "grr", telescope("lsp_references"), opts("LSP references"))
	map("n", "gri", telescope("lsp_implementations"), opts("LSP implementations"))
	map("n", "grt", telescope("lsp_type_definitions"), opts("LSP type definitions"))
	map("n", "gO", telescope("lsp_document_symbols"), opts("LSP document symbols"))
	map("n", "<leader>d", telescope("diagnostics"), opts("LSP diagnostics list"))

	map("n", "<leader>K", vim.lsp.buf.signature_help, opts("LSP signature help"))

	if client:supports_method("textDocument/completion") then
		local provider = client.server_capabilities.completionProvider
		provider.triggerCharacters = with_identifier_triggers(provider.triggerCharacters)
		vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })
	end
end

return M
