# Ubuntu setup

### Setup a new machine

1. Make sure `git` is installed
2. Execute `git clone https://github.com/hpcsc/dotfiles ~/dotfiles && cd ~/dotfiles && ./up.sh`
3. Set zsh as default shell: `chsh -s $(which zsh)`, logout and login again

### Checklist after setup

- Remap Capslock to Ctrl: `make load-gnome-tweak-tool-config`. This loads config for Gnome Tweak Tool, which can be found at `Tweaks -> Keyboard & Mouse -> Additional Layout Options -> Caps Lock Behavior -> Caps Lock is also a Ctrl`
- Setup vscode: `make setup-vscode`
- Install `aws-profile`: `make install-aws-profile`
- GPG
    - Download GPG key
    - Run `./others/ubuntu/import-gpg-key.sh path-to-downloaded-gpg-key` to import GPG key. Set trust level to 5 (ultimate) when prompted
    - Delete downloaded GPG key
- Download and copy public and private SSH keys to `~/.ssh` and make sure they're set to `600`
