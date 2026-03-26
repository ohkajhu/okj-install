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

section "🌍 Environment & Hosts Setup"

# Function to show current environment file
show_current_environment() {
    log "INFO" "📄 Checking current /etc/environment file:"
    echo "------------------------------------------"
    if [ -f /etc/environment ] && [ -s /etc/environment ]; then
        cat /etc/environment
    else
        log "INFO" "(File is empty or not found)"
    fi
    echo "------------------------------------------"
    echo ""
}

# Function to show current hosts file
show_current_hosts() {
    log "INFO" "📄 Checking current /etc/hosts file:"
    echo "------------------------------------------"
    if [ -f /etc/hosts ] && [ -s /etc/hosts ]; then
        cat /etc/hosts
    else
        log "INFO" "(File is empty or not found)"
    fi
    echo "------------------------------------------"
    echo ""
}

# Function to prompt for TENANT name
get_tenant_name() {
    while true; do
        echo -n -e "${CYAN}Please enter TENANT name: ${NC}"
        read TENANT_NAME
        
        if [ -z "$TENANT_NAME" ]; then
            log "WARN" "⚠️  Please enter TENANT name"
            continue
        fi
        
        if [[ ! $TENANT_NAME =~ ^[a-zA-Z0-9_-]+$ ]]; then
            log "WARN" "⚠️  TENANT name should only contain letters, numbers, -, _"
            continue
        fi
        
        break
    done
}

# Function to confirm settings
confirm_settings() {
    echo ""
    log "INFO" "📋 Review settings:"
    echo "------------------------------------------"
    echo "File: /etc/environment"
    echo "TENANT: $TENANT_NAME"
    echo "REGISTRY_HOST: registry.ohkajhu.com"
    echo "REGISTRY_USERNAME: robot\$cache-server"
    echo "REGISTRY_PASSWORD: KcHN7gPepBR2AGkKC2NQQiNAmDUheTAm"
    echo ""
    echo "File: /etc/hosts"
    echo "125.254.54.194 registry.ohkajhu.com"
    echo "125.254.54.194 shop-gateway.ohkajhu.com"
    echo "------------------------------------------"
    echo ""
    
    while true; do
        echo -n -e "${YELLOW}Confirm settings? (y/n): ${NC}"
        read CONFIRM
        case $CONFIRM in
            [Yy]|[Yy]es) return 0 ;;
            [Nn]|[Nn]o) return 1 ;;
            *) log "WARN" "Please answer y or n" ;;
        esac
    done
}

# Function to create/update environment file
create_environment_file() {
    log "INFO" "🔧 Updating /etc/environment file..."
    
    TEMP_FILE=$(mktemp)
    if [ -f /etc/environment ] && [ -s /etc/environment ]; then
        sudo grep -v "^TENANT=" /etc/environment | \
        sudo grep -v "^REGISTRY_HOST=" | \
        sudo grep -v "^REGISTRY_USERNAME=" | \
        sudo grep -v "^REGISTRY_PASSWORD=" > "$TEMP_FILE" || true
    fi
    
    cat >> "$TEMP_FILE" <<EOF
TENANT='$TENANT_NAME'
REGISTRY_HOST='registry.ohkajhu.com'
REGISTRY_USERNAME='robot\$cache-server'
REGISTRY_PASSWORD='KcHN7gPepBR2AGkKC2NQQiNAmDUheTAm'
EOF
    
    sudo cp "$TEMP_FILE" /etc/environment
    rm "$TEMP_FILE"
    
    log "SUCCESS" "✅ Correctly updated /etc/environment"
}

# Function to update hosts file
update_hosts_file() {
    log "INFO" "🔧 Updating /etc/hosts file..."
    
    sudo cp /etc/hosts /etc/hosts.backup
    sudo sed -i '/ohkajhu\.com/d' /etc/hosts
    
    sudo tee -a /etc/hosts >/dev/null << EOF
125.254.54.194 registry.ohkajhu.com
125.254.54.194 shop-gateway.ohkajhu.com
EOF
    
    log "SUCCESS" "✅ Correctly updated /etc/hosts"
}

# Function to load environment variables
load_environment() {
    log "INFO" "🔄 Loading environment variables..."
    # Note: In this script, source only affects the child process
    log "SUCCESS" "✅ Variables are ready (please restart terminal for changes to take full effect)"
}

# Function to check permissions
check_permissions() {
    if [ "$EUID" -eq 0 ]; then
        log "WARN" "⚠️  Running as root"
        log "INFO" "Please run this script as a regular user (it will ask for sudo when needed)"
        exit 1
    fi
    
    sudo -v > /dev/null 2>&1 || log "ERROR" "❌ sudo access denied. Please configure sudo permissions."
}

# Main function
main() {
    check_permissions
    show_current_environment
    show_current_hosts
    get_tenant_name
    
    if ! confirm_settings; then
        log "WARN" "❌ Canceled settings update"
        exit 0
    fi
    
    create_environment_file
    update_hosts_file
    load_environment
    
    section "✅ Setup Complete"
    log "INFO" "📄 New Environment:"
    cat /etc/environment
}

main