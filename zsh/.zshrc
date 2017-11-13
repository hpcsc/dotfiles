#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

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

export GOPATH=$HOME/Documents/Workspace/Code/Go
export CLICOLOR=1
export TERM=xterm-256color
export EDITOR=vim
export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH:$HOME/.local/bin"
export MANPATH="/usr/local/opt/coreutils/libexec/gnuman:$MANPATH"
