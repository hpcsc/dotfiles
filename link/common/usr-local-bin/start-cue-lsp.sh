#!/bin/bash

# Start CUE LSP server for OpenCode
# This script starts 'cue lsp serve' if:
# - 'cue' command is available
# - 'cue version' is at least 0.15.0

set -e

# Check if cue command is available
if ! command -v cue &> /dev/null; then
    echo "cue command not found" >&2
    exit 1
fi

# Get cue version
CUE_VERSION=$(cue version 2>/dev/null | grep -E '^cue version\s+v[0-9]+\.[0-9]+\.[0-9]+' | sed -E 's/cue version\s+v([0-9]+\.[0-9]+\.[0-9]+).*/\1/' || echo "")

if [ -z "$CUE_VERSION" ]; then
    echo "Failed to get cue version" >&2
    exit 1
fi

# Compare versions (requires >= 0.15.0)
MIN_VERSION="0.15.0"

# Simple version comparison
if printf '%s\n' "$MIN_VERSION" "$CUE_VERSION" | sort -V | head -n1 | grep -q "^$MIN_VERSION$"; then
    # Version is >= 0.15.0, check if LSP server is already running
    
    
    
    cue lsp serve

    
else
    echo "cue version $CUE_VERSION is too old (need >= $MIN_VERSION)" >&2
    exit 1
fi
