#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

export CLICOLOR=1
export TERM=xterm-256color

# ====== source custom aliases, functions  ==========
#
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

# =================== fasd  ===================
eval "$(fasd --init auto)"

# =================== antigen  ===================
OS=$(uname 2> /dev/null)
if [ "$OS" = "Darwin" ]; then
    source /usr/local/share/antigen/antigen.zsh
else
    source /usr/share/antigen/antigen.zsh
fi
antigen init ~/.antigenrc

# =================== asdf =======================
source ~/.asdf/asdf.sh
source ~/.asdf/completions/asdf.bash

# =================== fzf ========================
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export FZF_DEFAULT_COMMAND='rg --files --hidden --sort-files --follow --glob "!.git/*"'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# =================== tmux  ======================
[[ -f ~/.bin/tmuxinator.zsh ]] && source ~/.bin/tmuxinator.zsh


# ============ custom key bindings  ==============
# changes hex 0x15 to delete everything to the left of the cursor, rather than the whole line
bindkey "^U" backward-kill-line

# bind redo (hexcode 0x18 0x1f)
bindkey "^X^_" redo

# bind Ctrl-Space to accept zsh auto suggestion
bindkey '^ ' autosuggest-accept

# ======== load additional rc files ==============
#
# OS-specific customization
[[ -f ~/.zshrc-$OS ]] && source ~/.zshrc-$OS

# machine-specific customization
[[ -f ~/.local-zshrc ]] && source ~/.local-zshrc
