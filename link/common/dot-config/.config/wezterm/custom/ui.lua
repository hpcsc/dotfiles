local wezterm = require 'wezterm'

local module = {}

function module.apply_to_config(config)
    config.color_scheme = 'GruvboxDark'
    config.initial_rows = 300
    config.initial_cols = 600
    config.scrollback_lines = 10000
    config.hide_tab_bar_if_only_one_tab = true
    config.font = wezterm.font {
        family = 'FiraCode Nerd Font',
        harfbuzz_features = { 'calt=0', 'clig=0', 'liga=1' }
    }

    config.font_size = 16
    config.window_frame = {
        font_size = 16.0
    }

    config.colors = {
        tab_bar = {
            active_tab = {
                bg_color = '#7c6f64',
                fg_color = '#3c3836'
            },
            inactive_tab = {
                bg_color = '#504945',
                fg_color = '#808080'
            }
        }
    }

    config.window_padding = {
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
    }
end

return module
