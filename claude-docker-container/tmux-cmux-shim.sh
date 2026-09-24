#!/usr/bin/env bash
# tmux-cmux-shim.sh
# Replaces tmux to intercept Claude Code Agent Teams tmux calls
# and redirect pane/window creation into native cmux desktop splits via cmux CLI,
# while keeping all agent executions inside the single container/sandbox for shared IPC.

set -e

# Log all invocations for transparency and debugging
echo "$(date '+%Y-%m-%d %H:%M:%S') [shim] tmux called with: $*" >> /tmp/tmux_shim.log 2>/dev/null || true

# Strip global tmux flags (-S <path>, -L <name>, -u, -v, -V, etc.)
while [ $# -gt 0 ]; do
    case "$1" in
        -V|-v)
            echo "tmux 3.4"
            exit 0
            ;;
        -S|-L|-c|-f)
            shift 2
            ;;
        -2|-C|-D|-l|-N|-u)
            shift
            ;;
        -*)
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Ensure fake TMUX and experimental agent teams variables are set
export TMUX="${TMUX:-/tmp/fake-tmux-sock,0,0}"
export TMUX_PANE="${TMUX_PANE:-%0}"
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# Determine container or sandbox target
CONTAINER_TARGET="${CONTAINER_NAME:-claude-teams}"
SANDBOX_TARGET="${SANDBOX_NAME:-claude-teams-sbx}"
IS_SBX="${IS_SANDBOX:-0}"

# Function to build execution command on the host (sbx or docker)
build_host_exec_cmd() {
    local cmd_args="$1"
    local cwd_dir
    if [ -n "${CWD:-}" ] && [ -d "$CWD" ]; then
        cwd_dir="$(cd "$CWD" 2>/dev/null && pwd -P)"
    else
        cwd_dir="$(pwd -P)"
    fi
    if [ "$IS_SBX" = "1" ] || [ -n "$SANDBOX_NAME" ]; then
        if [ -n "$cmd_args" ]; then
            echo "exec env PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin sbx exec -w \"${cwd_dir}\" -it ${SANDBOX_TARGET} ${cmd_args}"
        else
            echo "exec env PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin sbx exec -w \"${cwd_dir}\" -it ${SANDBOX_TARGET} bash"
        fi
    else
        if [ -n "$cmd_args" ]; then
            echo "exec env PATH=/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin docker exec -u node -it ${CONTAINER_TARGET} ${cmd_args}"
        else
            echo "exec env PATH=/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin docker exec -u node -it ${CONTAINER_TARGET} bash"
        fi
    fi
}

# Helper to create a teammate runner script that waits for respawn-pane command
create_teammate_runner() {
    local pane_id="$1"
    local runner_file="/tmp/teammate_runner_${pane_id}.sh"
    local cmd_file="/tmp/teammate_cmd_${pane_id}"
    local log_file="/tmp/teammate_${pane_id}.log"

    rm -f "$cmd_file" "$runner_file"
    cat << 'RUNNER_EOF' > "$runner_file"
#!/usr/bin/env bash
PANE_ID="REPLACE_PANE_ID"
CMD_FILE="/tmp/teammate_cmd_${PANE_ID}"
LOG_FILE="/tmp/teammate_${PANE_ID}.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') [cmux] Runner started for pane %${PANE_ID}" > "$LOG_FILE"
echo -ne "\033[1;36m[cmux]\033[0m Initializing teammate agent in pane %${PANE_ID}...\r\n"

for i in $(seq 1 600); do
    if [ -s "$CMD_FILE" ]; then
        break
    fi
    sleep 0.05
done

if [ -s "$CMD_FILE" ]; then
    CMD=$(cat "$CMD_FILE")
    echo "$(date '+%Y-%m-%d %H:%M:%S') [cmux] Executing command: $CMD" >> "$LOG_FILE"
    echo -ne "\033[1;32m[cmux]\033[0m Starting Claude Code teammate agent...\r\n"
    echo $$ > "/tmp/teammate_pid_${PANE_ID}"
    eval "$CMD"
    EXIT_CODE=$?
    rm -f "/tmp/teammate_pid_${PANE_ID}" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') [cmux] Teammate finished with code $EXIT_CODE" >> "$LOG_FILE"
    echo -ne "\r\n\033[1;33m[cmux] Teammate agent process finished (exit code $EXIT_CODE).\033[0m\r\n"
    if [ -f "/tmp/teammate_surface_${PANE_ID}" ]; then
        SURF=$(cat "/tmp/teammate_surface_${PANE_ID}" 2>/dev/null || true)
        if [ -n "$SURF" ]; then
            sleep 1
            cmux close-surface "$SURF" >> /tmp/cmux_split.log 2>&1 || true
        fi
    fi
    exit $EXIT_CODE
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') [cmux] Timed out waiting for command file" >> "$LOG_FILE"
    echo -ne "\r\n\033[1;31m[cmux] Timed out waiting for teammate command.\033[0m\r\n"
    if [ -f "/tmp/teammate_surface_${PANE_ID}" ]; then
        SURF=$(cat "/tmp/teammate_surface_${PANE_ID}" 2>/dev/null || true)
        if [ -n "$SURF" ]; then
            sleep 2
            cmux close-surface "$SURF" >> /tmp/cmux_split.log 2>&1 || true
        fi
    fi
    exit 1
fi
RUNNER_EOF
    sed -i "s/REPLACE_PANE_ID/${pane_id}/g" "$runner_file" 2>/dev/null || sed -i "" "s/REPLACE_PANE_ID/${pane_id}/g" "$runner_file"
    chmod +x "$runner_file"
    echo "$runner_file"
}

SUBCOMMAND="${1:-}"
shift || true

# Helper to manage pane ID counter for Claude's pane tracking
PANE_COUNTER_FILE="/tmp/tmux_pane_counter"
get_next_pane_id() {
    local next_id=1
    if [ -f "$PANE_COUNTER_FILE" ]; then
        local current
        current=$(cat "$PANE_COUNTER_FILE" 2>/dev/null || echo 0)
        next_id=$((current + 1))
    fi
    echo "$next_id" > "$PANE_COUNTER_FILE"
    echo "$next_id"
}

case "$SUBCOMMAND" in
    split-window|splitw)
        DIRECTION_FLAG="-h"
        PRINT_FLAG=0
        FORMAT=""
        TARGET_PANE=""
        CWD=""
        COMMAND_ARGS=()

        while [ $# -gt 0 ]; do
            case "$1" in
                -h)
                    DIRECTION_FLAG="-h"
                    shift
                    ;;
                -v)
                    DIRECTION_FLAG="-v"
                    shift
                    ;;
                -b)
                    shift
                    ;;
                -d)
                    shift
                    ;;
                -P)
                    PRINT_FLAG=1
                    shift
                    ;;
                -F)
                    FORMAT="$2"
                    shift 2
                    ;;
                -t)
                    TARGET_PANE="$2"
                    shift 2
                    ;;
                -c)
                    CWD="$2"
                    shift 2
                    ;;
                -l)
                    shift 2
                    ;;
                --)
                    shift
                    COMMAND_ARGS=("$@")
                    break
                    ;;
                *)
                    COMMAND_ARGS+=("$1")
                    shift
                    ;;
            esac
        done

        PANE_NUM=$(get_next_pane_id)

        # Prepare command to execute inside the container / sandbox
        CMD_EXEC=""
        if [ ${#COMMAND_ARGS[@]} -gt 0 ]; then
            CMD_EXEC="${COMMAND_ARGS[*]}"
        fi

        # If command is 'cat' or empty, use the runner script that waits for respawn-pane
        if [ -z "$CMD_EXEC" ] || [ "$CMD_EXEC" = "cat" ]; then
            RUNNER_PATH=$(create_teammate_runner "$PANE_NUM")
            DISPATCH_CMD=$(build_host_exec_cmd "$RUNNER_PATH")
        else
            DISPATCH_CMD=$(build_host_exec_cmd "$CMD_EXEC")
        fi

        # Dispatch split through cmux CLI and capture surface ID
        SPLIT_RAW=$(cmux split ${DIRECTION_FLAG} -- "${DISPATCH_CMD}" 2>> /tmp/cmux_split.log || true)
        echo "$SPLIT_RAW" >> /tmp/cmux_split.log 2>&1 || true
        SURFACE_ID=$(echo "$SPLIT_RAW" | grep -oE '(surface:[0-9]+|[0-9a-fA-F-]{36})' | head -n 1)
        if [ -n "$SURFACE_ID" ]; then
            echo "$SURFACE_ID" > "/tmp/teammate_surface_${PANE_NUM}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') [shim] Assigned surface ${SURFACE_ID} to pane %${PANE_NUM}" >> /tmp/tmux_shim.log 2>/dev/null || true
        fi

        if [ "$PRINT_FLAG" -eq 1 ]; then
            if [ -n "$FORMAT" ]; then
                OUT="$FORMAT"
                OUT="${OUT//\#\{pane_id\}/%${PANE_NUM}}"
                OUT="${OUT//\#\{window_id\}/@0}"
                OUT="${OUT//\#\{session_name\}/claude-teams}"
                echo "$OUT"
            else
                echo "%${PANE_NUM}"
            fi
        fi
        exit 0
        ;;

    new-window|neww)
        PRINT_FLAG=0
        FORMAT=""
        COMMAND_ARGS=()

        while [ $# -gt 0 ]; do
            case "$1" in
                -d) shift ;;
                -P) PRINT_FLAG=1; shift ;;
                -F) FORMAT="$2"; shift 2 ;;
                -c) shift 2 ;;
                -n) shift 2 ;;
                --) shift; COMMAND_ARGS=("$@"); break ;;
                *) COMMAND_ARGS+=("$1") ; shift ;;
            esac
        done

        PANE_NUM=$(get_next_pane_id)

        CMD_EXEC=""
        if [ ${#COMMAND_ARGS[@]} -gt 0 ]; then
            CMD_EXEC="${COMMAND_ARGS[*]}"
        fi

        if [ -z "$CMD_EXEC" ] || [ "$CMD_EXEC" = "cat" ]; then
            RUNNER_PATH=$(create_teammate_runner "$PANE_NUM")
            DISPATCH_CMD=$(build_host_exec_cmd "$RUNNER_PATH")
        else
            DISPATCH_CMD=$(build_host_exec_cmd "$CMD_EXEC")
        fi

        SPLIT_RAW=$(cmux new-window -- "${DISPATCH_CMD}" 2>> /tmp/cmux_split.log || true)
        echo "$SPLIT_RAW" >> /tmp/cmux_split.log 2>&1 || true
        SURFACE_ID=$(echo "$SPLIT_RAW" | grep -oE '(surface:[0-9]+|[0-9a-fA-F-]{36})' | head -n 1)
        if [ -n "$SURFACE_ID" ]; then
            echo "$SURFACE_ID" > "/tmp/teammate_surface_${PANE_NUM}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') [shim] Assigned surface ${SURFACE_ID} to window @${PANE_NUM}" >> /tmp/tmux_shim.log 2>/dev/null || true
        fi

        if [ "$PRINT_FLAG" -eq 1 ]; then
            if [ -n "$FORMAT" ]; then
                OUT="$FORMAT"
                OUT="${OUT//\#\{pane_id\}/%${PANE_NUM}}"
                OUT="${OUT//\#\{window_id\}/@${PANE_NUM}}"
                OUT="${OUT//\#\{session_name\}/claude-teams}"
                echo "$OUT"
            else
                echo "%${PANE_NUM}"
            fi
        fi
        exit 0
        ;;

    respawn-pane|respawnp)
        TARGET_PANE=""
        COMMAND_ARGS=()

        while [ $# -gt 0 ]; do
            case "$1" in
                -k) shift ;;
                -t) TARGET_PANE="$2"; shift 2 ;;
                --)
                    shift
                    COMMAND_ARGS=("$@")
                    break
                    ;;
                *)
                    COMMAND_ARGS+=("$1")
                    shift
                    ;;
            esac
        done

        PANE_ID="${TARGET_PANE#%}"
        if [ -z "$PANE_ID" ]; then
            PANE_ID="1"
        fi

        if [ ${#COMMAND_ARGS[@]} -gt 0 ]; then
            CMD_EXEC="${COMMAND_ARGS[*]}"
            # Ensure teammate agents run with --dangerously-skip-permissions
            if [[ "$CMD_EXEC" == *"claude "* ]] || [[ "$CMD_EXEC" == *"claude" ]]; then
                if [[ "$CMD_EXEC" != *"--dangerously-skip-permissions"* ]]; then
                    CMD_EXEC="${CMD_EXEC/claude /claude --dangerously-skip-permissions }"
                fi
            fi
            echo "$CMD_EXEC" > "/tmp/teammate_cmd_${PANE_ID}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') [shim] Wrote teammate command for pane %${PANE_ID}" >> /tmp/tmux_shim.log 2>/dev/null || true
        fi
        exit 0
        ;;

    display-message|display)
        PRINT_FLAG=0
        FORMAT=""
        TARGET=""
        while [ $# -gt 0 ]; do
            case "$1" in
                -p) PRINT_FLAG=1; shift ;;
                -F) FORMAT="$2"; shift 2 ;;
                -t) TARGET="$2"; shift 2 ;;
                *)
                    if [ -z "$FORMAT" ] && [[ "$1" == *"#"* ]]; then
                        FORMAT="$1"
                    fi
                    shift
                    ;;
            esac
        done

        if [ -z "$FORMAT" ]; then
            FORMAT="#{pane_id}"
        fi

        OUT="$FORMAT"
        OUT="${OUT//\#\{pane_id\}/%0}"
        OUT="${OUT//\#\{window_id\}/@0}"
        OUT="${OUT//\#\{window_name\}/claude}"
        OUT="${OUT//\#\{session_name\}/claude-teams}"
        echo "$OUT"
        exit 0
        ;;

    list-panes|lsp)
        FORMAT=""
        TARGET=""
        while [ $# -gt 0 ]; do
            case "$1" in
                -F) FORMAT="$2"; shift 2 ;;
                -t) TARGET="$2"; shift 2 ;;
                -a) shift ;;
                *) shift ;;
            esac
        done
        if [ "$FORMAT" = "#{pane_id}" ]; then
            echo "%0"
        else
            echo "%0: [200x50] [history 0/2000, 0 bytes] %0 (active)"
        fi
        exit 0
        ;;

    list-windows|lsw)
        FORMAT=""
        TARGET=""
        while [ $# -gt 0 ]; do
            case "$1" in
                -F) FORMAT="$2"; shift 2 ;;
                -t) TARGET="$2"; shift 2 ;;
                -a) shift ;;
                *) shift ;;
            esac
        done
        if [ "$FORMAT" = "#{window_name}" ]; then
            echo "claude"
        elif [ "$FORMAT" = "#{window_id}" ]; then
            echo "@0"
        else
            echo "0: claude* (1 panes) [200x50]"
        fi
        exit 0
        ;;

    has-session)
        exit 0
        ;;

    send-keys|send)
        TARGET_PANE=""
        while [ $# -gt 0 ]; do
            case "$1" in
                -t) TARGET_PANE="$2"; shift 2 ;;
                *) break ;;
            esac
        done
        PANE_ID="${TARGET_PANE#%}"
        if [ -n "$PANE_ID" ] && [ -n "$*" ]; then
            echo "$*" >> "/tmp/teammate_cmd_${PANE_ID}" 2>/dev/null || true
        fi
        exit 0
        ;;

    kill-pane|killp|kill-window|killw)
        TARGET_PANE=""
        while [ $# -gt 0 ]; do
            case "$1" in
                -t) TARGET_PANE="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        PANE_ID="${TARGET_PANE#%}"
        PANE_ID="${PANE_ID#@}"
        if [ -n "$PANE_ID" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [shim] kill-pane called for ${TARGET_PANE}" >> /tmp/tmux_shim.log 2>/dev/null || true
            if [ -f "/tmp/teammate_pid_${PANE_ID}" ]; then
                TPID=$(cat "/tmp/teammate_pid_${PANE_ID}" 2>/dev/null || true)
                if [ -n "$TPID" ]; then
                    kill "$TPID" 2>/dev/null || true
                fi
            fi
            if [ -f "/tmp/teammate_surface_${PANE_ID}" ]; then
                SURF_TO_CLOSE=$(cat "/tmp/teammate_surface_${PANE_ID}" 2>/dev/null || true)
                if [ -n "$SURF_TO_CLOSE" ]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') [shim] Closing cmux surface ${SURF_TO_CLOSE} for pane %${PANE_ID}" >> /tmp/tmux_shim.log 2>/dev/null || true
                    cmux close-surface "$SURF_TO_CLOSE" >> /tmp/cmux_split.log 2>&1 || true
                fi
            fi
            rm -f "/tmp/teammate_pid_${PANE_ID}" "/tmp/teammate_cmd_${PANE_ID}" "/tmp/teammate_runner_${PANE_ID}.sh" "/tmp/teammate_surface_${PANE_ID}" 2>/dev/null || true
        fi
        exit 0
        ;;

    select-pane|select-layout|resize-pane)
        exit 0
        ;;

    show-options|show|set-option|set)
        exit 0
        ;;

    *)
        exit 0
        ;;
esac
