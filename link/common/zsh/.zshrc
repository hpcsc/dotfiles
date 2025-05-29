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

# =================== prezto  ===================
source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"

# =================== misc  ===================
# disable zsh bundled function mtools command mcd
# which causes a conflict with our custom function mcd
compdef -d mcd

# =================== mise =======================
eval "$(~/.local/bin/mise activate zsh)"

# =================== aqua =======================
export PATH="${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}/bin:$PATH"

# =================== zoxide  ===================
# must be after activating mise

# Lazy initialising zoxide
z() {
  # Remove this function, subsequent calls will execute 'z' directly
  unfunction "$0"

  # init
  eval "$(zoxide init zsh)"

  # Execute 'z' binary
  $0 "$@"
}

# =================== fzf ========================
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export FZF_DEFAULT_COMMAND='rg --files --hidden --smart-case --sort-files --follow --glob "!.git/*"'
export FZF_DEFAULT_OPTS="--reverse --height 30%"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd -t d"
export FZF_ALT_C_OPTS="
  --walker-skip .git,node_modules,target
  --preview-window=bottom
  --preview 'tree -C {}'"

# =================== tmux  ======================
[[ -f ~/.bin/tmuxinator.zsh ]] && source ~/.bin/tmuxinator.zsh

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

# bind Ctrl-y to trigger yazi
bindkey -s '^y' 'yazi^M'

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

# bind Ctrl-backspace
_backward-kill-non-dash () {
  # remove - and _ from word definition so that word deletion stops at the first - or _ character
  local WORDCHARS=${WORDCHARS/_-//}
  zle backward-kill-word
  zle -f kill
}
zle -N _backward-kill-non-dash
bindkey "^H" _backward-kill-non-dash

# bind Ctrl-left
_backward-non-dash () {
  # remove - and _ from word definition so that word backword navigation stops at the first - or _ character
  local WORDCHARS=${WORDCHARS/_-//}
  zle backward-word
}
zle -N _backward-non-dash
bindkey "^[[1;5D" _backward-non-dash

# bind Ctrl-right
_forward-non-dash () {
  # remove - and _ from word definition so that word forward navigation stops at the first - or _ character
  local WORDCHARS=${WORDCHARS/_-//}
  zle forward-word
}
zle -N _forward-non-dash
bindkey "^[[1;5C" _forward-non-dash

# ref: https://unix.stackexchange.com/a/531178
_clear-scrollback-buffer () {
  # Behavior of clear:
  # 1. clear scrollback if E3 cap is supported (terminal, platform specific)
  # 2. then clear visible screen
  # For some terminal 'e[3J' need to be sent explicitly to clear scrollback
  clear && printf '\e[3J'
  # .reset-prompt: bypass the zsh-syntax-highlighting wrapper
  # https://github.com/sorin-ionescu/prezto/issues/1026
  # https://github.com/zsh-users/zsh-autosuggestions/issues/107#issuecomment-183824034
  # -R: redisplay the prompt to avoid old prompts being eaten up
  # https://github.com/Powerlevel9k/powerlevel9k/pull/1176#discussion_r299303453
  zle && zle .reset-prompt && zle -R
}

zle -N _clear-scrollback-buffer
bindkey '^L' _clear-scrollback-buffer

# bind Ctrl-F to invoke fzf and insert result of file selection to current location of cursor
_insert_quoted_fzf_output() {
  local output
  output=$(fzf</dev/tty)
  if [ -z "${output}" ]; then
    zle reset-prompt
    return
  fi

  LBUFFER+=${(q-)output}
  zle reset-prompt
}

zle -N _insert_quoted_fzf_output
bindkey '^F' _insert_quoted_fzf_output

### Jetbrains terminal
if [[ "$TERMINAL_EMULATOR" == "JetBrains-JediTerm" ]]; then
  # alt + c
  bindkey "ç" fzf-cd-widget
fi

# =================== prompt  ======================

eval "$(mise exec starship -- starship init zsh)"

# ======== load additional rc files ==============
#
# OS-specific customization
OS=$(distro_name)
[[ -f ~/.zshrc-$OS ]] && source ~/.zshrc-$OS

# machine-specific customization
[[ -f ~/.zshrc-local ]] && source ~/.zshrc-local
