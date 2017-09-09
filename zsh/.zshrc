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
export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH:$HOME/.local/bin"
export MANPATH="/usr/local/opt/coreutils/libexec/gnuman:$MANPATH"
