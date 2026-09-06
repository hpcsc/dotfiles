-- gruvbox predates most of the popup menu's highlight groups, so it paints the
-- kind, detail and matched-text columns the same colour as the rest of the row.
-- These fit them into its palette; the group names below are gruvbox's own.
local palette = {
	bg1 = "#3c3836",
	bg2 = "#504945",
	bg3 = "#665c54",
	bg4 = "#7c6f64",
	fg0 = "#fbf1c7",
	fg1 = "#ebdbb2",
	fg3 = "#bdae93",
	gray = "#928374",
	yellow = "#fabd2f",
}

local function set_pmenu_highlights()
	local hl = function(group, spec)
		vim.api.nvim_set_hl(0, group, spec)
	end

	hl("Pmenu", { bg = palette.bg2, fg = palette.fg1 })
	-- gruvbox selects with a bright blue bar, which the coloured kind glyphs
	-- disappear into. A neutral bar keeps them legible on the selected row too.
	hl("PmenuSel", { bg = palette.bg3, fg = palette.fg0, bold = true })
	-- Only the foreground of these two is used; every LSP item overrides it with
	-- its own kind_hlgroup. The background has to match the row either way.
	hl("PmenuKind", { bg = palette.bg2, fg = palette.gray })
	hl("PmenuKindSel", { bg = palette.bg3, fg = palette.gray })
	hl("PmenuExtra", { bg = palette.bg2, fg = palette.gray })
	hl("PmenuExtraSel", { bg = palette.bg3, fg = palette.fg3 })
	hl("PmenuMatch", { bg = palette.bg2, fg = palette.yellow, bold = true })
	hl("PmenuMatchSel", { bg = palette.bg3, fg = palette.yellow, bold = true })
	hl("PmenuSbar", { bg = palette.bg1 })
	hl("PmenuThumb", { bg = palette.bg4 })
	hl("PmenuBorder", { bg = palette.bg2, fg = palette.bg3 })

	-- The documentation window beside the menu is an ordinary float, so it follows
	-- NormalFloat, which gruvbox leaves at Neovim's near-black default. Setting it
	-- also restyles hover and diagnostic floats, which were the same black.
	hl("NormalFloat", { bg = palette.bg1, fg = palette.fg1 })
	hl("FloatBorder", { bg = palette.bg1, fg = palette.bg3 })
end

vim.api.nvim_create_autocmd("ColorScheme", {
	pattern = "gruvbox",
	callback = set_pmenu_highlights,
})
