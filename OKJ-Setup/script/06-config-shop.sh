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

# --- Logging Helpers ---
log() {
    local level=$1
    shift
    local message="$*"
    local log_out="${LOGFILE:-/dev/null}"
    
    case $level in
        "INFO")    echo -e "  ${B_BLUE}ℹ [INFO]${NC}    $message" | tee -a "$log_out" ;;
        "WARN")    echo -e "  ${B_YELLOW}⚠ [WARN]${NC}    $message" | tee -a "$log_out" ;;
        "ERROR")   echo -e "\n${BG_RED}${B_WHITE} ❌ ERROR ${NC} ${B_RED}$message${NC}\n" | tee -a "$log_out" ;;
        "SUCCESS") echo -e "     ${B_GREEN}╰─ ✔${NC} ${B_GREEN}$message${NC}" | tee -a "$log_out" ;;
        "STEP")    echo -e "${B_CYAN} ➜ ${NC} ${B_WHITE}$message${NC}" | tee -a "$log_out" ;;
    esac
}

section() {
    local title="$1"
    local clean_title=$(echo -e "$title" | sed 's/\x1b\[[0-9;]*m//g')
    local title_len=${#clean_title}
    local width=55
    local pad_len=$((width - title_len))
    [ $pad_len -lt 0 ] && pad_len=0
    local padding=$(printf "%${pad_len}s" "")

    echo -e "\n${B_PURPLE}╭──────────────────────────────────────────────────────────╮${NC}"
    echo -e "${B_PURPLE}│${NC} ${B_WHITE}${title}${NC}${padding} ${B_PURPLE}│${NC}"
    echo -e "${B_PURPLE}╰──────────────────────────────────────────────────────────╯${NC}"
}

# --- Check Permissions ---
if [ "$EUID" -eq 0 ]; then
   log "ERROR" "Please run this script as a regular user, not root/sudo."
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"

section "🛠️  Interactive POS Shop Configuration"

log "INFO" "This script will help you configure the Shop Code and Gateway/RMS Tokens."
log "INFO" "Configuration File: $BASE_DIR/configmap/pos-shop-service-cm.yaml"
echo ""

while true; do
    echo -e "\n${CYAN}--- Please enter the following information ---${NC}"
    read -p "  1. Enter SHOP_CODE (e.g., JW000): " SHOP_CODE
    read -p "  2. Enter SHOP_TOKEN (Gateway/RMS): " SHOP_TOKEN
    
    if [ -z "$SHOP_CODE" ] || [ -z "$SHOP_TOKEN" ]; then
        log "WARN" "⚠️ SHOP_CODE and SHOP_TOKEN cannot be empty. Please try again."
        continue
    fi
    
    echo -e "\n${YELLOW}--- Review your information ---${NC}"
    echo -e "  SHOP_CODE  : ${GREEN}$SHOP_CODE${NC}"
    echo -e "  SHOP_TOKEN : ${GREEN}$SHOP_TOKEN${NC}"
    echo -e "${YELLOW}-------------------------------${NC}"
    
    read -p "Is this correct? (y/n): " CONFIRM
    if [[ $CONFIRM =~ ^[Yy]$ ]]; then
        break
    else
        log "INFO" "Resetting... please re-enter the information."
    fi
done

log "INFO" "Updating configuration file using yq..."

# Update using yq
if ! command -v yq &> /dev/null; then
    log "ERROR" "yq is not installed. Please run Step 1 first."
fi

yq eval ".data.CONFIG_SHOP_CODE = \"$SHOP_CODE\"" -i "$BASE_DIR/configmap/pos-shop-service-cm.yaml"
yq eval ".data.CONFIG_SHOP_GATEWAY_TOKEN = \"$SHOP_TOKEN\"" -i "$BASE_DIR/configmap/pos-shop-service-cm.yaml"
yq eval ".data.CONFIG_RMS_TOKEN = \"$SHOP_TOKEN\"" -i "$BASE_DIR/configmap/pos-shop-service-cm.yaml"

log "SUCCESS" "✅ Configuration file updated."

section "🚀 Applying to Cluster"
log "INFO" "Applying ConfigMap to cluster..."
if sudo KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f "$BASE_DIR/configmap/pos-shop-service-cm.yaml" -n apps; then
    log "SUCCESS" "✅ Shop configuration applied to cluster successfully."
else
    log "ERROR" "❌ Failed to apply ConfigMap. Ensure K3s is running and namespace 'apps' exists."
fi

echo ""
log "SUCCESS" "🏁 POS Shop setup complete!"
echo "==========================================="
