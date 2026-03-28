#!/bin/bash
set -euo pipefail

# --- Premium UI/UX Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

B_RED='\033[1;31m'
B_GREEN='\033[1;32m'
B_YELLOW='\033[1;33m'
B_BLUE='\033[1;34m'
B_PURPLE='\033[1;35m'
B_CYAN='\033[1;36m'
B_WHITE='\033[1;37m'

BG_RED='\033[41;1;37m'
BG_GREEN='\033[42;1;37m'
BG_YELLOW='\033[43;1;37m'
BG_BLUE='\033[44;1;37m'
BG_PURPLE='\033[45;1;37m'
BG_CYAN='\033[46;1;37m'

# --- Configuration ---
REPO_URL="https://github.com/ohkajhu/okj-install.git"
TARGET_DIR="$HOME/okj-install"

# --- Functions ---
log_info()    { echo -e "  ${B_BLUE}ℹ [INFO]${NC} $*"; }
log_success() { echo -e "     ${B_GREEN}╰─ ✔ ${NC} ${B_GREEN}$*${NC}"; }
log_warn()    { echo -e "  ${B_YELLOW}⚠ [WARN]${NC} $*"; }
log_error()   { echo -e "\n${BG_RED}${B_WHITE} ❌ ERROR ${NC} ${B_RED}$*${NC}\n" >&2; exit 1; }

section() {
    local title="$1"
    local clean_title=$(echo -e "$title" | sed 's/\x1b\[[0-9;]*m//g')
    local title_len=${#clean_title}
    local width=55
    local pad_len=$((width - title_len))
    [ $pad_len -lt 0 ] && pad_len=0
    local padding=$(printf "%${pad_len}s" "")

    echo -e "${B_PURPLE}╭────────────────────────────────────────────────────────╮${NC}"
    echo -e "${B_PURPLE}│${NC}${B_WHITE}${title}${NC}${padding}${B_PURPLE}│${NC}"
    echo -e "${B_PURPLE}╰────────────────────────────────────────────────────────╯${NC}"
}

print_banner() {
    clear
    echo -e "${B_CYAN}"
    echo '  ██████╗ ██╗  ██╗     ██╗   ██████╗  ██████╗ ███████╗'
    echo ' ██╔═══██╗██║ ██╔╝     ██║   ██╔══██╗██╔═══██╗██╔════╝'
    echo ' ██║   ██║█████╔╝      ██║   ██████╔╝██║   ██║███████╗'
    echo ' ██║   ██║██╔═██╗ ██   ██║   ██╔═══╝ ██║   ██║╚════██║'
    echo ' ╚██████╔╝██║  ██╗╚█████╔╝   ██║     ╚██████╔╝███████║'
    echo '  ╚═════╝ ╚═╝  ╚═╝ ╚════╝    ╚═╝      ╚═════╝ ╚══════╝'
    echo -e "${NC}${B_PURPLE}   ━━━━━━  A U T O M A T I O N   S Y S T E M  ━━━━━━${NC}"
    echo -e "${NC}${B_WHITE}                                       By TOTHEMARS 🚀${NC}\n"
}

print_banner

section " 🚀 OKJ POS System Bootstrap Script"

# 1. Pre-flight checks
if [ "$EUID" -eq 0 ]; then
    log_warn "This script must not be run as root directly. Use a normal user with sudo."
    log_info "💡 Please run without 'sudo'."
    exit 1
fi

# 2. Check/Install Git
if ! command -v git >/dev/null 2>&1; then
    log_info "Git is not found. Installing..."
    # Check if we can run sudo
    if ! sudo -v &>/dev/null; then
        log_error "This script requires sudo to install Git. Please run with a user that has sudo privileges."
    fi
    sudo apt update -qq &>/dev/null && sudo apt install -y git -qq &>/dev/null
fi

# 3. Detect environment
IS_WSL=$(grep -qi microsoft /proc/version 2>/dev/null && echo "yes" || echo "no")

# Check /proc/sys/kernel/osrelease for newer WSL versions
if [ "$IS_WSL" = "no" ] && [ -f /proc/sys/kernel/osrelease ]; then
    IS_WSL=$(grep -qi microsoft /proc/sys/kernel/osrelease && echo "yes" || echo "no")
fi

if [ "$IS_WSL" = "yes" ]; then
    SETUP_TYPE="OJ-Setup"
    log_info "Detected environment: 🖥️ WSL (Windows Subsystem for Linux)"
else
    SETUP_TYPE="OKJ-Setup"
    log_info "Detected environment: 🛠️ Ubuntu Server"
fi

# 4. Prepare Cleanup on failure
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# 5. Clone Repository
log_info "Cloning files from $REPO_URL..."
if git clone --depth 1 "$REPO_URL" "$TEMP_DIR" -q; then
    log_success "Clone successful"
else
    log_error "Failed to clone repository. please check your internet or REPO_URL."
fi

# 6. Prepare Target Directory (Idempotent)
if [ -d "$TARGET_DIR" ]; then
    log_warn "Target directory $TARGET_DIR already exists."
    log_info "Cleaning up old files for a fresh setup..."
    rm -rf "$TARGET_DIR"
fi
mkdir -p "$TARGET_DIR"

# 7. Copy files
log_info "Moving $SETUP_TYPE files to $TARGET_DIR..."
if [ -d "$TEMP_DIR/$SETUP_TYPE" ]; then
    cp -r "$TEMP_DIR/$SETUP_TYPE/." "$TARGET_DIR/"
else
    log_error "Setup directory $SETUP_TYPE not found in repository."
fi

# 8. Set permissions
log_info "Setting executable permissions on scripts..."
    chmod +x "$TARGET_DIR"/*.sh 2>/dev/null || true
    if [ -d "$TARGET_DIR/script" ]; then
        chmod +x "$TARGET_DIR/script"/*.sh 2>/dev/null || true
    fi

section " ✨ Bootstrap Complete!"
log_info "All files are ready at: ${B_YELLOW}$TARGET_DIR${NC}"
log_info "Next Steps:"
echo -e "  ${B_CYAN}1.${NC} ${B_WHITE}cd $TARGET_DIR${NC}"
echo -e "  ${B_CYAN}2.${NC} ${B_WHITE}./install-all.sh${NC} ${CYAN}(Recommended to run this for full installation)${NC}\n"
