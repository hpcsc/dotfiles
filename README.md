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

It uses [lazy.nvim](https://github.com/folke/lazy.nvim) for plugin management. A single config serves every language; language-specific plugins load on demand.

```sh
nvim
```

General settings, keymaps, and language-agnostic plugins load at startup. Language tooling is gated on filetype, so a language server and its plugins start only when you open a matching file:

| Language | Plugin | Trigger | Includes |
|----------|--------|---------|----------|
| Go | go.nvim (ray-x) | `go`, `gomod`, `gosum`, `gowork`, `gotmpl` files | gopls, treesitter for go/gomod/gosum/gowork, auto goimports on save |
| Elixir | elixir-tools.nvim | `elixir`, `eelixir`, `heex` files | ElixirLS, treesitter for elixir/heex/eex |

### Adding a language

1. Add a plugin spec under `lua/plugins/<language>.lua`, gated with `ft = { ... }` so it loads only for the relevant filetypes.
2. Add the treesitter grammars for the language to the `languages` list in `lua/plugins/treesitter.lua`.

## Setup a new machine

To setup a new machine using this dotfiles repo, follow instructions at [Wiki](https://github.com/hpcsc/dotfiles/wiki)
