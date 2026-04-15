#!/bin/bash
# pane-border-info.sh — Shows git branch and linked PR in tmux pane border
#
# Usage: pane-border-info.sh <pane_pid>
# Caches PR lookups per repo+branch for 5 minutes to avoid GitHub API rate limits.
# PR lookups run in the background so the branch name shows instantly.

PANE_PID="$1"
CACHE_DIR="/tmp/tmux-pr-cache"
CACHE_TTL=300  # 5 minutes

# Skip panes running Claude Code
if ps -axo ppid=,comm= | awk -v ppid="$PANE_PID" '$1 == ppid && $2 == "claude" { found=1; exit } END { exit !found }'; then
    exit 0
fi

# Get the pane's current working directory
PANE_CWD=$(readlink /proc/$PANE_PID/cwd 2>/dev/null)
if [ -z "$PANE_CWD" ]; then
    # macOS: use lsof to find cwd
    PANE_CWD=$(lsof -p "$PANE_PID" -a -d cwd -Fn 2>/dev/null | grep '^n' | head -1 | cut -c2-)
fi
[ -z "$PANE_CWD" ] && exit 0

# Check if it's a git repo and read branch — all lock-free
GIT_DIR=$(git -C "$PANE_CWD" --no-optional-locks rev-parse --git-dir 2>/dev/null) || exit 0
if [ "${GIT_DIR}" = "${GIT_DIR#/}" ]; then
    GIT_DIR="$PANE_CWD/$GIT_DIR"
fi

HEAD=$(cat "$GIT_DIR/HEAD" 2>/dev/null) || exit 0
if [[ "$HEAD" == ref:* ]]; then
    BRANCH="${HEAD#ref: refs/heads/}"
else
    BRANCH="${HEAD:0:7}"
fi
[ -z "$BRANCH" ] && exit 0

# Cache key from repo root + branch
REPO_ROOT=$(git -C "$PANE_CWD" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
CACHE_KEY=$(echo "${REPO_ROOT}:${BRANCH}" | tr '/' '_')
mkdir -p "$CACHE_DIR"
CACHE_FILE="$CACHE_DIR/$CACHE_KEY"

# Read cached PR info
PR_INFO=""
NEEDS_REFRESH=1
if [ -f "$CACHE_FILE" ]; then
    CACHE_AGE=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
    if [ "$CACHE_AGE" -lt "$CACHE_TTL" ]; then
        NEEDS_REFRESH=0
    fi
    PR_INFO=$(cat "$CACHE_FILE")
fi

# Refresh cache in background if stale (non-blocking)
if [ "$NEEDS_REFRESH" -eq 1 ] && command -v gh >/dev/null 2>&1; then
    LOCK_FILE="${CACHE_FILE}.lock"
    # Skip if another refresh is already running
    if ! [ -f "$LOCK_FILE" ]; then
        (
            touch "$LOCK_FILE"
            REMOTE=$(git -C "$PANE_CWD" --no-optional-locks remote get-url origin 2>/dev/null)
            PR_JSON=$(gh pr view --repo "$REMOTE" "$BRANCH" --json number,title,url 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$PR_JSON" ]; then
                PR_NUM=$(echo "$PR_JSON" | jq -r '.number // empty' 2>/dev/null)
                PR_TITLE=$(echo "$PR_JSON" | jq -r '.title // empty' 2>/dev/null)
                PR_URL=$(echo "$PR_JSON" | jq -r '.url // empty' 2>/dev/null)
                [ -n "$PR_NUM" ] && printf '%s\t%s\t%s\n' "$PR_NUM" "$PR_TITLE" "$PR_URL" > "$CACHE_FILE" || echo "" > "$CACHE_FILE"
            else
                echo "" > "$CACHE_FILE"
            fi
            rm -f "$LOCK_FILE"
        ) &
    fi
fi

# Format output — show immediately with whatever we have
if [ -n "$PR_INFO" ]; then
    # Parse cached tab-separated format: number\ttitle\turl
    PR_NUM=$(echo "$PR_INFO" | cut -f1)
    PR_TITLE=$(echo "$PR_INFO" | cut -f2)
    PR_URL=$(echo "$PR_INFO" | cut -f3)

    TITLE_MAX=40
    if [ ${#PR_TITLE} -gt $TITLE_MAX ]; then
        PR_TITLE="${PR_TITLE:0:$((TITLE_MAX - 3))}..."
    fi

    if [ -n "$PR_URL" ]; then
        echo " $BRANCH · #${PR_NUM}: ${PR_TITLE} · $PR_URL "
    else
        echo " $BRANCH · #${PR_NUM}: ${PR_TITLE} "
    fi
else
    echo " $BRANCH "
fi
