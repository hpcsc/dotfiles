# David Nguyen's dotfiles

I use primarily `homebrew-bundle` and `stow` to manage all of my dotfiles

## To generate a Brewfile for backup

```
brew bundle dump --force
```

## For a new Mac setup

1. Update macOS to the latest version with the App Store
2. Install Xcode from the App Store, open it and accept the license agreement
3. Install macOS Command Line Tools by running `xcode-select --install`
4. Copy public and private SSH keys to `~/.ssh` and make sure they're set to `600`
5. Execute `sudo vim /etc/shells`, append `/usr/local/bin/zsh` at the end of the file and save. `/usr/local/bin/zsh` is the symlink created by Homebrew and in order to be able to change default shell to this, it needs to be in the list of valid shells (`/etc/shells`)
6. Clone this repo to `~/dotfiles`
7. `cd ~/dotfiles` and execute `install.sh`
8. Make ZSH the default shell environment: `chsh -s $(which zsh)`
9. Open `iTerm2` preferences -> `General` -> `Load preferences from a custom folder`, points to `~/dotfiles/iterm`
    - Refresh iTerm2 preferences cache if needed: `defaults read com.googlecode.iterm2`
10. Restart computer to finalize the process
