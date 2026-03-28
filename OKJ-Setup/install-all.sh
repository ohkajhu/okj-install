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
log_step() { echo -e "\n${B_CYAN} ➜ ${NC} ${B_WHITE}$1${NC}"; }
log_success() { echo -e "   ${B_GREEN}╰─ ✔ $1${NC}"; }
log_err() { echo -e "\n${BG_RED}${B_WHITE} ❌ ERROR ${NC} ${B_RED}$1${NC}\n"; }

section() {
    local title="$1"
    local clean_title=$(echo -e "$title" | sed 's/\x1b\[[0-9;]*m//g')
    local title_len=${#clean_title}
    local width=55
    local pad_len=$((width - title_len))
    [ $pad_len -lt 0 ] && pad_len=0
    local padding=$(printf "%${pad_len}s" "")

    echo -e "${B_PURPLE}╭─────────────────────────────────────────────────────────╮${NC}"
    echo -e "${B_PURPLE}│${NC} ${B_WHITE}${title}${NC}${padding} ${B_PURPLE}│${NC}"
    echo -e "${B_PURPLE}╰─────────────────────────────────────────────────────────╯${NC}"
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

create_summary_file() {
    local summary_file="$HOME/okj-install/install-summary.txt"
    local env_type=$1
    local flux_env=$2
    local tenant_name=$(grep "^TENANT=" /etc/environment | cut -d'=' -f2 | tr -d "'\"" || echo "Not Set")
    local ip_addr=$(hostname -I | awk '{print $1}')
    
    # Try to get AnyDesk ID with retries (similar to Step 1)
    local anydesk_id="Not Ready"
    log_step "Retrieving AnyDesk ID for summary..."
    for i in {1..5}; do
        local current_id=$(anydesk --get-id 2>/dev/null | tr -d ' ' || sudo anydesk --get-id 2>/dev/null | tr -d ' ' || echo "")
        if [[ "$current_id" =~ [0-9] ]]; then
            anydesk_id=$(echo "$current_id" | grep -o '[0-9]*' | head -1)
            [ -n "$anydesk_id" ] && break
        fi
        sleep 2
    done
    
    {
        echo "───────────────────────────────────────────"
        echo "    OKJ POS SYSTEM - INSTALLATION SUMMARY"
        echo "───────────────────────────────────────────"
        echo "Date         : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Environment  : $env_type"
        echo "Tenant/Branch: $tenant_name"
        echo "Flux Env     : $flux_env"
        echo ""
        echo "--- ACCESS DETAILS ---"
        echo "Local IP (SSH/pgAdmin): $ip_addr"
        echo "AnyDesk ID            : $anydesk_id"
        echo "User (SSH/AnyDesk)    : okjadmin"
        echo "AnyDesk Password      : mu,wvmu2023"
        echo ""
        echo "--- SERVICES ---"
        echo "pgAdmin4 URL : http://$ip_addr:8080"
        echo "Email        : admin@ohkajhu.com"
        echo "Password     : Xw2#Rk9xLp"
        echo ""
        echo "--- CLUSTER STATUS ---"
        echo "Nodes:"
        KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo kubectl get nodes --no-headers 2>/dev/null | awk '{print "  - " $1 " (" $2 ")"}' || echo "  - No nodes found"
        echo ""
        echo "───────────────────────────────────────────"
    } > "$summary_file"
    
    log_success "Created installation summary at: $summary_file"
}

# --- Check Permissions ---
if [ "$EUID" -eq 0 ]; then
   log_err "Please run this script as a regular user, not root/sudo."
   exit 1
fi

print_banner
section "OKJ POS SYSTEM - MASTER INSTALLER (Ubuntu Server)"

# --- 0. Get Environment Choice ---
echo -e "${B_CYAN}Please select the Flux environment to install:${NC}"
echo -e "  ${B_WHITE}1) staging (stg)${NC}"
echo -e "  ${B_WHITE}2) production (prd)${NC}"
echo ""
read -p "👉 Please select (1 or 2): " ENV_CHOICE

case $ENV_CHOICE in
    1) FLUX_SCRIPT="install-stg.sh"; FLUX_ENV="staging" ;;
    2) FLUX_SCRIPT="install-prd.sh"; FLUX_ENV="production" ;;
    *) log_err "Invalid choice. Installation cancelled."; exit 1 ;;
esac

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- 1. Step 1: Basic Tools ---
section "Step 1: Installing Basic Tools"
log_step "Running ./script/01-install-tools-k3s.sh..."
./script/01-install-tools-k3s.sh
log_success "Basic tools installed."

# --- 2. Step 2: pgAdmin4 ---
section "Step 2: Setup pgAdmin4"
log_step "Running ./script/01-setup-pgadmin.sh..."
./script/01-setup-pgadmin.sh
log_success "pgAdmin4 setup complete."

# --- 3. Step 3: K3s Cluster ---
section "Step 3: Installing K3s Cluster"
log_step "Running sudo ./script/02-install-k3s.sh..."
sudo ./script/02-install-k3s.sh
log_success "K3s installation complete."

# --- 4. Step 4: Environment Variables ---
section "Step 4: Setting Environment & Hosts"
log_step "Running ./script/03-set-env.sh..."
./script/03-set-env.sh
log_success "Environment set."

# --- 5. Step 5: Flux Bootstrap ---
section "Step 5: Flux Bootstrap"
log_step "Extracting flux-bootstrap.tar.gz to home..."
cd "$HOME"
tar -xvf "$HOME/okj-install/flux-bootstrap.tar.gz" --no-same-owner --no-same-permissions

if [ -d ".bootstrap" ]; then
    cd .bootstrap
    log_step "Installing Flux ($FLUX_SCRIPT)..."
    sudo "./$FLUX_SCRIPT"
    log_success "Flux installation complete."
    cd "$SCRIPT_DIR"

    # เร่งสปีดให้ Flux ซิงค์ทันทีโดยไม่ต้องรอรอบเวลา
    log_step "Triggering Flux reconcile (forcing immediate GitOps sync)..."
    sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml flux reconcile kustomization flux-system --with-source || echo -e "${YELLOW}⚠️ Flux reconcile warning (continuing...)${NC}"
else
    echo -e "${RED}❌ .bootstrap directory not found after extraction!${NC}"
    exit 1
fi

# --- 6. Step 6: Cluster Services ---
section "Step 6: Installing Cluster Services"
log_step "Running ./script/05-install-services.sh..."
./script/05-install-services.sh
log_success "Cluster services installed."

# --- 7. Step 7: Shop Configuration ---
section "Step 7: Shop Configuration"
log_step "Running ./script/06-config-shop.sh..."
./script/06-config-shop.sh
log_success "Shop configuration complete."

# --- 8. Final Steps: Summary ---
create_summary_file "Ubuntu Server (Native)" "$FLUX_ENV"

# --- Final Summary ---
echo -e "\n${B_GREEN}╭─────────────────────────────────────────────────────────╮${NC}"
echo -e "${B_GREEN}│ 🎉 MASTER INSTALLATION COMPLETED SUCCESSFULLY           │${NC}"
echo -e "${B_GREEN}╰─────────────────────────────────────────────────────────╯${NC}"
echo -e "  A detailed summary with credentials has been generated:"
echo -e "  👉 ${B_YELLOW}cat ~/okj-install/install-summary.txt${NC}\n"

echo -e "${B_CYAN}╭─ 🌐 SYSTEM STATUS ───────────────────────────────────────╮${NC}"
echo -e "${B_CYAN}│ Nodes:${NC}"
KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo kubectl get node -o wide 2>/dev/null | awk '{print "│  " $0}' || echo "│  Unable to get node status."
echo -e "${B_CYAN}│${NC}"
echo -e "${B_CYAN}│ Pods (All Namespaces):${NC}"
KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo kubectl get pod -A 2>/dev/null | awk '{print "│  " $0}' || echo "│  Unable to get pod status."
echo -e "${B_CYAN}╰──────────────────────────────────────────────────────────╯${NC}"
