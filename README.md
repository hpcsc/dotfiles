# David Nguyen's dotfiles

## Tools

- `stow`: manage symlinks in both MacOS and Ubuntu
- `homebrew-bundle`: backup and restore brew packages (MacOS only)

## MacOS

### To generate a Brewfile for backup

```
brew bundle dump --force
```

### To backup list of VSCode extensions

```
code --list-extensions >! ./scripts/macos/vscode-extensions
```

### Setup a new machine

1. Update macOS to the latest version with the App Store
2. Install Xcode from the App Store, open it and accept the license agreement
3. Install macOS Command Line Tools by running `xcode-select --install`
4. Execute `sudo vim /etc/shells`, append `/usr/local/bin/zsh` at the end of the file and save. `/usr/local/bin/zsh` is the symlink created by Homebrew and in order to be able to change default shell to this, it needs to be in the list of valid shells (`/etc/shells`)
5. Execute `git clone https://github.com/hpcsc/dotfiles ~/dotfiles && cd ~/dotfiles && ./install.sh | tee install-log`
6. Make ZSH the default shell environment: `chsh -s $(which zsh)`
7. Open `iTerm2` preferences -> `General` -> `Load preferences from a custom folder`, points to `~/dotfiles/iterm`
    - Refresh iTerm2 preferences cache if needed: `defaults read com.googlecode.iterm2`
8. Execute `./scripts/macos/install-gui-apps.sh` to install GUI applications
9. Execute `./scripts/macos/tools.sh` to install necessary VSCode extensions
10. Restart computer to finalize the process

### Checklist after setup

- Install .NET Core, Authy, Boostnote, Caffeine, Jetbrains Toolbox
- Enable "Use F1, F2, etc keys as standard function keys" in Keyboard settings

## Ubuntu

### Setup a new machine

1. Make sure `git` is installed
2. Execute `git clone https://github.com/hpcsc/dotfiles ~/dotfiles && cd ~/dotfiles && ./install-debian.sh | tee install-log`

## Common checklist after setup (both MacOS and Ubuntu)

- Copy public and private SSH keys to `~/.ssh` and make sure they're set to `600`
- Remap Capslock to Ctrl (Keyboard settings -> Modifier Keys)
- Import Jetbrains IDEs (Rider, Intellij) settings from github: https://www.jetbrains.com/help/idea/sharing-your-ide-settings.html#settings-repository
