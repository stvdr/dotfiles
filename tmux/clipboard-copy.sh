#!/bin/sh
# clipboard-copy.sh — Cross-platform clipboard copy (stdin -> system clipboard)
if command -v pbcopy >/dev/null 2>&1; then
    pbcopy
elif command -v wl-copy >/dev/null 2>&1; then
    wl-copy
elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard -i
elif command -v xsel >/dev/null 2>&1; then
    xsel --clipboard --input
fi
