local wezterm = require 'wezterm'
local act = wezterm.action

local module = {}

function module.apply_to_config(config)
  config.keys = {
    {
      key = 'LeftArrow',
      mods = 'OPT',
      action = act.SendKey {
        key = 'b',
        mods = 'ALT',
      }
    },
    {
      key = 'RightArrow',
      mods = 'OPT',
      action = act.SendKey {
        key = 'f',
        mods = 'ALT',
      }
    },
    {
      key = 'LeftArrow',
      mods = 'CMD',
      action = act.SendKey {
        key = 'a',
        mods = 'CTRL',
      }
    },
    {
      key = 'RightArrow',
      mods = 'CMD',
      action = act.SendKey {
        key = 'e',
        mods = 'CTRL',
      }
    },
    {
      key = 'Backspace',
      mods = 'OPT',
      action = act.SendKey {
        key = 'w',
        mods = 'CTRL',
      }
    },
    {
      key = 'Backspace',
      mods = 'CMD',
      action = act.SendKey {
        key = 'u',
        mods = 'CTRL',
      }
    },
    -- {
    --   key = 'Delete', -- Fn + Backspace
    --   mods = 'OPT',
    --   action = act.SendKey {
    --     key = 'd',
    --     mods = 'ALT',
    --   }
    -- },
    {
      key = 'z',
      mods = 'CMD',
      action = act.SendString '\x1f'  -- Undo
    }
  }
end

return module
