local M = {}

function M.setup(opts)
	opts = opts or {}
	require("usercommands")
	require("config.options")
	require("config.autocmds")
	require("config.lazy").setup(opts.lazy)
	require("config.mappings")
end

return M
