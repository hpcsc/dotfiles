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

## Setup a new machine

To setup a new machine using this dotfiles repo, follow instructions at [Wiki](https://github.com/hpcsc/dotfiles/wiki)
