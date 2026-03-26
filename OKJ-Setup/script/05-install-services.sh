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
        local tools_pods=$(echo "$all_pods" | grep "tools" || true)
        
        # 3. Check for non-ready pods in system namespaces
        local non_ready_system=$(echo "$all_pods" | grep -E "kube-system|flux-system" | grep -vE "Running|Completed" || true)
        
        # 4. Check for non-ready pods in tools
        local non_ready_tools=$(echo "$tools_pods" | grep -vE "Running|Completed" || true)

        # Logic: We must have at least SOME pods in tools, AND no system/tools pods are non-ready
        if [ -n "$tools_pods" ] && [ -z "$non_ready_system" ] && [ -z "$non_ready_tools" ]; then
            log "SUCCESS" "✅ System and Tools namespaces are ready."
            sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get pods -A
            return 0
        fi
        
        if [ -z "$tools_pods" ]; then
            log "INFO" "   Attempt $attempt/$max_attempts: Waiting for 'tools' namespace pods (CloudNativePG, Ingress, etc.) to start..."
        else
            local count=$(echo -e "${non_ready_system}\n${non_ready_tools}" | grep -v "^$" | wc -l || echo 0)
            log "INFO" "   Attempt $attempt/$max_attempts: $count core pods are not ready yet. Waiting 10s..."
        fi
        
        sleep 10
        ((attempt++))
    done
    
    log "WARN" "⚠️  Timeout waiting for system pods. Proceeding anyway..."
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
