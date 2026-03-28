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
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"

# --- Check Cluster Readiness ---
check_cluster_readiness() {
    section "🔍 checking cluster readiness"
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

section "🚀 installing cluster services"
check_cluster_readiness

# --- 1. PostgreSQL ---
section "🐘 setting up postgresql"
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
section "🏮 setting up redis & monitoring"
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
section "⚙️ setting up configmaps"
log "INFO" "Applying pos-shop-terminal-cm manifests..."
sudo KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f "$BASE_DIR/configmap/pos-shop-terminal-cm.yaml" -n apps
log "SUCCESS" "Terminal ConfigMap applied."

# --- Notice ---
echo ""
log "WARN" "⚠️  Note: pos-shop-service-cm.yaml configuration is handled in the next step."
log "INFO" "💡 You can run Step 6 (06-config-shop.sh) to configure it interactively."

section "✨ all services applied"
sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get pod -n pgsql
sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get pod -n apps
