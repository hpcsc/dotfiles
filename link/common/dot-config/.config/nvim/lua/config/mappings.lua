local map = vim.keymap.set
local silent = { silent = true }

-- disable arrow navigation keys :(
map({ "n", "v", "x", "s", "o" }, "<Up>", "<NOP>", silent)
map({ "n", "v", "x", "s", "o" }, "<Down>", "<NOP>", silent)
map({ "n", "v", "x", "s", "o" }, "<Left>", "<NOP>", silent)
map({ "n", "v", "x", "s", "o" }, "<Right>", "<NOP>", silent)

-- window navigation and management
map("n", "<leader>h", "<C-w>h", silent)
map("n", "<leader>j", "<C-w>j", silent)
map("n", "<leader>k", "<C-w>k", silent)
map("n", "<leader>l", "<C-w>l", silent)
map("n", "<leader>ws", "<C-w>s", silent)
map("n", "<leader>wv", "<C-w>v", silent)
map("n", "<leader>wc", "<C-w>c", silent)

-- OverCommandLine then start %s/
map("n", "<leader>s", ":OverCommandLine<CR>%s/", {})
map("n", "<leader>w", ":update<CR>", {})
map("n", "<leader>q", ":qa<CR>", {})

-- Command-line mode mappings
map("c", "w!!", "w !sudo tee > /dev/null % ")
map("c", "%%", [[<C-R>=expand("%:p:h") . "/" <CR>]])

-- Normal mode mappings
map("n", "<leader>[", ':exe "resize " . (winheight(0) * 3/2)<CR>', silent)
map("n", "<leader>]", ':exe "resize " . (winheight(0) * 2/3)<CR>', silent)
map("n", "<leader><", ':exe "vertical resize " . (winwidth(0) * 2/3)<CR>', silent)
map("n", "<leader>>", ':exe "vertical resize " . (winwidth(0) * 3/2)<CR>', silent)
map("n", "<leader>=", ":winc =<CR>", silent)
map("n", "<C-d>", "<C-d>zz", silent)
map("n", "<C-u>", "<C-u>zz", silent)
map("n", "H", "Hzz", silent)
map("n", "M", "Mzz", silent)
map("n", "L", "Lzz", silent)

-- insert newline in normal mode
map("n", "<leader><space>", "o<Esc>", silent)

-- yank current line without newline character
map("n", "<leader>y", "^y$", silent)

-- stop highlighting search
map("n", "<CR>", ":nohlsearch<CR>", {})

-- toggle folding
map("n", "<leader>z", "za", {})

-- NERDTree mappings
map("n", "<leader>m", ":NERDTreeFind<cr>", {})
map("n", "<leader>t", ":NERDTreeToggle<cr>", {})

-- fzf mappings
map("n", "<c-n>", ":Buffers<cr>", {})
map("n", "<c-p>", ":Files<cr>", {})
map("n", "<c-g>", ":Rg<cr>", {})
map("n", "<c-y>", ":BTags<cr>", {})

-- Insert mode mappings
map("i", "jk", "<Esc>")

-- Visual mode mappings
map("v", "<CR>", "<Esc>")
map("v", "y", "ygv<Esc>")
map("x", "<", "<gv")
map("x", ">", ">gv")
map("x", "<leader>p", '"_dP')

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
end, {})

local function is_nerdtree_open()
	local bufname = vim.t.NERDTreeBufName
	return bufname ~= nil and vim.fn.bufwinnr(bufname) ~= -1
end

local function sync_tree()
	if vim.bo.modifiable and is_nerdtree_open() and #vim.fn.expand("%") > 0 and not vim.wo.diff then
		vim.cmd("NERDTreeFind")
		vim.cmd("wincmd p")
	end
end
map("n", "<leader>/", function()
	sync_tree()
end, {})
