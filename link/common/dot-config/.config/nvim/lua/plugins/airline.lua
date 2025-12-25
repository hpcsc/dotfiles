return {
	"vim-airline/vim-airline",

	init = function()
		vim.g["airline#extensions#tabline#enabled"] = 1
		vim.g["airline#extensions#tabline#formatter"] = "unique_tail"
		vim.g["airline#extensions#nerdtree_statusline"] = 0
		vim.g["airline_skip_empty_sections"] = 1
		vim.g["airline_section_b"] = ""
		vim.g["airline_powerline_fonts"] = 1
		-- workaround for wide character issue in NeoVim 0.10.*
		vim.g["airline#extensions#whitespace#symbol"] = "!"
	end,
}
