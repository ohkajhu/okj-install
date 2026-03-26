#!/bin/bash
set -euo pipefail

# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Configuration ---
REPO_URL="https://github.com/ohkajhu/okj-install.git"
TARGET_DIR="$HOME/okj-install"

# --- Functions ---
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

echo -e "${BLUE}===========================================${NC}"
echo -e "   ${GREEN}OKJ POS System Bootstrap Script${NC}"
echo -e "${BLUE}===========================================${NC}"

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
if [ -d "$TARGET_DIR/script" ]; then
    find "$TARGET_DIR/script" -maxdepth 1 -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
fi

echo -e "${BLUE}===========================================${NC}"
log_success "Bootstrap complete!"
echo -e "${BLUE}===========================================${NC}"
log_info "All files are ready at: ${YELLOW}$TARGET_DIR${NC}"
log_info "Next Steps:"
echo -e "  1. ${CYAN}cd $TARGET_DIR/script${NC}"
echo -e "  2. ${CYAN}./00-install-all.sh${NC} (Recommended to run this for full installation)"
echo -e "${BLUE}===========================================${NC}"
