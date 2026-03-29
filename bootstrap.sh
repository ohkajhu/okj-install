#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
#  MINIMALIST COLORS (Premium Slate/Emerald Palette)
# ─────────────────────────────────────────────────────────────────────────────
CLR_TITLE='\033[38;5;75m'    # Steel Blue
CLR_SECTION='\033[38;5;135m'  # Soft Purple
CLR_SUCCESS='\033[38;5;82m'   # Emerald Green
CLR_INFO='\033[38;5;111m'    # Sky Blue
CLR_TXT='\033[38;5;253m'     # Off White
CLR_DIM='\033[38;5;244m'     # Muted Slate
CLR_ERR='\033[38;5;196m'     # Crimson
CLR_WARN='\033[38;5;214m'    # Amber
NC='\033[0m'
BOLD='\033[1m'

# ─────────────────────────────────────────────────────────────────────────────
#  CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
REPO_URL="https://github.com/ohkajhu/okj-install.git"
TARGET_DIR="$HOME/okj-install"
TEMP_DIR=""

# ─────────────────────────────────────────────────────────────────────────────
#  MINIMALIST UI FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────
print_banner() {
    clear
    echo -e "${CLR_TITLE}"
    echo '  ██████╗ ██╗  ██╗     ██╗   ██████╗  ██████╗ ███████╗'
    echo ' ██╔═══██╗██║ ██╔╝     ██║   ██╔══██╗██╔═══██╗██╔════╝'
    echo ' ██║   ██║█████╔╝      ██║   ██████╔╝██║   ██║███████╗'
    echo ' ██║   ██║██╔═██╗ ██   ██║   ██╔═══╝ ██║   ██║╚════██║'
    echo ' ╚██████╔╝██║  ██╗╚█████╔╝   ██║     ╚██████╔╝███████║'
    echo '  ╚═════╝ ╚═╝  ╚═╝ ╚════╝    ╚═╝      ╚═════╝ ╚══════╝'
    echo -e "${NC}${CLR_SECTION}   ━━━━━━  A U T O M A T I O N   S Y S T E M  ━━━━━━${NC}"
    echo -e "${CLR_DIM}                                       By TOTHEMARS 🚀${NC}\n"
}

section() {
    local icon=""
    local title="$1"
    
    # If 2 arguments provided: section "🧬" "title"
    if [ $# -eq 2 ]; then
        icon="$1"
        title="$2"
    # If 1 argument provided: section "🧬 title"
    elif [[ "$1" =~ ^([^[:alnum:][:space:][:punct:]]+)[[:space:]]+(.*)$ ]]; then
        icon="${BASH_REMATCH[1]}"
        title="${BASH_REMATCH[2]}"
    fi

    # Convert title to Title Case (Proper Case)
    local formatted_title=$(echo "$title" | sed 's/.*/\L&/; s/[a-z]/\U&/1; s/ \([a-z]\)/ \U\1/g')
    
    if [ -z "$icon" ]; then
        printf "\n${CLR_SECTION}${BOLD}▎${NC} ${BOLD}%s${NC}\n" "$formatted_title"
    else
        printf "\n${CLR_SECTION}${BOLD}▎${NC} ${icon} ${BOLD}%s${NC}\n" "$formatted_title"
    fi
}

log_info() {
    # Lowercase info for a modern, non-cluttered feel
    local msg=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    printf "  ${CLR_DIM}· %s${NC}\n" "$msg"
}

log_warn() {
    printf "  ${CLR_WARN}⚠ %s${NC}\n" "$(echo "$1" | tr '[:upper:]' '[:lower:]')"
}

# Advanced execution with a clean minimalist spinner
run_task() {
    local task_cmd="$1"
    local task_msg=$(echo "$2" | tr '[:upper:]' '[:lower:]')
    local error_msg="$3"
    local log_file=$(mktemp)
    
    tput civis
    eval "$task_cmd" > "$log_file" 2>&1 &
    local pid=$!
    
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\r  ${CLR_SECTION}%c${NC}  ${CLR_DIM}%s...${NC} " "$spinstr" "$task_msg"
        local spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
    done
    
    wait $pid
    local exit_code=$?
    printf "\r\033[K"
    
    if [ $exit_code -eq 0 ]; then
        printf "  ${CLR_SUCCESS}·${NC} ${CLR_TXT}%s${NC}\n" "$task_msg"
    else
        printf "  ${CLR_ERR}·${NC} ${CLR_ERR}%s${NC}\n" "$task_msg"
        printf "\n${CLR_ERR}${BOLD}error:${NC} ${CLR_TXT}%s${NC}\n" "$error_msg"
        cat "$log_file" | sed 's/^/  /'
        tput cnorm
        exit 1
    fi
    
    rm -f "$log_file"
    tput cnorm
}

_cleanup() {
    tput cnorm
    [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}
trap '_cleanup' EXIT

# ═════════════════════════════════════════════════════════════════════════════
#  MAIN EXECUTION
# ═════════════════════════════════════════════════════════════════════════════
print_banner
section "🧬 initialization"

# 1. Pre-flight
log_info "verifying user non-root privileges"
if [[ "$EUID" -eq 0 ]]; then
    log_warn "this script should not be run as root directly."
    log_info "checking for sudo availability..."
fi

# 2. Git Check
if ! command -v git >/dev/null 2>&1; then
    run_task "sudo apt-get update -qq && sudo apt-get install -y git -qq" "installing git dependency" "git installation failed"
else
    log_info "git and basic development tools are already available"
fi

# 3. Detect environment
IS_WSL="no"
if grep -qi microsoft /proc/version 2>/dev/null || ( [[ -f /proc/sys/kernel/osrelease ]] && grep -qi microsoft /proc/sys/kernel/osrelease ); then
    IS_WSL="yes"
fi

if [[ "$IS_WSL" == "yes" ]]; then
    SETUP_TYPE="OJ-Setup"
    log_info "environment: 🖥️ Windows Subsystem for Linux (WSL)"
else
    SETUP_TYPE="OKJ-Setup"
    log_info "environment: 🐧 Ubuntu Server (Native)"
fi

section "📦 deployment"

# 4. Prepare directories
TEMP_DIR=$(mktemp -d)
if [[ -d "$TARGET_DIR" ]]; then
    run_task "rm -rf '$TARGET_DIR'" "cleaning up previous installation files" "cleanup failed"
fi
run_task "mkdir -p '$TARGET_DIR'" "initializing target workspace" "directory creation failed"

# 5. Sync from Repository
run_task "git clone --depth 1 '$REPO_URL' '$TEMP_DIR/repo' -q" "syncing repository from github" "github sync failed"
run_task "cp -r '$TEMP_DIR/repo/$SETUP_TYPE/.' '$TARGET_DIR/'" "deploying components to target directory" "deployment failed"

# 6. Finalizing
run_task "chmod +x '$TARGET_DIR'/*.sh '$TARGET_DIR'/script/*.sh 2>/dev/null || true" "finalizing local script permissions" "chmod failed"

# ─────────────────────────────────────────────────────────────────────────────
#  COMPLETION
# ─────────────────────────────────────────────────────────────────────────────
printf "\n"
printf "  ${CLR_SUCCESS}✨ Bootstrap complete!${NC}\n"
printf "  ${CLR_DIM}all files are ready at: %s${NC}\n\n" "$TARGET_DIR"

printf "  ${BOLD}Next steps${NC}\n"
printf "  ${CLR_DIM}1.${NC} cd %s\n" "$TARGET_DIR"
printf "  ${CLR_DIM}2.${NC} ./install-all.sh\n\n"
