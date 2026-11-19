# macOS setup

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
4. Execute `sudo vim /etc/shells`, append `/opt/homebrew/bin/zsh` at the end of the file and save. `/opt/homebrew/bin/zsh` is the symlink created by Homebrew and in order to be able to change default shell to this, it needs to be in the list of valid shells (`/etc/shells`)
5. Install [HomeBrew](https://brew.sh/)
6. Execute `git clone https://github.com/hpcsc/dotfiles ~/dotfiles && cd ~/dotfiles && ./up.sh`
7. Make ZSH the default shell environment: `chsh -s $(which zsh)`
8. Install VSCode
9. Execute `./others/macos/vscode/setup.sh` to configure VSCode
10. Setup SSH
- Copy the SSH keys to `~/.ssh` and make sure they're set to `600`: `id_ed25519.hpcsc` for personal repos, `id_ed25519` for work repos.
  Or generate a new key: `ssh-keygen -t ed25519 -C "hpcsc@users.noreply.github.com"`
- `./up.sh` creates `~/.gitconfig-personal` and `~/.gitconfig-work`. They use these keys to sign commits. In `~/.gitconfig-work`, replace `REPLACE_WITH_WORK_EMAIL` with the work email
- Add each key to `~/.git_allowed_signers`, so that git can verify the signatures:

```
for f in ~/.gitconfig-personal ~/.gitconfig-work; do
  echo "$(git config -f $f user.email) namespaces=\"git\" $(cat $(git config -f $f user.signingkey | sed "s|^~|$HOME|"))" >> ~/.git_allowed_signers
done
```

11. (Optional) Setup GPG
- Install GnuPG for OS X from https://gnupg.org/download/
- If moving GPG from another computer over:
    - In the other computer, execute `./others/common/backup-gpg.sh` to back up GPG to `./tmp/gpg` folder
    - Copy above `./tmp/gpg` from the other computer over to the new computer
    - Execute `./others/common/restore-gpg.sh path/to/gpg/folder` to restore GPG keys in the new computer
- If generating new GPG keys, follow instructions at https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key
12. Restart computer to finalize the process

### Checklist after setup

- Install Dropbox
- Install Alfred, set preferences folder to Alfred folder in Dropbox
- Install Obsidian, open Obsidian folder in Dropbox as vault
- Install Jetbrains Toolbox
    - Import settings from Dropbox: File -> Manage IDE Settings -> Import Settings
    - Install [Gruvbox theme](https://github.com/caleb/gruvbox-idea/blob/master/GruvboxDarkHard.icls) for Goland (where `X.X` is the currently installed version):
        ```
        mkdir ~/Library/Application\ Support/JetBrains/GoLandX.X/colors
        cp ~/Dropbox/Tools/Jetbrains/GruvboxDarkHard.icls ~/Library/Application\ Support/JetBrains/GoLandX.X/colors
        ```
- Install [Loop](https://github.com/MrKai77/Loop), then import the keybinds from `others/macos/loop/keybinds.json` (Loop Settings -> Keybinds -> Import)
- Docker, .NET, Tailscale, [Caffeinate](https://github.com/LennardKittner/Caffeinate), [Zettlr](https://www.zettlr.com), Bartender, Kap, Shottr, 1Password
- Enable `Use F1, F2, etc keys as standard function keys` in Keyboard settings
- Remap Capslock to Ctrl (Keyboard settings -> Modifier Keys)

### Manual macOS settings

The install does not change the Mail and Calendar settings. macOS keeps the settings of these apps in their sandbox containers, and a terminal can write there only when it has Full Disk Access. Set them by hand after the install.

#### Mail

In Mail > Settings > Composing, set **Check spelling** to **Never**.

The Mail settings window has no control for the other settings. To set them:

1. In System Settings > Privacy & Security > Full Disk Access, turn on your terminal app.
2. Quit the terminal app and open it again.
3. Quit Mail.
4. Run these commands:

```sh
# Do not show an animation when you reply or send
defaults write com.apple.mail DisableReplyAnimations -bool true
defaults write com.apple.mail DisableSendAnimations -bool true

# Copy an address as foo@example.com, not as Foo Bar <foo@example.com>
defaults write com.apple.mail AddressesIncludeNameOnPasteboard -bool false

# Show attachments as icons, not as previews in the message
defaults write com.apple.mail DisableInlineAttachmentViewing -bool true
```

After the commands, you can turn off Full Disk Access for the terminal app again.

#### Calendar

In Calendar > Settings > General, set:

- **Start week on** to **Monday**
- **Show** to **24** hours at a time
