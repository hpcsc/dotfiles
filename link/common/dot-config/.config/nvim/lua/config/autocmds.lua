-- Highlight yanked text (respect HighlightedyankRegion if present)
vim.api.nvim_create_autocmd("TextYankPost", {
	callback = function()
		local higroup = (vim.fn.hlexists("HighlightedyankRegion") > 0) and "HighlightedyankRegion" or "IncSearch"
		vim.hl.on_yank({ higroup = higroup, timeout = 500 })
	end,
})

-- [[
-- `checktime`: compares the timestamp of the file on disk with the timestamp of the buffer in memory.
--    If a discrepancy is found, it indicates that the file has been changed externally.
--    Use in combination with `autoread` option
-- behavior:
-- - If autoread is enabled and a buffer has not been modified within Neovim,
--   `checktime` will automatically reload the buffer's contents from the disk without prompting the user.
-- - If autoread is disabled, or if the buffer has been modified within Neovim (creating a "dirty" buffer),
--   `checktime` will prompt you to decide how to handle the external change. You will typically be given options to reload the file (discarding local changes), keep local changes (overwriting the external changes on save), or merge the changes.
-- ]]
vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "CursorHoldI", "FocusGained" }, {
	command = "if mode() != 'c' | checktime | endif",
})

-- number_toggle_group: relative in normal, absolute in insert
local number_toggle_group = vim.api.nvim_create_augroup("number_toggle", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "InsertLeave" }, {
	group = number_toggle_group,
	callback = function()
		vim.opt.relativenumber = true
	end,
})
vim.api.nvim_create_autocmd({ "BufLeave", "FocusLost", "InsertEnter" }, {
	group = number_toggle_group,
	callback = function()
		vim.opt.relativenumber = false
	end,
})

-- mark buffer with mO when leaving (skip fzf/terminal)
local buf_mark_group = vim.api.nvim_create_augroup("buf_mark", { clear = true })
vim.api.nvim_create_autocmd("BufLeave", {
	group = buf_mark_group,
	callback = function()
		if not string.match(vim.fn.bufname(""), "fzf") and vim.bo.buftype ~= "terminal" then
			vim.cmd("normal! mO")
		end
	end,
})

-- C# indentation
vim.api.nvim_create_autocmd("FileType", {
	pattern = "cs",
	callback = function()
		vim.bo.tabstop = 4
		vim.bo.shiftwidth = 4
		vim.bo.softtabstop = 4
		vim.bo.expandtab = true
	end,
})
