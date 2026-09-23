return {
	"natecraddock/telescope-zf-native.nvim",
	-- the plugin ships precompiled libzf libraries, so do not let lazy
	-- build them with its rocks (luarocks) support
	--
	-- lazy.nvim only reads rocks support from its global options, so the
	-- disable lives in config/lazy.lua where setup, install and checker
	-- are configured. a per-spec `rocks` block here is ignored.
	dependencies = {
		{ "nvim-telescope/telescope.nvim", lazy = true },
	},
}
