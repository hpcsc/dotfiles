local map = vim.keymap.set
local silent = { silent = true }

local function opts(desc, o)
	o = o or {}
	o.desc = desc
	return o
end

-- disable arrow navigation keys :(
map({ "n", "v", "x", "s", "o" }, "<Up>", "<NOP>", silent)
map({ "n", "v", "x", "s", "o" }, "<Down>", "<NOP>", silent)
map({ "n", "v", "x", "s", "o" }, "<Left>", "<NOP>", silent)
map({ "n", "v", "x", "s", "o" }, "<Right>", "<NOP>", silent)

-- window navigation and management
map("n", "<leader>h", "<C-w>h", opts("Window left", { silent = true }))
map("n", "<leader>j", "<C-w>j", opts("Window down", { silent = true }))
map("n", "<leader>k", "<C-w>k", opts("Window up", { silent = true }))
map("n", "<leader>l", "<C-w>l", opts("Window right", { silent = true }))
map("n", "<leader>ws", "<C-w>s", opts("Split horizontal", { silent = true }))
map("n", "<leader>wv", "<C-w>v", opts("Split vertical", { silent = true }))
map("n", "<leader>wc", "<C-w>c", opts("Close window", { silent = true }))
local saved_layout = nil
local function maximize_window()
	saved_layout = vim.fn.winrestcmd()
	vim.cmd("wincmd _ | wincmd |")
end
local function restore_window()
	if saved_layout then
		vim.cmd(saved_layout)
		saved_layout = nil
	else
		vim.cmd("wincmd =")
	end
end
map("n", "<leader>wm", maximize_window, opts("Maximize window", { silent = true }))
map("n", "<leader>w=", restore_window, opts("Restore window layout", { silent = true }))
map("t", "<leader>wm", function()
	vim.cmd("stopinsert")
	maximize_window()
end, opts("Maximize window", { silent = true }))
map("t", "<leader>w=", function()
	vim.cmd("stopinsert")
	restore_window()
end, opts("Restore window layout", { silent = true }))

-- OverCommandLine then start %s/
map("n", "<leader>s", ":OverCommandLine<CR>%s/", opts("Substitute in file"))
map("n", "<leader>W", ":update<CR>", opts("Save file"))
map("n", "<leader>q", ":qa<CR>", opts("Quit all"))

-- Command-line mode mappings
map("c", "w!!", "w !sudo tee > /dev/null % ")
map("c", "%%", [[<C-R>=expand("%:p:h") . "/" <CR>]])

-- Normal mode mappings
map("n", "<leader>[", ':exe "resize " . (winheight(0) * 3/2)<CR>', opts("Taller window", { silent = true }))
map("n", "<leader>]", ':exe "resize " . (winheight(0) * 2/3)<CR>', opts("Shorter window", { silent = true }))
map("n", "<leader><", ':exe "vertical resize " . (winwidth(0) * 2/3)<CR>', opts("Narrower window", { silent = true }))
map("n", "<leader>>", ':exe "vertical resize " . (winwidth(0) * 3/2)<CR>', opts("Wider window", { silent = true }))
map("n", "<leader>=", ":winc =<CR>", opts("Equalize windows", { silent = true }))
map("n", "<C-d>", "<C-d>zz", opts("Half-page down (centered)", { silent = true }))
map("n", "<C-u>", "<C-u>zz", opts("Half-page up (centered)", { silent = true }))
map("n", "H", "Hzz", opts("Top of screen (centered)", { silent = true }))
map("n", "M", "Mzz", opts("Middle of screen (centered)", { silent = true }))
map("n", "L", "Lzz", opts("Bottom of screen (centered)", { silent = true }))
map("n", "<leader>cp", function()
	local path = vim.fn.expand("%")
	vim.fn.setreg("+", path)
	print("Copied: " .. path)
end, opts("Copy file path", { silent = true }))

-- insert newline in normal mode
map("n", "<leader><space>", "o<Esc>", opts("Blank line below", { silent = true }))

-- yank current line without newline character
map("n", "<leader>y", "^y$", opts("Yank line (no newline)", { silent = true }))

-- stop highlighting search
map("n", "<CR>", ":nohlsearch<CR>", opts("Clear search highlight"))

-- toggle folding
map("n", "<leader>z", "za", opts("Toggle fold"))

-- File-tree mappings (<leader>t toggle, <leader>m reveal) live in the
-- neo-tree spec's `keys`.

-- fzf mappings
map("n", "<c-n>", ":Buffers<cr>", opts("fzf buffers"))
map("n", "<c-p>", ":Files<cr>", opts("fzf files"))
map("n", "<c-g>", ":Rg<cr>", opts("fzf ripgrep"))
map("n", "<c-y>", ":BTags<cr>", opts("fzf buffer tags"))

-- quickfix navigation
map("n", "]q", ":cnext<cr>", opts("Next quickfix", { silent = true }))
map("n", "[q", ":cprev<cr>", opts("Previous quickfix", { silent = true }))

-- Insert mode mappings
map("i", "jk", "<Esc>", opts("Escape"))

-- Visual mode mappings
map("v", "<CR>", "<Esc>", opts("Escape"))
map("v", "y", "ygv<Esc>", opts("Yank (keep position)"))
map("x", "<", "<gv", opts("Dedent, keep selection"))
map("x", ">", ">gv", opts("Indent, keep selection"))
map("x", "<leader>p", '"_dP', opts("Paste (no yank)"))

local function execute_macro_over_visual_range()
	-- Ask for a register and execute the macro over the visual range
	local char = vim.fn.nr2char(vim.fn.getchar())
	if not char or char == "" then
		return
	end
	vim.cmd("'<,'>normal @" .. char)
end
map("x", "@", function()
	execute_macro_over_visual_range()
end, opts("Run macro over selection"))
