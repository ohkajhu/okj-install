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

log "INFO" "environment: ubuntu server (native)"

# --- 0. Get Environment Choice ---
printf "\n  ${CLR_INFO}Please select flux environment:${NC}\n"
printf "    ${BOLD}1)${NC} staging (stg)\n"
printf "    ${BOLD}2)${NC} production (prd)\n\n"
printf "  ${CLR_INFO}👉 select (1 or 2):${NC} "
read ENV_CHOICE

case $ENV_CHOICE in
    1) FLUX_SCRIPT="install-stg.sh"; FLUX_ENV="staging" ;;
    2) FLUX_SCRIPT="install-prd.sh"; FLUX_ENV="production" ;;
    *) log "ERROR" "invalid choice. installation cancelled."; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- 1. Step 1: Basic Tools ---
section "🧩 installing basic tools"
log "INFO" "running tools installation script..."
./script/01-install-tools-k3s.sh
log "SUCCESS" "basic tools deployment complete"

# --- 2. Step 2: pgAdmin4 ---
section "📉 setup pgadmin4"
log "INFO" "running pgadmin setup script..."
./script/01-setup-pgadmin.sh
log "SUCCESS" "pgadmin4 setup complete"

# --- 3. Step 3: K3s Cluster ---
section "☸️ installing k3s cluster"
log "INFO" "running k3s installation with sudo..."
sudo ./script/02-install-k3s.sh
log "SUCCESS" "k3s cluster installation complete"

# --- 4. Step 4: Environment Variables ---
section "📝 setting environment & hosts"
log "INFO" "applying environment variables..."
./script/03-set-env.sh
log "SUCCESS" "environment configuration set"

# --- 5. Step 5: Flux Bootstrap ---
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

# --- 6. Step 6: Cluster Services ---
section "🚀 installing cluster services"
log "INFO" "running services deployment..."
./script/05-install-services.sh
log "SUCCESS" "cluster services deployment initiated"

# --- 7. Step 7: Shop Configuration ---
section "🏪 shop configuration"
log "INFO" "applying shop-specific settings..."
./script/06-config-shop.sh
log "SUCCESS" "shop configuration complete"

# --- 8. Final Steps: Summary ---
create_summary_file "Ubuntu Server (Native)" "$FLUX_ENV"

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
