#!/bin/bash

if [ ! -f ./bin/task ]; then
    echo "Installing Taskfile"
    ./install-taskfile.sh
fi

export PATH="${PATH}:$(pwd)/bin"

task up
