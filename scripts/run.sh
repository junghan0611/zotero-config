#!/usr/bin/env bash
#
# run.sh - Translation Server 실행/중단 스크립트
#
# Usage:
#   ./run.sh start   - 서버 시작
#   ./run.sh stop    - 서버 중단
#   ./run.sh status  - 서버 상태 확인
#   ./run.sh restart - 서버 재시작
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_DIR="$HOME/repos/3rd/translation-server"
PID_FILE="$REPO_DIR/.translation-server.pid"
LOG_FILE="$SERVER_DIR/translation-server.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

get_pid() {
    if [[ -f "$PID_FILE" ]]; then
        cat "$PID_FILE"
    else
        # Try to find by port
        lsof -ti:1969 2>/dev/null || true
    fi
}

is_running() {
    local pid
    pid=$(get_pid)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    return 1
}

do_start() {
    if is_running; then
        log_warn "Translation Server already running (PID: $(get_pid))"
        return 0
    fi

    if [[ ! -d "$SERVER_DIR" ]]; then
        log_error "Translation Server not found at $SERVER_DIR"
        log_info "Run: mkdir -p ~/repos/3rd && git clone https://github.com/zotero/translation-server.git $SERVER_DIR"
        log_info "Then: cd $SERVER_DIR && git submodule update --init --recursive && npm install"
        exit 1
    fi

    log_info "Starting Translation Server..."

    cd "$SERVER_DIR"
    nohup npm start > "$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"

    # Wait for server to be ready
    local count=0
    while ! curl -s http://localhost:1969 >/dev/null 2>&1; do
        sleep 1
        count=$((count + 1))
        if [[ $count -ge 30 ]]; then
            log_error "Server failed to start. Check log: $LOG_FILE"
            exit 1
        fi
    done

    log_success "Translation Server started (PID: $pid)"
    log_info "Log: $LOG_FILE"
}

do_stop() {
    local pid
    pid=$(get_pid)

    if [[ -z "$pid" ]]; then
        log_warn "Translation Server not running"
        rm -f "$PID_FILE"
        return 0
    fi

    log_info "Stopping Translation Server (PID: $pid)..."

    # Kill the process tree (npm start spawns child processes)
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true

    # Wait for process to end
    local count=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        count=$((count + 1))
        if [[ $count -ge 10 ]]; then
            log_warn "Force killing..."
            kill -9 "$pid" 2>/dev/null || true
            break
        fi
    done

    rm -f "$PID_FILE"
    log_success "Translation Server stopped"
}

do_status() {
    if is_running; then
        local pid
        pid=$(get_pid)
        log_success "Translation Server is running (PID: $pid)"

        # Test endpoint
        if curl -s http://localhost:1969 >/dev/null 2>&1; then
            log_info "Endpoint: http://localhost:1969 (responding)"
        else
            log_warn "Endpoint: http://localhost:1969 (not responding)"
        fi
    else
        log_warn "Translation Server is not running"
        return 1
    fi
}

do_restart() {
    do_stop
    sleep 2
    do_start
}

show_usage() {
    cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  start    Start the Translation Server
  stop     Stop the Translation Server
  status   Check server status
  restart  Restart the server
  log      Show server log (tail -f)

Examples:
  $(basename "$0") start
  $(basename "$0") status
  $(basename "$0") stop

EOF
}

do_log() {
    if [[ -f "$LOG_FILE" ]]; then
        tail -f "$LOG_FILE"
    else
        log_error "Log file not found: $LOG_FILE"
        exit 1
    fi
}

# Main
case "${1:-}" in
    start)   do_start ;;
    stop)    do_stop ;;
    status)  do_status ;;
    restart) do_restart ;;
    log)     do_log ;;
    -h|--help|"")
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
