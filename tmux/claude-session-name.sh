#!/bin/bash
# claude-session-name.sh — Returns a formatted name for tmux windows
#
# Claude windows:  "[✴] label" or "◷ [✴] label" when busy
# Other windows:   "[shell] command" or "[shell] last_command" when idle
#
# Usage: claude-session-name.sh <pane_pid> <pane_current_command> <tmux_pane_id>

PANE_PID="$1"
CURRENT_CMD="$2"
PANE_ID="$3"
MAX_LABEL=25

# Get shell name from pane PID
SHELL_NAME=$(ps -o comm= -p "$PANE_PID" 2>/dev/null)
SHELL_NAME="${SHELL_NAME#-}"       # Strip login shell dash
SHELL_NAME="${SHELL_NAME##*/}"     # Strip path prefix

# --- Claude window (version string as process title) ---
if [[ "$CURRENT_CMD" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    PS_TABLE=$(ps -axo pid=,ppid=,comm=)
    CLAUDE_PID=$(echo "$PS_TABLE" | awk -v ppid="$PANE_PID" '$2 == ppid && $3 == "claude" { print $1; exit }')

    if [ -z "$CLAUDE_PID" ]; then
        echo "[$CURRENT_CMD]"
        exit 0
    fi

    # Busy = has children other than caffeinate (macOS-only process, harmless on Linux)
    BUSY=$(echo "$PS_TABLE" | awk -v ppid="$CLAUDE_PID" '$2 == ppid && $3 != "caffeinate" { found=1; exit } END { if (found) print 1 }')

    SESSION_FILE="$HOME/.claude/sessions/${CLAUDE_PID}.json"
    if [ ! -f "$SESSION_FILE" ]; then
        [ -n "$BUSY" ] && echo "◷ [✴]" || echo "[✴]"
        exit 0
    fi

    # Read cwd and name in one jq call
    if command -v jq >/dev/null 2>&1; then
        eval "$(jq -r '"CWD=\(.cwd // "")\nNAME=\(.name // "")"' "$SESSION_FILE" 2>/dev/null)"
    else
        CWD=""; NAME=""
    fi

    LABEL=""
    if [[ "$CWD" =~ /.claude/worktrees/([^/]+) ]]; then
        LABEL="${BASH_REMATCH[1]}"
    elif [ -n "$NAME" ]; then
        LABEL="$NAME"
    elif [ -n "$CWD" ]; then
        LABEL="$(basename "$CWD")"
    fi

    LABEL="${LABEL:-session}"
    if [ ${#LABEL} -gt $MAX_LABEL ]; then
        LABEL="${LABEL:0:$((MAX_LABEL - 3))}..."
    fi

    [ -n "$BUSY" ] && echo "◷ [✴] ${LABEL}" || echo "[✴] ${LABEL}"
    exit 0
fi

# --- Non-Claude: command currently running ---
if [ "$CURRENT_CMD" != "$SHELL_NAME" ]; then
    CHILD_PID=$(ps -axo pid=,ppid=,comm= | awk -v ppid="$PANE_PID" -v cmd="$CURRENT_CMD" '$2 == ppid && $3 == cmd { print $1; exit }')

    if [ -n "$CHILD_PID" ]; then
        CHILD_ARGS=$(ps -o args= -p "$CHILD_PID" 2>/dev/null | sed 's/^ *//')
    else
        CHILD_ARGS="$CURRENT_CMD"
    fi

    if [ ${#CHILD_ARGS} -gt $MAX_LABEL ]; then
        CHILD_ARGS="${CHILD_ARGS:0:$((MAX_LABEL - 3))}..."
    fi

    echo "[${SHELL_NAME}] ${CHILD_ARGS}"
    exit 0
fi

# --- Non-Claude: idle shell — show last command if available ---
LAST_CMD_FILE="/tmp/tmux-last-cmd-${PANE_ID#%}"
if [ -f "$LAST_CMD_FILE" ]; then
    LAST_CMD=$(cat "$LAST_CMD_FILE" 2>/dev/null)
    if [ -n "$LAST_CMD" ]; then
        if [ ${#LAST_CMD} -gt $MAX_LABEL ]; then
            LAST_CMD="${LAST_CMD:0:$((MAX_LABEL - 3))}..."
        fi
        echo "[${SHELL_NAME}] ${LAST_CMD}"
        exit 0
    fi
fi

echo "[${SHELL_NAME}]"
