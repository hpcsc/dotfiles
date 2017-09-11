#!/bin/sh

# Usage: backup source_folder target_folder backup_folder
# iterate source_folder recursively, if found any file/folder with same name in target_folder,
# move that file/folder to backup_folder, keep structure of folder
function backup() {
    local source_folder=$1
    local target_folder=$2
    local backup_folder=$3

    mkdir -p $backup_folder

    for f in "$source_folder"/*; do
        base_name=$(basename $f)
        local target="$target_folder/$base_name"
        if [[ -d $f ]]; then
            if [[ -d $target ]]; then
                backup $f $target "$backup_folder/$base_name"
            fi
        elif [[ -f $target ]]; then
            echo "moving $target to $backup_folder"
            mv $target $backup_folder
        fi
    done
}
