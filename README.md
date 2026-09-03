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
- `/docs`: reference documentation for the tooling this repo carries
- `/tests`: contains the test suites. `tests/scripts/*.bats` use `bats`; the rest are plain shell scripts that build fixture repositories and assert on the JSON a command returns
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

## clerk, and the implement skill

`clerk` carries an implementation run from a request to a landed branch. It holds the order of the run, checks the paperwork, and leaves every judgment — what the code should be, whether a review finding is real — to whoever is doing the work. The `/implement` skill is one loop around it: ask `clerk step` what comes next, do that one thing, ask again.

The commands are Python under `link/common/dot-local/bin/`, stowed to `~/.local/bin`, and reached as `clerk <name>` the way git reaches `git-<name>`.

Start here to change any of it:

| Read | For |
|---|---|
| [docs/clerk-structure.md](docs/clerk-structure.md) | Seven diagrams of how the pieces fit, each naming the files to open and when you would change them |
| `link/common/dot-config/.config/ai/method/README.md` | Why a given decision belongs to a command rather than to the model |
| `link/common/dot-config/.config/ai/method/clerk-step.md` | The step table, the run ledger, and what each row accepts as evidence |

The prose the model reads is generated. Edit the sources under `link/common/dot-config/.config/ai/method/`, never the `SKILL.md` files, then run `task common:gen`.

```sh
task common:test:clerk    # the three fixture suites, about six minutes
task common:test:python   # pyflakes over every Python file
task common:test          # everything, including the generated-file checks
```

## Setup a new machine

To setup a new machine using this dotfiles repo, follow instructions at [Wiki](https://github.com/hpcsc/dotfiles/wiki)
