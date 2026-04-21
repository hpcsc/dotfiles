# David Nguyen's dotfiles

## Tools

- `stow`: manage symlinks in both MacOS and Ubuntu
- `homebrew-bundle`: backup and restore brew packages (MacOS only)

## Folder Structure

- `/up.sh`: entry point to setting up a new machine. This script just setup log output and delegates actual installation to install.sh
- `/install.sh`: main installation script
- `/scripts`: contains scripts used during setting up a new machine. Scripts in this folder follows convention of prepending platform in front of script names.
  E.g. `macos-brew-bundle.sh` is only applicable to MacOS, `ubuntu-fasd.sh` is only applicable to Ubuntu and `common-stow.sh` is applicable to both MacOS and Ubuntu
- `/link`: contains settings to be stowed during stow step. These settings are also organized according to platforms.
- `/tests`: contains tests written using `bats`
- `/libs`: git submodules for bats and additional libraries used during testing
- `/others`: contains additional setup/tools that are not covered in `install.sh` script and need to be setup manually. E.g. iterm settings

## Neovim

Neovim configuration lives in `/link/common/dot-config/.config/nvim/` (symlinked to `~/.config/nvim/`).

It uses [lazy.nvim](https://github.com/folke/lazy.nvim) for plugin management and supports multiple profiles via Neovim's `NVIM_APPNAME` feature.

### Base config

```sh
nvim
```

Loads the default config from `~/.config/nvim/`. Contains general settings, keymaps, and language-agnostic plugins.

### Profiles

Profiles extend the base config with language-specific plugins (LSP, treesitter grammars, etc.). Each profile is a separate directory under `~/.config/` that prepends the base config to its runtime path.

Launch a profile with:

```sh
NVIM_APPNAME=nvim-<profile> nvim
```

Available profiles:

| Profile | `NVIM_APPNAME` | Config path | Includes |
|---------|----------------|-------------|----------|
| Elixir | `nvim-elixir` | `nvim-elixir/` | Next LS (elixir-tools.nvim), treesitter for elixir/heex/eex |

### Adding a new profile

1. Create `~/.config/nvim-<name>/init.lua` that prepends the base config and passes extra specs:

   ```lua
   vim.g.mapleader = " "

   local base = vim.fn.expand("~/.config/nvim")
   vim.opt.rtp:prepend(base)
   vim.opt.rtp:append(base .. "/after")

   require("init").setup({
       lazy = {
           extra_specs = {
               { import = "profile-plugins" },
           },
       }
   })

   vim.cmd("filetype plugin indent on")
   vim.cmd("syntax on")
   vim.cmd("colorscheme gruvbox")
   ```

2. Add language-specific plugin specs under `lua/profile-plugins/` in the new config directory.

## Setup a new machine

To setup a new machine using this dotfiles repo, follow instructions at [Wiki](https://github.com/hpcsc/dotfiles/wiki)
