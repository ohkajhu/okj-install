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
BASE_DIR="$SCRIPT_DIR"
KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"

# --- Check Cluster Readiness ---
check_cluster_readiness() {
    section "🔍 Checking Cluster Readiness"
    log "INFO" "Waiting for core system pods to be healthy..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # We check pods in kube-system, flux-system, and tools.
        # We wait until they are either 'Running' or 'Completed'.
        local non_ready_pods=$(sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get pods -A --no-headers | grep -E "kube-system|flux-system|tools" | grep -vE "Running|Completed" || true)
        
        if [ -z "$non_ready_pods" ]; then
            log "SUCCESS" "✅ System namespaces are ready."
            sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get pods -A
            return 0
        fi
        
        local count=$(echo "$non_ready_pods" | wc -l)
        log "INFO" "   Attempt $attempt/$max_attempts: $count pods in system namespaces are not ready yet. Waiting 10s..."
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

# --- Warning Message ---
echo ""
log "WARN" "⚠️  Note: pos-shop-service-cm.yaml was skipped."
log "INFO" "💡 You must manually configure its token for this branch before applying:"
log "INFO" "   Location: $BASE_DIR/configmap/pos-shop-service-cm.yaml"
log "INFO" "   Command: sudo kubectl apply -f $BASE_DIR/configmap/pos-shop-service-cm.yaml -n apps"

section "✅ ALL SERVICES APPLIED"
sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get pod -n pgsql
sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get pod -n apps
