#!/bin/bash
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Logging Helpers ---
log() {
    local level=$1
    shift
    local message="$*"
    case $level in
        "INFO")    echo -e "${BLUE}[INFO]${NC}  $message" ;;
        "WARN")    echo -e "${YELLOW}[WARN]${NC}  $message" ;;
        "ERROR")   echo -e "${RED}[ERROR]${NC} $message" >&2; exit 1 ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "STEP")    echo -e "${PURPLE}[STEP]${NC} $message" ;;
    esac
}

section() {
    echo -e "\n${PURPLE}===========================================${NC}"
    echo -e "${PURPLE}   $*${NC}"
    echo -e "${PURPLE}===========================================${NC}"
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
        log "WARN" "⚠️  SHOP_CODE and SHOP_TOKEN cannot be empty. Please try again."
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
