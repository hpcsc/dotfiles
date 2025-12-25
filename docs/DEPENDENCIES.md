# Script Dependencies

This document documents implicit dependencies between installation scripts that are not explicitly defined in the Taskfile.

## Core Dependency Chain

```
common-rust.sh → common-mise.sh → common-stow.sh → common-mise-global.sh
```

- `common-rust.sh`: Installs rustup/cargo - **no dependencies**
- `common-mise.sh`: Installs mise to `~/.local/bin/mise` - **requires rust** (for cargo to install yazi)
- `common-stow.sh`: Creates symlinks including `~/.config/mise/config.toml` - **requires stow binary** from OS package manager
- `common-mise-global.sh`: Installs global tools using mise - **requires mise + stow** (both mise binary and config file)

## Script Groups

### Base Scripts (No Dependencies)
These can run in parallel before core installation:
- `common-working-folders.sh`: Creates working folders (`~/Workspace`, `~/Personal`, `~/Tools`)
- `common-prezto.sh`: Installs prezto shell framework
- `common-fonts.sh`: Installs Fira Code fonts

### Core Scripts (Critical Chain)
These must run sequentially:
1. `common-rust.sh`: No dependencies
2. `common-mise.sh`: Depends on `common-rust.sh` (uses cargo)
3. `common-stow.sh`: Depends on stow binary (installed by OS)
4. `common-mise-global.sh`: Depends on `common-mise.sh` and `common-stow.sh`

### Devtools Scripts (Require Core)
These can run in parallel after core completes:
- `common-vim.sh`: Installs Vim plugins - **requires mise** (for Go SDK/fzf plugin)
- `common-neovim.sh`: Installs Neovim plugins - **requires mise** (uses `mise exec neovim`)
- `common-tmux.sh`: Installs tmux plugins - **requires stow** (needs `~/.tmux.conf` for plugin list)

### Langtools Scripts (Require Core)
These can run in parallel after core completes:
- `common-configure-yazi.sh`: Installs yazi plugins - **requires mise** (uses `mise exec cargo:yazi-cli`)

### Optional Scripts
These are run manually after main installation:
- `common-krew.sh`: Installs kubectl plugins - **requires kubectl** (from `common-asdf-plugins.sh`)
- `common-istio.sh`: Installs Istio - **requires working-folders** (for `~/Tools/` directory)
- `ubuntu-net-core.sh`: Installs .NET Core (Ubuntu only)

## Platform-Specific Dependencies

### macOS
- `macos-keep-sudo.sh`: No dependencies
- `macos-brew-bundle.sh`: Depends on `macos-keep-sudo.sh` (for sudo access)
- `macos-stow.sh`: Depends on `macos-brew-bundle.sh` (installs stow)
- `macos-settings.sh`: Depends on stow (reads dotfile configs)
- `macos-imagemagick.sh`: Depends on `common-working-folders.sh` (for `~/Personal/Tools/`)

### Ubuntu
- `ubuntu-install-sudo.sh`: No dependencies
- `ubuntu-install-required-packages.sh`: Depends on `ubuntu-install-sudo.sh`
- `ubuntu-install-common-tools.sh`: Depends on `ubuntu-install-required-packages.sh` (installs stow)
- `ubuntu-docker.sh`: No dependencies
- `ubuntu-stow.sh`: Depends on `ubuntu-install-common-tools.sh`
- `ubuntu-ripgrep.sh`: No dependencies
- `ubuntu-keyboard.sh`: No dependencies
- `ubuntu-wezterm.sh`: No dependencies
- `ubuntu-net-core.sh`: No dependencies

### Fedora
- `fedora-install-required-packages.sh`: No dependencies
- `fedora-install-common-tools.sh`: Depends on `fedora-install-required-packages.sh` (installs stow)
- `fedora-docker.sh`: No dependencies

## Taskfile Execution Order

The Taskfile enforces these dependencies:

```
default →
├── macos:base/ubuntu:base/fedora:base
│   └── common:base (parallel: working-folders, prezto, aqua, fonts)
├── common:core (sequential: rust → mise → stow → mise-global)
├── common:devtools (parallel: vim, neovim, tmux)
├── common:langtools (parallel: configure-yazi, python-tools)
└── macos:settings/ubuntu:extras/fedora:extras
```

## Key Notes

1. **Working folders**: Created by `common-working-folders.sh` in base, used by:
   - `common-istio.sh` (extracts to `~/Tools/`)
   - `macos-imagemagick.sh` (installs to `~/Personal/Tools/`)
   - `macos-settings.sh` (configures finder to use `~/Workspace/`)

2. **Stow**: Required by scripts that need configuration files:
   - `common-mise-global.sh` (needs `~/.config/mise/config.toml`)
   - `common-tmux.sh` (needs `~/.tmux.conf` for plugin list)
   - Platform-specific stow scripts create additional symlinks

3. **Mise**: Used extensively after core installation:
   - `common-vim.sh` (Go SDK for fzf plugin)
   - `common-neovim.sh` (exec neovim)
   - `common-configure-yazi.sh` (exec cargo:yazi-cli)
   - `common-mise-global.sh` (install global tools)
