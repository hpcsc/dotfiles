-- snacks.nvim is already pulled in by claudecode.nvim; configured here so its
-- image module gets set up. Renders markdown images, and mermaid blocks via mmdc.
return {
	"folke/snacks.nvim",
	opts = {
		image = {
			-- Off under WezTerm. It has no kitty unicode placeholder support, so snacks
			-- falls back to positioning images with a cursor escape, and under tmux that
			-- escape reaches the terminal in absolute coordinates rather than the pane's.
			-- Images land somewhere else on screen entirely, over the status line and any
			-- neighbouring pane. Sending the escape unwrapped so tmux reads it does not
			-- help either; Neovim's own redraw moves the cursor again before the image
			-- data arrives.
			--
			-- Placeholders skip cursor positioning altogether, so this can go straight
			-- back to true on ghostty or kitty. Returning to it on WezTerm needs two
			-- separate things to land:
			--   1. https://github.com/wezterm/wezterm/pull/7924 - the unicode placeholder
			--      implementation, still open as of 2026-08-04. It is the unticked
			--      "placeholder support" item on the kitty protocol tracking issue,
			--      https://github.com/wezterm/wezterm/issues/986. The newest stable
			--      release is 20240203, so this also means running a nightly.
			--   2. snacks hardcodes placeholders = false for wezterm, in
			--      lua/snacks/image/terminal.lua. Until that flips, override the
			--      detection with SNACKS_KITTY=1 SNACKS_WEZTERM=0 - both are needed,
			--      since wezterm is matched after kitty and would reset the flag.
			enabled = false,
			convert = {
				mermaid = function()
					local theme = vim.o.background == "light" and "neutral" or "dark"
					-- snacks derives its scale from the cell size the terminal reports,
					-- but tmux reports logical pixels, so on a HiDPI display that lands
					-- near 1.25 and mmdc emits a PNG with about half the pixels it gets
					-- drawn into. Render oversized and let max_width/max_height below
					-- scale it back down, which costs a little render time and buys back
					-- the resolution.
					local scale = math.max(3, (Snacks.image.terminal.size().scale or 1) * 3)
					return { "-i", "{src}", "-o", "{file}", "-b", "transparent", "-t", theme, "-s", tostring(scale) }
				end,
			},
			doc = {
				-- `inline` is deliberately left at its default of true, so that enabling
				-- this module on a placeholder-capable terminal renders in the buffer
				-- rather than pinning the float fallback that fails above.
				max_width = 90,
				max_height = 40,
			},
		},
	},
}
