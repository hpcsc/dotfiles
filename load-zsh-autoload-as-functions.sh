#!/bin/bash

# ugly workaround to load zsh autoload functions as normal shell functions, to be used in install.sh
autoload_functions=(
  execute
  echo_with_color 
  echo_blue 
  echo_red
  echo_cyan
  echo_green
  echo_purple
  echo_yellow
  is_macos
  is_ubuntu
  distro_name
)

for f in "${autoload_functions[@]}"
do
  eval "
    function $f() {
      $(cat ./link/common/zsh/.functions/misc/$f)
    }
  "
done
