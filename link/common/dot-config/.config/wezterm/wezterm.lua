local wezterm = require 'wezterm'

local config = wezterm.config_builder()
require('custom').apply_to_config(config)
return config
