vim.g.mapleader = " "

require("init")

-- filetype plugin indent on (load filetype-specific indent files at ~/.vim/indent/*.vim)
vim.cmd("filetype plugin indent on")
-- Syntax on
vim.cmd("syntax on")
-- Theme (gruvbox is provided by plugin so this needs to run after plugin setup)
vim.cmd("colorscheme gruvbox")
