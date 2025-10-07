return {
	"vim-airline/vim-airline",

	init = function()
		vim.g["airline#extensions#tabline#enabled"] = 1
		-- workaround for wide character issue in NeoVim 0.10.*
		vim.g["airline#extensions#whitespace#symbol"] = "!"
	end,
}
