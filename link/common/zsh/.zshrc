#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

export CLICOLOR=1
export TERM=xterm-256color
export KEYTIMEOUT=1  # set zsh vi mode timeout to 0.1s when switching mode
export WORDCHARS='*?_-[]~&;!#$%^(){}<>'

export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$HOME/.cargo/bin:$PATH"

# ====== set terminal title ======================

function set_terminal_title() {
  local mode=$1 ;
  shift
  print -Pn "\e]${mode};$@\a"
}

precmd () {
  # mode: 0 - both, 1 - tab title, 2 - window title
  # reference: https://superuser.com/a/344397
  set_terminal_title 1 "%C" # %C is to display trailing component of current directory
  set_terminal_title 2 "%~" # %~ is to display current working directory
}

# ====== source custom aliases ======================
source ~/.aliases
[[ -f ~/.aliases-local ]] && source ~/.aliases-local

# ====== source custom shell functions ==============
source ~/.common-shell-functions.sh

# ====== autoload custom functions ==================
fpath=($fpath ~/.functions)
autoload -Uz ~/.functions/**/*

# =================== fasd  ===================
eval "$(fasd --init auto)"

# =================== prezto  ===================
source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"

# =================== asdf =======================
source ~/.asdf/asdf.sh

# =================== fzf ========================
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export FZF_DEFAULT_COMMAND='rg --files --hidden --smart-case --sort-files --follow --glob "!.git/*"'
export FZF_DEFAULT_OPTS="--reverse --height 30%"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd -t d"

# =================== tmux  ======================
[[ -f ~/.bin/tmuxinator.zsh ]] && source ~/.bin/tmuxinator.zsh

# =================== direnv  ======================
eval "$(direnv hook zsh)"

# ============ custom key bindings  ==============
# changes hex 0x15 to delete everything to the left of the cursor, rather than the whole line
bindkey "^U" backward-kill-line

# bind redo (hexcode 0x18 0x1f)
bindkey "^X^_" redo

# bind Ctrl-Space to accept zsh auto suggestion
bindkey '^ ' autosuggest-accept

bindkey '^p' fzf-file-widget

# bind Ctrl-z to fg command (.e.g. to switch from terminal back to suspended vim session)
bindkey -s '^z' 'fg^M'

# bind Ctrl-t to trigger gitui
bindkey -s '^t' 'gitui^M'

# bind Ctrl-j/k to do cycle through history substring search
bindkey "^k" history-substring-search-up
bindkey "^j" history-substring-search-down

# custom function and zsh zle widget to get last commit message and output git commit command
# bind Ctrl-g to this custom zle widget
function _git_last_message() {
  BUFFER=${LBUFFER}'git commit -m "'$(git log -1 --pretty=%s)'"'
  zle end-of-line;
}
zle -N _git_last_message
bindkey "^g" _git_last_message

# ======== load additional rc files ==============
#
# OS-specific customization
OS=$(distro_name)
[[ -f ~/.zshrc-$OS ]] && source ~/.zshrc-$OS

# machine-specific customization
[[ -f ~/.zshrc-local ]] && source ~/.zshrc-local
