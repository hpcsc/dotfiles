[ -f ~/.fzf.bash ] && source ~/.fzf.bash

# Unicode characters:
# ✔ 'heavy check mark' (U+2714) 
# ✘ 'heavy ballot x' (U+2718)
# ❯ 'heavy right-pointing angle quotation mark ornament' (U+276F)
export PS1='`if [ $? = 0 ]; then echo "\[\e[32m\] ✔ "; else echo "\[\e[31m\] ✘ "; fi` \[\e[1;34m\]\w \[\033[38;5;9m\]❯\[\033[38;5;11m\]❯\[\033[38;5;10m\]❯\[\e[0m\] '

source ~/.aliases

