#!/usr/bin/env bash

set -euo pipefail

sanitize_id() {
    echo "$1" | tr '-' '_' | tr ' ' '_' | tr ':' '_'
}

capitalize() {
    local str="$1"
    local first_char rest
    first_char=$(echo "$str" | cut -c1 | tr '[:lower:]' '[:upper:]')
    rest=$(echo "$str" | cut -c2-)
    echo "${first_char}${rest}"
}

get_prefix() {
    local file="$1"
    case "$file" in
        Taskfile_darwin.yml) echo "macos" ;;
        Taskfile_macos.yml) echo "macos" ;;
        Taskfile_common.yml) echo "common" ;;
        Taskfile_linux.yml) echo "linux" ;;
        Taskfile_ubuntu.yml) echo "ubuntu" ;;
        Taskfile_fedora.yml) echo "fedora" ;;
        *) echo "" ;;
    esac
}

extract_deps() {
    local file="$1"
    local task="$2"

    local deps
    deps=$(yq eval ".tasks[\"$task\"].deps // []" "$file" 2>/dev/null)

    if [[ "$deps" != "[]" && "$deps" != "null" ]]; then
        echo "$deps" | yq eval '.[]' - 2>/dev/null | while read -r dep; do
            dep=$(sanitize_id "$dep")
            echo "$dep"
        done
    fi
}

extract_cmd_deps() {
    local file="$1"
    local task="$2"

    yq eval ".tasks[\"$task\"].cmds[] | .task" "$file" 2>/dev/null | while read -r dep; do
        if [[ -n "$dep" && "$dep" != "null" ]]; then
            dep=$(sanitize_id "$dep")
            echo "$dep"
        fi
    done
}

echo "graph TD"
echo ""

if [[ -f Taskfile.yml ]]; then
    echo "  subgraph Root[Root Tasks]"
    yq eval '.tasks | keys | .[]' Taskfile.yml 2>/dev/null | while read -r task; do
        task=$(sanitize_id "$task")
        echo "    $task[$task]"
    done
    echo "  end"
    echo ""
fi

for file in Taskfile_*.yml; do
    if [[ -f "$file" ]]; then
        prefix=$(get_prefix "$file")
        if [[ -n "$prefix" ]]; then
            capital_prefix=$(capitalize "$prefix")
            echo "  subgraph ${capital_prefix}[${capital_prefix}]"
            yq eval '.tasks | keys | .[]' "$file" 2>/dev/null | while read -r task; do
                task=$(sanitize_id "$task")
                echo "    ${prefix}_$task[$task]"
            done
            echo "  end"
            echo ""
        fi
    fi
done

if [[ -f Taskfile.yml ]]; then
    yq eval '.tasks | keys | .[]' Taskfile.yml 2>/dev/null | while read -r task; do
        task_sanitized=$(sanitize_id "$task")

        while read -r dep; do
            if [[ -n "$dep" ]]; then
                dep_sanitized=$(sanitize_id "$dep")
                echo "  $task_sanitized --> $dep_sanitized"
            fi
        done < <(extract_deps "Taskfile.yml" "$task"; extract_cmd_deps "Taskfile.yml" "$task")
    done
fi

for file in Taskfile_*.yml; do
    if [[ -f "$file" ]]; then
        prefix=$(get_prefix "$file")
        if [[ -n "$prefix" ]]; then
            yq eval '.tasks | keys | .[]' "$file" 2>/dev/null | while read -r task; do
                task_sanitized=$(sanitize_id "$task")
                full_task="${prefix}_${task_sanitized}"

                while read -r dep; do
                    if [[ -n "$dep" ]]; then
                        dep_sanitized=$(sanitize_id "$dep")
                        if [[ "$dep" != *:* ]]; then
                            dep_sanitized="${prefix}_${dep_sanitized}"
                        fi
                        echo "  $full_task --> $dep_sanitized"
                    fi
                done < <(extract_deps "$file" "$task"; extract_cmd_deps "$file" "$task")
            done
        fi
    fi
done

echo ""
echo "  classDef root fill:#f9f,stroke:#333,stroke-width:2px"
echo "  classDef common fill:#bbf,stroke:#333,stroke-width:1px"
echo "  classDef macos fill:#bfb,stroke:#333,stroke-width:1px"
echo "  classDef linux fill:#fbb,stroke:#333,stroke-width:1px"
echo "  classDef ubuntu fill:#fbf,stroke:#333,stroke-width:1px"
echo "  classDef fedora fill:#ffb,stroke:#333,stroke-width:1px"