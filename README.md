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

## MacOS

### To generate a Brewfile for backup

```
./bundle-dump.sh
```

### To backup list of VSCode extensions

```
./others/common/vscode-backup-extensions.sh
```

### Setup a new machine

1. Update macOS to the latest version with the App Store
2. Install Xcode from the App Store, open it and accept the license agreement
3. Install macOS Command Line Tools by running `xcode-select --install`
4. Install Mac GPG/GnuPG for OS X from https://gnupg.org/download/ . This is to fix the issue of gpg not found during asdf installation (https://stackoverflow.com/questions/39494631/gpg-failed-to-sign-the-data-fatal-failed-to-write-commit-object-git-2-10-0)
5. Execute `sudo vim /etc/shells`, append `/usr/local/bin/zsh` at the end of the file and save. `/usr/local/bin/zsh` is the symlink created by Homebrew and in order to be able to change default shell to this, it needs to be in the list of valid shells (`/etc/shells`)
6. Execute `git clone https://github.com/hpcsc/dotfiles ~/dotfiles && cd ~/dotfiles && ./up.sh`
7. Make ZSH the default shell environment: `chsh -s $(which zsh)`
8. Open `iTerm2` preferences -> `General` -> `Load preferences from a custom folder`, points to `~/dotfiles/others/macos/iterm`
    - Refresh iTerm2 preferences cache if needed: `defaults read com.googlecode.iterm2`
9. Execute `./others/macos/install-gui-apps.sh` to install GUI applications
10. Execute `./others/macos/vscode/setup.sh` to configure VSCode
11. Restart computer to finalize the process

### Checklist after setup

- Install .NET Core, Authy, Boostnote, Caffeine, Jetbrains Toolbox
- Enable "Use F1, F2, etc keys as standard function keys" in Keyboard settings

## Ubuntu

### Setup a new machine

1. Make sure `git` is installed
2. Execute `git clone https://github.com/hpcsc/dotfiles ~/dotfiles && cd ~/dotfiles && ./install.sh | tee install-full.log`
3. Execute `./others/ubuntu/install-gui-apps.sh` to install additional GUI applications

## Common checklist after setup (both MacOS and Ubuntu)

- Copy public and private SSH keys to `~/.ssh` and make sure they're set to `600`
- Remap Capslock to Ctrl (Keyboard settings -> Modifier Keys in Macs or use Gnome Tweak Tool -> Typing -> Caps Lock key behavior'
- Import Jetbrains IDEs (Rider, Intellij) settings from github: https://www.jetbrains.com/help/idea/sharing-your-ide-settings.html#settings-repository
