local opt = vim.opt

opt.compatible = false -- turn off vi compatibility
opt.cursorline = true -- highlight current line
opt.tabstop = 2 -- number of visual spaces per TAB
opt.softtabstop = 2 -- number of spaces in tab when editing
opt.shiftwidth = 2 -- number of spaces when indenting with '>'
opt.expandtab = true -- tabs are spaces
opt.wildmenu = true -- visual autocomplete for command menu
opt.lazyredraw = true -- redraw only when we need
opt.showmatch = true -- highlight matching [{()}]
opt.incsearch = true -- search as characters are entered
opt.hlsearch = true -- highlight matches
opt.modelines = 1 -- enable modeline at the bottom of the file
opt.hidden = true -- hide current unsaved buffer when opening a new file instead of closing it
opt.backspace = { "indent", "eol", "start" }
opt.number = true -- show relative line number by default
opt.relativenumber = true
opt.clipboard = "unnamed" -- yank to clipboard
opt.showcmd = true -- show incomplete command
opt.autoindent = true -- copy indent from current line when starting a new line
opt.smartindent = true -- indent based on code syntax
opt.wrap = false -- not wrap lines
opt.linebreak = true -- wrap lines at convenient points
opt.encoding = "utf-8" -- to fix NERDTree rendering issue in ubuntu
opt.backupdir = vim.fn.expand("~/.vim/tmp/backup//") -- set custom location for backup files
opt.directory = vim.fn.expand("~/.vim/tmp/swap//") -- set custom location for swap files
opt.undodir = vim.fn.expand("~/.vim/tmp/undo//") -- set custom location for undo files
opt.ignorecase = true
opt.smartcase = true -- smart case insensitive search
opt.mouse = "a" -- enable mouse for scrolling and resizing
opt.scrolloff = 1 -- always keep 1 line above and below the cursor for context
opt.background = "dark"
opt.complete:remove("i") -- disable scanning included files for keyword completion
-- Open new split panes to right and bottom, which feels more natural
opt.splitbelow = true
opt.splitright = true
opt.jumpoptions = "stack" -- make jumplist behaves like a stack
-- Use rg over Grep
opt.grepprg = "rg --vimgrep"
-- [[
-- use in combination with `checktime` (in autocmd)
-- behavior:
-- - If autoread is enabled and a buffer has not been modified within Neovim,
--   `checktime` will automatically reload the buffer's contents from the disk without prompting the user.
-- - If autoread is disabled, or if the buffer has been modified within Neovim (creating a "dirty" buffer),
--   `checktime` will prompt you to decide how to handle the external change. You will typically be given options to reload the file (discarding local changes), keep local changes (overwriting the external changes on save), or merge the changes.
-- ]]
opt.autoread = true

-- Folding
opt.foldenable = true -- enable folding
opt.foldlevelstart = 10 -- open most folds by default
opt.foldnestmax = 10 -- 10 nested fold max
opt.foldmethod = "syntax" -- fold based on filetype syntax
vim.g.javaScript_fold = 1
vim.g.xml_syntax_folding = 1
