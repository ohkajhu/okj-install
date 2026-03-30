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

# --- Logging Helpers ---
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

# --- Check Permissions ---
if [ "$EUID" -eq 0 ]; then
   log "ERROR" "Please run this script as a regular user, not root/sudo."
   exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"

section "🛠️ interactive pos shop configuration"

log "INFO" "This script will help you configure the Shop Code and Gateway/RMS Tokens."
log "INFO" "Configuration File: $BASE_DIR/configmap/pos-shop-service-cm.yaml"
echo ""

# Fallback Mechanism: Skip interactive prompt if variables are already provided
if [ -z "${SHOP_CODE:-}" ] || [ -z "${SHOP_TOKEN:-}" ]; then
    while true; do
        echo ""
        printf "  ${CLR_INFO}👉 1. enter shop_code (e.g. jw101):${NC} "
        read input_shop
        SHOP_CODE=$(echo "$input_shop" | tr -d '\r' | tr -cd '[:print:]' | xargs)

        printf "  ${CLR_INFO}👉 2. enter shop_token (gateway/rms):${NC} "
        read input_token
        SHOP_TOKEN=$(echo "$input_token" | tr -d '\r' | tr -cd '[:print:]' | xargs)
        
        if [ -z "$SHOP_CODE" ] || [ -z "$SHOP_TOKEN" ]; then
            log "WARN" "shop_code and shop_token cannot be empty"
            continue
        fi
        
        echo ""
        log "INFO" "📋 review information:"
        echo "  ──────────────────────────────────────────"
        printf "  ${CLR_DIM}· CONFIG_SHOP_CODE          :${NC} %s\n" "$SHOP_CODE"
        printf "  ${CLR_DIM}· CONFIG_SHOP_GATEWAY_TOKEN :${NC} %s\n" "$SHOP_TOKEN"
        printf "  ${CLR_DIM}· CONFIG_RMS_TOKEN          :${NC} %s\n" "$SHOP_TOKEN"
        echo "  ──────────────────────────────────────────"
        echo ""
        
        printf "  ${CLR_WARN}👉 is this correct? (y/n):${NC} "
        read CONFIRM
        if [[ $CONFIRM =~ ^[Yy]$ ]]; then
            break
        else
            log "INFO" "resetting... please re-enter information."
        fi
    done
else
    log "INFO" "Using SHOP_CODE and SHOP_TOKEN provided by orchestrator."
fi

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
section "✨ pos shop setup complete"
