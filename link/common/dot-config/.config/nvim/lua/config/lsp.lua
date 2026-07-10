local M = {}

local function telescope(builtin)
	return function()
		require("telescope.builtin")[builtin]()
	end
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
-- The maps below shadow the default grr/gri/grt/gO (and add gd) so the same
-- keys open Telescope pickers instead of the quickfix list.
function M.on_attach(bufnr)
	local map = vim.keymap.set
	local bufopts = { buffer = bufnr }

	map("n", "gd", telescope("lsp_definitions"), bufopts)
	map("n", "grr", telescope("lsp_references"), bufopts)
	map("n", "gri", telescope("lsp_implementations"), bufopts)
	map("n", "grt", telescope("lsp_type_definitions"), bufopts)
	map("n", "gO", telescope("lsp_document_symbols"), bufopts)
	map("n", "<leader>d", telescope("diagnostics"), bufopts)

	map("n", "<leader>K", vim.lsp.buf.signature_help, bufopts)
end

return M
