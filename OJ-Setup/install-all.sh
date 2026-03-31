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
    local message="$*" # REMOVE lowercasing here
    
    case $level in
        "INFO")    printf "  ${CLR_DIM}· %s${NC}\n" "$message" ;;
        "WARN")    printf "  ${CLR_WARN}⚠ %s${NC}\n" "$message" ;;
        "ERROR")   printf "\n  ${CLR_ERR}✖ error: %s${NC}\n" "$(echo "$message" | tr '[:upper:]' '[:lower:]')" ;; # Keep error level msg lowercase
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

create_summary_file() {
    local summary_file="$HOME/okj-install/install-summary.txt"
    local env_type=$1
    local flux_env=$2
    local tenant_name=$(grep "^TENANT=" /etc/environment | cut -d'=' -f2 | tr -d "'\"" || echo "Not Set")
    local ip_addr=$(hostname -I | awk '{print $1}')
    
    local anydesk_id="Not Ready"
    log "INFO" "retrieving anydesk id for summary..."
    for i in {1..5}; do
        local current_id=$(anydesk --get-id 2>/dev/null | tr -d ' ' || sudo anydesk --get-id 2>/dev/null | tr -d ' ' || echo "")
        if [[ "$current_id" =~ [0-9] ]]; then
            anydesk_id=$(echo "$current_id" | grep -o '[0-9]*' | head -1)
            [ -n "$anydesk_id" ] && break
        fi
        sleep 2
    done
    
    {
        echo "  OKJ POS SYSTEM - INSTALLATION SUMMARY"
        echo "  ──────────────────────────────────────"
        echo "  · Date          : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  · Environment   : $env_type"
        echo "  · Tenant/Branch : $tenant_name"
        echo "  · Flux Env      : $flux_env"
        echo ""
        echo "  ACCESS DETAILS"
        echo "  ──────────────"
        echo "  · Local IP (SSH/pgAdmin) : $ip_addr"
        echo "  · AnyDesk ID             : $anydesk_id"
        echo "  · User (SSH/AnyDesk)     : okjadmin"
        echo "  · AnyDesk Password       : mu,wvmu2023"
        echo ""
        echo "  SERVICES"
        echo "  ────────"
        echo "  · pgAdmin4 URL  : http://$ip_addr:8080"
        echo "  · Email         : admin@ohkajhu.com"
        echo "  · Password      : Xw2#Rk9xLp"
        echo ""
        echo "  CLUSTER STATUS"
        echo "  ──────────────"
        echo "  · Nodes:"
        KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo kubectl get nodes --no-headers 2>/dev/null | awk '{print "    · " $1 " (" $2 ")"}' || echo "    · No nodes found"
        echo ""
        echo "  ──────────────────────────────────────"
    } > "$summary_file"
    
    log "SUCCESS" "created installation summary at: $summary_file"
}

# --- Check Permissions ---
if [ "$EUID" -eq 0 ]; then
   log "ERROR" "please run as regular user, not root/sudo"
   exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
#  HARDENING & UTILITY FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────
sudo_keep_alive() {
    while true; do
        sudo -n true
        sleep 60
    done 2>/dev/null &
    SUDO_PID=$!
    trap 'kill $SUDO_PID 2>/dev/null' EXIT
}

check_script() {
    local script_path=$1
    if [ ! -f "$script_path" ]; then
        log "ERROR" "critical script missing: $script_path"
        exit 1
    fi
    chmod +x "$script_path"
}

validate_essential_files() {
    log "INFO" "verifying essential installation components..."
    local required_files=(
        "flux-bootstrap.tar.gz"
        "okj-pos-pgsql.yaml"
        "redis.yaml"
        "asynqmon.yaml"
    )
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log "ERROR" "essential file missing: $file"
            exit 1
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  STATE MANAGEMENT (Smart Resume)
# ─────────────────────────────────────────────────────────────────────────────
STATE_FILE="$SCRIPT_DIR/.install_state"
START_FROM_STEP=1

save_state() {
    local step=$1
    cat <<EOF > "$STATE_FILE"
START_FROM_STEP=$((step + 1))
FLUX_ENV="$FLUX_ENV"
FLUX_SCRIPT="$FLUX_SCRIPT"
TENANT_NAME="$TENANT_NAME"
SHOP_CODE="$SHOP_CODE"
SHOP_TOKEN="$SHOP_TOKEN"
EOF
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
        return 0
    fi
    return 1
}

clear_state() {
    rm -f "$STATE_FILE"
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
    echo -e "${NC}${CLR_SECTION}   ━━━━━━  A U T O M A T I O N   S Y S T E M  ━━━━━━${NC}"
    echo -e "${CLR_DIM}                                       By TOTHEMARS 🚀${NC}\n"
}

print_banner
section "🚀 okj pos system - master installer"

# --- Check for Resume ---
if load_state; then
    section "🔄 interrupted installation detected"
    log "INFO" "last successful step: $((START_FROM_STEP - 1))"
    log "INFO" "tenant: $TENANT_NAME | shop: $SHOP_CODE"
    printf "\n  ${CLR_WARN}👉 do you want to resume from step $START_FROM_STEP? (y/n):${NC} "
    read RESUME_CONFIRM
    if [[ "$RESUME_CONFIRM" =~ ^[Yy]$ ]]; then
        log "SUCCESS" "resuming installation..."
        RESUMING=true
    else
        log "INFO" "starting fresh installation..."
        clear_state
        START_FROM_STEP=1
        RESUMING=false
    fi
else
    RESUMING=false
fi

# --- 0. Pre-flight Questionnaire ---
if [ "$RESUMING" = false ]; then
    section "📋 pre-flight questionnaire"

# 1. Environment Choice
printf "\n  ${CLR_INFO}Select flux environment:${NC}\n"
printf "    ${BOLD}1)${NC} Staging (stg)\n"
printf "    ${BOLD}2)${NC} Production (prd)\n\n"
while true; do
    printf "  ${CLR_INFO}👉 select (1 or 2):${NC} "
    read ENV_CHOICE
    case $ENV_CHOICE in
        1) FLUX_SCRIPT="install-stg.sh"; FLUX_ENV="staging"; break ;;
        2) FLUX_SCRIPT="install-prd.sh"; FLUX_ENV="production"; break ;;
        *) log "WARN" "invalid choice." ;;
    esac
done

# 2. Existing Tenant Check & Prompt
EXISTING_TENANT=$(grep "^TENANT=" /etc/environment 2>/dev/null | cut -d'=' -f2 | tr -d "'\"" || echo "")

if [ -n "$EXISTING_TENANT" ]; then
    printf "\n  ${CLR_DIM}· Current system tenant: ${EXISTING_TENANT}${NC}\n"
fi

while true; do
    if [ -n "$EXISTING_TENANT" ]; then
        printf "  ${CLR_INFO}👉 enter TENANT name (press Enter to use '${EXISTING_TENANT}'):${NC} "
    else
        printf "\n  ${CLR_INFO}👉 enter TENANT name:${NC} "
    fi
    read input_tenant
    
    # Sanitize input: remove carriage return, keep only printable chars, and trim whitespace
    input_tenant=$(echo "$input_tenant" | tr -d '\r' | tr -cd '[:print:]' | xargs)
    export TENANT_NAME=${input_tenant:-$EXISTING_TENANT}
    
    if [ -z "$TENANT_NAME" ]; then
        log "WARN" "TENANT name cannot be empty"
        continue
    fi
    
    if [[ ! $TENANT_NAME =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log "WARN" "TENANT name should only contain letters, numbers, -, _"
        continue
    fi
    break
done

# 3. Shop Configuration
while true; do
    printf "\n  ${CLR_INFO}👉 1. enter SHOP_CODE (e.g. jw101):${NC} "
    read input_shop
    export SHOP_CODE=$(echo "$input_shop" | tr -d '\r' | tr -cd '[:print:]' | xargs)
    
    printf "  ${CLR_INFO}👉 2. enter SHOP_TOKEN (gateway/rms):${NC} "
    read input_token
    export SHOP_TOKEN=$(echo "$input_token" | tr -d '\r' | tr -cd '[:print:]' | xargs)
    
    if [ -z "$SHOP_CODE" ] || [ -z "$SHOP_TOKEN" ]; then
        log "WARN" "shop_code and shop_token cannot be empty"
        continue
    fi
    break
done

# 4. Review & Confirm
echo ""
log "INFO" "📋 master configuration review:"
echo "  ──────────────────────────────────────────"
printf "  ${CLR_DIM}· FLUX_ENV           :${NC} %s\n" "$FLUX_ENV"
printf "  ${CLR_DIM}· TENANT_NAME        :${NC} %s\n" "$TENANT_NAME"
printf "  ${CLR_DIM}· SHOP_CODE          :${NC} %s\n" "$SHOP_CODE"
printf "  ${CLR_DIM}· SHOP_GATEWAY_TOKEN :${NC} %s\n" "$SHOP_TOKEN"
printf "  ${CLR_DIM}· SHOP_RMS_TOKEN     :${NC} %s\n" "$SHOP_TOKEN"
echo "  ──────────────────────────────────────────"
echo ""

while true; do
    printf "  ${CLR_WARN}👉 is this correct? (y/n):${NC} "
    read CONFIRM
    case $CONFIRM in
        [Yy]|[Yy]es) 
            export CONFIRM="y"
            break 
            ;;
        [Nn]|[Nn]o) 
            log "INFO" "installation cancelled."
            exit 0 
            ;;
        *) log "WARN" "Please answer y or n" ;;
    esac
done

# Cache sudo credentials upfront to prevent interruptions
if ! sudo -n true 2>/dev/null; then
    echo ""
    log "INFO" "authentication required to begin installation."
    sudo -v
fi

cd "$SCRIPT_DIR"
sudo_keep_alive
validate_essential_files

# --- 1. Step 1: Basic Tools ---
if [ "$START_FROM_STEP" -le 1 ]; then
    section "🧩 installing basic tools"
    log "INFO" "running tools installation script..."
    check_script "./script/01-install-tools-k3s.sh"
    ./script/01-install-tools-k3s.sh
    log "SUCCESS" "basic tools deployment complete"
    save_state 1
fi

# --- 2. Step 2: pgAdmin4 ---
if [ "$START_FROM_STEP" -le 2 ]; then
    section "📉 setup pgadmin4"
    log "INFO" "running pgadmin setup script..."
    check_script "./script/01-setup-pgadmin.sh"
    ./script/01-setup-pgadmin.sh
    log "SUCCESS" "pgadmin4 setup complete"
    save_state 2
fi

# --- 3. Step 3: K3s Cluster ---
if [ "$START_FROM_STEP" -le 3 ]; then
    section "☸️ installing k3s cluster"
    log "INFO" "running k3s installation with sudo..."
    check_script "./script/02-install-k3s.sh"
    sudo ./script/02-install-k3s.sh
    log "SUCCESS" "k3s cluster installation complete"
    save_state 3
fi

# --- 4. Step 4: Environment Variables ---
if [ "$START_FROM_STEP" -le 4 ]; then
    section "📝 setting environment & hosts"
    log "INFO" "applying environment variables..."
    check_script "./script/03-set-env.sh"
    ./script/03-set-env.sh
    log "SUCCESS" "environment configuration set"
    save_state 4
fi

# --- 5. Step 5: Flux Bootstrap ---
if [ "$START_FROM_STEP" -le 5 ]; then
    section "♾️ fluxcd bootstrap"
    log "STEP" "extracting flux-bootstrap components..."
    cd "$HOME"
    tar -xvf "$HOME/okj-install/flux-bootstrap.tar.gz" --no-same-owner --no-same-permissions >/dev/null

    if [ -d ".bootstrap" ]; then
        cd .bootstrap
        log "INFO" "installing fluxcd ($FLUX_SCRIPT)..."
        sudo "./$FLUX_SCRIPT"
        log "SUCCESS" "fluxcd installation complete"
        cd "$SCRIPT_DIR"

        log "INFO" "triggering immediate gitops sync..."
        sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml flux reconcile kustomization flux-system --with-source >/dev/null 2>&1 || true
    else
        log "ERROR" "bootstrap directory not found after extraction!"
        exit 1
    fi
    save_state 5
fi

# --- 6. Step 6: Cluster Services ---
if [ "$START_FROM_STEP" -le 6 ]; then
    section "🚀 installing cluster services"
    log "INFO" "running services deployment..."
    check_script "./script/05-install-services.sh"
    ./script/05-install-services.sh
    log "SUCCESS" "cluster services deployment initiated"
    save_state 6
fi

# --- 7. Step 7: Add WSL to Startup ---
if [ "$START_FROM_STEP" -le 7 ]; then
    section "🏠" "adding wsl to startup"
    log "INFO" "configuring auto-start for wsl backend..."
    check_script "./script/07-startup.sh"
    ./script/07-startup.sh
    log "SUCCESS" "startup configuration complete"
    save_state 7
fi

# --- 8. Step 8: Shop Configuration ---
if [ "$START_FROM_STEP" -le 8 ]; then
    section "🏪 shop configuration"
    log "INFO" "applying shop-specific settings..."
    check_script "./script/06-config-shop.sh"
    ./script/06-config-shop.sh
    log "SUCCESS" "shop configuration complete"
    save_state 8
fi

# --- 9. Final Steps: Summary ---
create_summary_file "WSL (Windows Subsystem for Linux)" "$FLUX_ENV"
clear_state

# ─────────────────────────────────────────────────────────────────────────────
#  COMPLETION
# ─────────────────────────────────────────────────────────────────────────────
printf "\n"
printf "  ${CLR_SUCCESS}✨  master installation completed!${NC}\n"
section "📋 installation summary"
cat "$HOME/okj-install/install-summary.txt" | sed 's/^/  /'
printf "\n"

section "🌐 system status"
KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo kubectl get node -o wide 2>/dev/null | awk '{print "  ·  " $0}' || echo "  · Unable to get node status."
printf "\n"
KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo kubectl get pod -A 2>/dev/null | head -n 15 | awk '{print "  ·  " $0}' || echo "  · Unable to get pod status."
printf "  ${CLR_DIM}... (showing top 15 pods)${NC}\n\n"
