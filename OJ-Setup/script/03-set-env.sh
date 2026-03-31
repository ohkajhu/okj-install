#!/bin/bash
set -euo pipefail

# --- Premium UI/UX Colors ---
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

section "🌍 environment & hosts setup"

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
        printf "  ${CLR_INFO}👉 please enter tenant name:${NC} "
        read TENANT_NAME
        
        if [ -z "$TENANT_NAME" ]; then
            log "WARN" "please enter tenant name"
            continue
        fi
        
        if [[ ! $TENANT_NAME =~ ^[a-zA-Z0-9_-]+$ ]]; then
            log "WARN" "tenant name should only contain letters, numbers, -, _"
            continue
        fi
        
        break
    done
}

# Function to confirm settings
confirm_settings() {
    echo ""
    log "INFO" "📋 review settings:"
    echo "  ──────────────────────────────────────────"
    printf "  ${CLR_DIM}· file        :${NC} /etc/environment\n"
    printf "  ${CLR_DIM}· tenant      :${NC} %s\n" "$TENANT_NAME"
    printf "  ${CLR_DIM}· registry    :${NC} registry.ohkajhu.com\n"
    echo "  ──────────────────────────────────────────"
    echo ""
    
    while true; do
        printf "  ${CLR_WARN}👉 confirm settings? (y/n):${NC} "
        read CONFIRM
        case $CONFIRM in
            [Yy]|[Yy]es) return 0 ;;
            [Nn]|[Nn]o) return 1 ;;
            *) log "WARN" "please answer y or n" ;;
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
    
    # If already authorized via master script's keep-alive, sudo -n true will succeed
    if ! sudo -n true 2>/dev/null; then
        sudo -v > /dev/null 2>&1 || log "ERROR" "❌ sudo access denied. Please configure sudo permissions."
    fi
}

# Main function
main() {
    check_permissions
    show_current_environment
    show_current_hosts
    if [ -z "${TENANT_NAME:-}" ]; then
        get_tenant_name
        
        if ! confirm_settings; then
            log "WARN" "❌ Canceled settings update"
            exit 0
        fi
    else
        log "INFO" "Using TENANT_NAME provided by orchestrator: $TENANT_NAME"
    fi
    
    create_environment_file
    update_hosts_file
    load_environment
    
    section "✨ setup complete"
    log "INFO" "📄 New Environment:"
    cat /etc/environment
}

main