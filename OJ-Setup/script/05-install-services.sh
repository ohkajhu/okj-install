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

# --- Check Cluster Readiness ---
check_cluster_readiness() {
    section "🔍 Checking Cluster Readiness"
    log "INFO" "Waiting for core system pods to be healthy..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # 1. Get all pods
        local all_pods=$(sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get pods -A --no-headers 2>/dev/null || true)
        
        # 2. Check if tools namespace has pods (it might take a while for Flux to create it)
        local tools_pods=$(echo "$all_pods" | awk '$1 == "tools"' || true)
        
        # 3. Check for non-ready pods in system namespaces
        local non_ready_system=$(echo "$all_pods" | awk '$1 ~ /^(kube-system|flux-system)$/ {split($3, a, "/"); if(a[1] != a[2] || ($4 != "Running" && $4 != "Completed")) print $0}' || true)
        
        # 4. Check for non-ready pods in tools (skip monitoring stack)
        local non_ready_tools=$(echo "$tools_pods" | grep -vE "k8s-monitoring|alloy" | awk '{split($3, a, "/"); if(a[1] != a[2] || ($4 != "Running" && $4 != "Completed")) print $0}' || true)

        # Logic: We must have at least SOME pods in tools, AND no system/tools pods are non-ready
        if [ -n "$tools_pods" ] && [ -z "$non_ready_system" ] && [ -z "$non_ready_tools" ]; then
            log "SUCCESS" "✅ System and Tools namespaces are ready."
            sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get pods -A
            return 0
        fi
        
        if [ -z "$tools_pods" ]; then
            log "INFO" "   Attempt $attempt/$max_attempts: Waiting for 'tools' namespace pods (CloudNativePG, Ingress, etc.) to start..."
        else
            local non_ready_list=$(echo -e "${non_ready_system}\n${non_ready_tools}" | grep -v "^$" || true)
            local count=$(echo "$non_ready_list" | wc -l || echo 0)
            log "INFO" "   Attempt $attempt/$max_attempts: $count core pods are not ready yet. Waiting 10s..."
            echo -e "$non_ready_list" | head -n 5 || true
        fi
        
        sleep 10
        ((attempt++))
    done
    
    log "WARN" "⚠️  Timeout waiting for system pods. Proceeding anyway..."
}

wait_for_ingress_webhook() {
    log "INFO" "⏳ Waiting for Ingress Admission Webhook endpoints to be ready..."
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Check if the admission service has endpoints
        local endpoints=$(sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get endpoints ingress-nginx-controller-admission -n tools -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
        
        if [ -n "$endpoints" ]; then
            log "SUCCESS" "✅ Ingress Admission Webhook is ready."
            return 0
        fi
        
        log "INFO" "     Attempt $attempt/$max_attempts: Webhook endpoints not ready yet. Waiting 5s..."
        sleep 5
        ((attempt++))
    done
    
    log "WARN" "⚠️ Webhook endpoints not ready after $max_attempts attempts. Retrying application may be needed."
}

wait_for_crd() {
    local crd=$1
    log "INFO" "⏳ Waiting for CRD: $crd..."
    for i in {1..30}; do
        if sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get crd "$crd" &>/dev/null; then
            log "SUCCESS" "✅ CRD $crd is ready."
            return 0
        fi
        sleep 10
    done
    log "ERROR" "❌ Timeout waiting for CRD: $crd. CloudNativePG might still be installing."
}

wait_for_service_endpoints() {
    local service_name=$1
    local namespace=$2
    log "INFO" "⏳ Waiting for service endpoints: $service_name ($namespace)..."
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Check if the service has endpoints
        local endpoints=$(sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get endpoints "$service_name" -n "$namespace" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
        
        if [ -n "$endpoints" ]; then
            log "SUCCESS" "✅ Service $service_name is ready."
            return 0
        fi
        
        log "INFO" "     Attempt $attempt/$max_attempts: No endpoints yet. Waiting 5s..."
        sleep 5
        ((attempt++))
    done
    
    log "WARN" "⚠️ Service $service_name endpoints not ready after $max_attempts attempts."
}

section "🚀 Installing Cluster Services"
check_cluster_readiness

# --- 1. PostgreSQL ---
section "🐘 Setting up PostgreSQL"
if ! sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get namespace pgsql &>/dev/null; then
    log "INFO" "Creating namespace: pgsql"
    sudo KUBECONFIG=$KUBECONFIG_PATH kubectl create namespace pgsql
else
    log "INFO" "Namespace 'pgsql' already exists."
fi

log "INFO" "Applying PostgreSQL manifests..."
wait_for_crd "clusters.postgresql.cnpg.io"
# Wait for CNPG Admission Webhook to be ready
wait_for_service_endpoints "cnpg-webhook-service" "tools"
sudo KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f "$BASE_DIR/okj-pos-pgsql.yaml" -n pgsql
log "SUCCESS" "PostgreSQL resources applied."

# --- 2. Redis & Asynqmon ---
section "🏮 Setting up Redis & Monitoring"
if ! sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get namespace apps &>/dev/null; then
    log "INFO" "Creating namespace: apps"
    sudo KUBECONFIG=$KUBECONFIG_PATH kubectl create namespace apps
else
    log "INFO" "Namespace 'apps' already exists."
fi

log "INFO" "Applying Redis manifests..."
sudo KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f "$BASE_DIR/redis.yaml" -n apps
log "SUCCESS" "Redis resources applied."

log "INFO" "Applying Asynqmon manifests..."
# Ingress-nginx webhook race condition fix
wait_for_ingress_webhook
sudo KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f "$BASE_DIR/asynqmon.yaml" -n apps
log "SUCCESS" "Asynqmon resources applied."

# --- 3. ConfigMaps ---
section "⚙️ Setting up ConfigMaps"
log "INFO" "Applying pos-shop-terminal-cm manifests..."
sudo KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f "$BASE_DIR/configmap/pos-shop-terminal-cm.yaml" -n apps
log "SUCCESS" "Terminal ConfigMap applied."

# --- Notice ---
echo ""
log "WARN" "⚠️  Note: pos-shop-service-cm.yaml configuration is handled in the next step."
log "INFO" "💡 You can run Step 6 (06-config-shop.sh) to configure it interactively."

section "✅ ALL SERVICES APPLIED"
sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get pod -n pgsql
sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get pod -n apps
