#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

# Customize to your needs...
eval "$(fasd --init auto)"

# changes hex 0x15 to delete everything to the left of the cursor, rather than the whole line
bindkey "^U" backward-kill-line

# bind redo (hexcode 0x18 0x1f)
bindkey "^X^_" redo

# utility function, used by all functions under .functions
function execute() {
    printf '%s' "Executing: $1"
    echo '\n====================='
    eval $1
}

source ~/.aliases
for func_def in ~/.functions/*; do
    source "$func_def"
done

OS=$(uname 2> /dev/null)
if [ "$OS" = "Darwin" ]; then
    source /usr/local/share/antigen/antigen.zsh
else
    source /usr/share/antigen/antigen.zsh
fi
antigen init ~/.antigenrc

source ~/.asdf/asdf.sh
source ~/.asdf/completions/asdf.bash

export CLICOLOR=1
export TERM=xterm-256color
export EDITOR=vim

# OS-specific customization
[[ -f ~/.zshrc-$OS ]] && source ~/.zshrc-$OS

# machine-specific customization
[[ -f ~/.local-zshrc ]] && source ~/.local-zshrc
