return {
	"scrooloose/nerdtree",

	cmd = { "NERDTree", "NERDTreeToggle", "NERDTreeFind" },

	init = function()
		vim.g.NERDTreeShowHidden = 1 -- show hidden files

		vim.api.nvim_create_autocmd("StdinReadPre", {
			callback = function()
				-- detect input from stdin (e.g. piping), to avoid auto-opening NERDTree
				vim.g.s_std_in = 1
			end,
		})

		vim.api.nvim_create_autocmd("VimEnter", {
			callback = function()
				-- if open with a single directory argument and not reading stdin,
				-- open NERDTree on that directory, then go back to previous window and open an empty buffer
				if vim.fn.argc() == 1 and vim.fn.isdirectory(vim.fn.argv()[1]) == 1 and vim.g.s_std_in == nil then
					vim.cmd("NERDTree " .. vim.fn.argv()[1])
					vim.cmd("wincmd p")
					vim.cmd("ene")
				end
			end,
		})
	end,
}
