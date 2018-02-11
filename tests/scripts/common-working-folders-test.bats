#!./libs/bats/bin/bats

load '../../libs/bats-support/load'
load '../../libs/bats-assert/load'

function setup() {
  source link/common/zsh/.functions/misc
  export -f echo_with_color echo_yellow
}

@test "common-working-folders.sh: Should print script header" {
  run scripts/common-working-folders.sh
  assert_output --partial 'Create working folders'
}
