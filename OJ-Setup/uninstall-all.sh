#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
#  PREMIUM UI/UX COLORS (Golden Standard)
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
#  MINIMALIST UI FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────
log() {
    local level=$1
    shift
    local message=$(echo "$*" | tr '[:upper:]' '[:lower:]')
    
    case $level in
        "INFO")    printf "  ${CLR_DIM}· %s${NC}\n" "$message" ;;
        "WARN")    printf "  ${CLR_WARN}⚠ %s${NC}\n" "$message" ;;
        "ERROR")   printf "\n  ${CLR_ERR}✖ error: %s${NC}\n" "$message" ;;
        "SUCCESS") printf "  ${CLR_SUCCESS}· %s${NC}\n" "$message" ;;
        "STEP")    printf "  ${CLR_INFO}· %s${NC}\n" "$message" ;;
    esac
}

section() {
    local icon=""
    local title="$1"
    if [ $# -eq 2 ]; then
        icon="$1"
        title="$2"
    elif [[ "$1" =~ ^([^[:alnum:][:space:][:punct:]]+)[[:space:]]+(.*)$ ]]; then
        icon="${BASH_REMATCH[1]}"
        title="${BASH_REMATCH[2]}"
    fi
    local formatted_title=$(echo "$title" | sed 's/.*/\L&/; s/[a-z]/\U&/1; s/ \([a-z]\)/ \U\1/g')
    if [ -z "$icon" ]; then
        printf "\n${CLR_SECTION}${BOLD}▎${NC} ${BOLD}%s${NC}\n" "$formatted_title"
    else
        printf "\n${CLR_SECTION}${BOLD}▎${NC} ${icon} ${BOLD}%s${NC}\n" "$formatted_title"
    fi
}

print_banner() {
    clear
    echo -e "${CLR_TITLE}"
    echo '  ██████╗ ██╗  ██╗     ██╗   ██████╗  ██████╗ ███████╗'
    echo ' ██╔═══██╗██║ ██╔╝     ██║   ██╔══██╗██╔═══██╗██╔════╝'
    echo ' ██║   ██║█████╔╝      ██║   ██████╔╝██║   ██║███████╗'
    echo ' ██║   ██║██╔═██╗ ██   ██║   ██╔═══╝ ██║   ██║╚════██║'
    echo ' ╚██████╔╝██║  ██╗╚█████╔╝   ██║     ╚██████╔╝███████║'
    echo '  ╚═════╝ ╚═╝  ╚═╝ ╚════╝    ╚═╝      ╚═════╝ ╚══════╝'
    echo -e "${NC}${CLR_ERR}   ━━━━━━  U N I N S T A L L   S Y S T E M  ━━━━━━${NC}"
    echo -e "${CLR_DIM}                                       By TOTHEMARS 🚀${NC}\n"
}

# --- Check Permissions ---
if [ "$EUID" -eq 0 ]; then
   log "ERROR" "please run as regular user, not root/sudo"
   exit 1
fi

# Cache sudo credentials upfront to prevent interruptions
if ! sudo -n true 2>/dev/null; then
    log "INFO" "authentication required for complete uninstallation."
    sudo -v
fi

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────
print_banner
section "💥 okj pos system - master uninstaller"

log "WARN" "you are about to completely remove the okj pos system."
log "WARN" "this action is irreversible and will destroy all data!"

printf "\n  ${CLR_ERR}Type 'YES' to confirm destruction of this system:${NC} "
read CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    log "INFO" "uninstallation aborted by user."
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- 1. Step 1: K3s Cluster ---
section "☸️ removing k3s cluster & workloads"
if [ -f "./script/02-uninstall-k3s.sh" ]; then
    log "INFO" "running k3s uninstallation with sudo..."
    sudo ./script/02-uninstall-k3s.sh
    log "SUCCESS" "k3s cluster successfully removed"
else
    log "WARN" "k3s uninstallation script not found, skipping..."
fi

# --- 2. Step 2: pgAdmin4 ---
section "📉 removing pgadmin4"
if [ -f "./script/01-uninstall-pgadmin.sh" ]; then
    log "INFO" "running pgadmin uninstallation script..."
    echo "y" | ./script/01-uninstall-pgadmin.sh
    log "SUCCESS" "pgadmin4 successfully removed"
else
    log "WARN" "pgadmin uninstallation script not found, skipping..."
fi

# --- 3. Step 3: Basic Tools ---
section "🧩 removing basic tools & dependencies"
if [ -f "./script/01-uninstall-tools-k3s.sh" ]; then
    log "INFO" "running tools uninstallation script..."
    echo "y" | ./script/01-uninstall-tools-k3s.sh
    log "SUCCESS" "basic tools and dependencies successfully removed"
else
    log "WARN" "tools uninstallation script not found, skipping..."
fi

# --- 4. Final Steps: Environment Cleanup ---
section "🧹 cleaning environment variables"
log "INFO" "removing okj configurations from /etc/environment..."
sudo sed -i '/TENANT/d' /etc/environment || true
sudo sed -i '/SHOP_CODE/d' /etc/environment || true
sudo sed -i '/SHOP_ENV/d' /etc/environment || true
sudo sed -i '/RMS_TOKEN/d' /etc/environment || true
sudo sed -i '/GATEWAY_TOKEN/d' /etc/environment || true
sudo sed -i '/FLUX_ENV/d' /etc/environment || true

log "INFO" "cleaning okj definitions from /etc/hosts..."
sudo sed -i '/okj-failover/d' /etc/hosts || true

log "SUCCESS" "system environment variables cleaned"

# ─────────────────────────────────────────────────────────────────────────────
#  COMPLETION
# ─────────────────────────────────────────────────────────────────────────────
printf "\n"
printf "  ${CLR_SUCCESS}✨  master uninstallation completed!${NC}\n"
log "INFO" "it is strongly recommended to securely reboot the node now."
printf "\n"
