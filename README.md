# David Nguyen's dotfiles

I use primarily `homebrew-bundle` and `stow` to manage all of my dotfiles

## To generate a Brewfile for backup

```
brew bundle dump --force
```

## To backup list of VSCode extensions

```
code --list-extensions >! vscode-extensions
```

## For a new Mac setup

1. Update macOS to the latest version with the App Store
2. Install Xcode from the App Store, open it and accept the license agreement
3. Install macOS Command Line Tools by running `xcode-select --install`
4. Copy public and private SSH keys to `~/.ssh` and make sure they're set to `600`
5. Execute `sudo vim /etc/shells`, append `/usr/local/bin/zsh` at the end of the file and save. `/usr/local/bin/zsh` is the symlink created by Homebrew and in order to be able to change default shell to this, it needs to be in the list of valid shells (`/etc/shells`)
6. Clone this repo to `~/dotfiles`
7. `cd ~/dotfiles` and execute `install.sh | tee install-log`
8. Make ZSH the default shell environment: `chsh -s $(which zsh)`
9. Open `iTerm2` preferences -> `General` -> `Load preferences from a custom folder`, points to `~/dotfiles/iterm`
    - Refresh iTerm2 preferences cache if needed: `defaults read com.googlecode.iterm2`
10. Execute `./install-gui-apps.sh` to install GUI applications
11. Execute `./tools.sh` to install necessary VSCode extensions
12. Restart computer to finalize the process

**Note**
```
It's not possible to automate installation of .NET Core on MacOS yet (unless using Brew Cask which is unstable). Ubuntu script (install-debian.sh) already has .NET Core installed automatically
```

## Ubuntu setup
1. Make sure `git` is installed
2. Execute `git clone https://github.com/hpcsc/dotfiles ~/dotfiles && cd ~/dotfiles && ./install-debian.sh | tee install-log`
3. Setup `ripgrep`
4. Setup `fzf`
    - Use `asdf` to install latest Go SDK
    - `sudo git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install`

## Checklist after setting up

- Remap Capslock to Ctrl
