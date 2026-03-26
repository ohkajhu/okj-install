#!/bin/bash
set -euo pipefail

# --- Colors ---
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Logging Helpers ---
log_step() { echo -e "${PURPLE}[MASTER]${NC} 🚀 $1"; }
log_success() { echo -e "${GREEN}[MASTER]${NC} ✅ $1"; }

section() {
    echo -e "\n${PURPLE}===========================================${NC}"
    echo -e "${PURPLE}   $*${NC}"
    echo -e "${PURPLE}===========================================${NC}"
}

create_summary_file() {
    local summary_file="$HOME/okj-install/install-summary.txt"
    local env_type=$1
    local flux_env=$2
    local tenant_name=$(grep "^TENANT=" /etc/environment | cut -d'=' -f2 | tr -d "'\"" || echo "Not Set")
    local ip_addr=$(hostname -I | awk '{print $1}')
    
    local anydesk_id=$(sudo anydesk --get-id 2>/dev/null | awk '{print $1}' || echo "Not Ready")
    
    {
        echo "==========================================="
        echo "    OKJ POS SYSTEM - INSTALLATION SUMMARY"
        echo "==========================================="
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
        echo "==========================================="
    } > "$summary_file"
    
    log_success "Created installation summary at: $summary_file"
}

# --- Check Permissions ---
if [ "$EUID" -eq 0 ]; then
   echo -e "${RED}[ERROR] Please run this script as a regular user, not root/sudo.${NC}"
   exit 1
fi

section "🚀 OKJ POS SYSTEM - MASTER INSTALLER (WSL)"

# --- 0. Get Environment Choice ---
echo -e "${CYAN}Please select the Flux environment to install:${NC}"
echo "  1) staging (stg)"
echo "  2) production (prd)"
read -p "Please select (1 or 2): " ENV_CHOICE

case $ENV_CHOICE in
    1) FLUX_SCRIPT="install-stg.sh"; FLUX_ENV="staging" ;;
    2) FLUX_SCRIPT="install-prd.sh"; FLUX_ENV="production" ;;
    *) echo -e "${RED}❌ Invalid choice. Installation cancelled.${NC}"; exit 1 ;;
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
else
    echo -e "${RED}❌ .bootstrap directory not found after extraction!${NC}"
    exit 1
fi

# --- 6. Step 6: Cluster Services ---
section "Step 6: Installing Cluster Services"
log_step "Running ./script/05-install-services.sh..."
./script/05-install-services.sh
log_success "Cluster services installed."

# --- 7. Step 7: Add WSL to Startup ---
section "Step 7: Adding WSL to Startup"
log_step "Running ./script/07-startup.sh..."
./script/07-startup.sh
log_success "Startup setup complete."

# --- 8. Step 8: Shop Configuration ---
section "Step 8: Shop Configuration"
log_step "Running ./script/06-config-shop.sh..."
./script/06-config-shop.sh
log_success "Shop configuration complete."

# --- 9. Final Steps: Summary ---
create_summary_file "WSL (Windows Subsystem for Linux)" "$FLUX_ENV"

# --- Final Summary ---
section "🎉 MASTER INSTALLATION COMPLETE"
echo -e "${GREEN}System installation completed successfully!${NC}"
echo -e "You can find the access details at:"
echo -e "${YELLOW}cat ~/okj-install/install-summary.txt${NC}"
echo -e "-------------------------------------------"
echo -e "${CYAN}Node Status:${NC}"
KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo kubectl get node -o wide 2>/dev/null || echo "Unable to get node status."
echo -e "\n${CYAN}Pod Status (All Namespaces):${NC}"
KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo kubectl get pod -A 2>/dev/null || echo "Unable to get pod status."
echo -e "==========================================="
