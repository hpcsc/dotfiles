-- Highlight yanked text (respect HighlightedyankRegion if present)
vim.api.nvim_create_autocmd("TextYankPost", {
	callback = function()
		local higroup = (vim.fn.hlexists("HighlightedyankRegion") > 0) and "HighlightedyankRegion" or "IncSearch"
		vim.hl.on_yank({ higroup = higroup, timeout = 500 })
	end,
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
