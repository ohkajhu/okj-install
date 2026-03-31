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
   exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"

# --- Robust Manifest Apply ---
robust_apply() {
    local manifest=$1
    local namespace=$2
    local max_retry=5
    local retry_count=0
    
    # Verify file exists
    if [ ! -f "$manifest" ]; then
        log "ERROR" "Manifest file not found: $manifest"
        exit 1
    fi

    log "INFO" "Applying manifest: $(basename "$manifest") in $namespace..."
    
    while [ $retry_count -lt $max_retry ]; do
        if sudo KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f "$manifest" -n "$namespace" 2>/tmp/apply_err; then
            log "SUCCESS" "$(basename "$manifest") applied successfully."
            return 0
        else
            local err_msg=$(cat /tmp/apply_err)
            # Common transient errors: Webhook TLS, Connection refused, API timeout
            if [[ "$err_msg" == *"x509"* ]] || [[ "$err_msg" == *"connection refused"* ]] || [[ "$err_msg" == *"timeout"* ]] || [[ "$err_msg" == *"validate.nginx.ingress.kubernetes.io"* ]]; then
                ((retry_count++))
                log "WARN" "⚠️ Transient error detected (attempt $retry_count/$max_retry). Waiting 10s before retry..."
                sleep 10
            else
                log "ERROR" "Failed to apply $(basename "$manifest"):"
                echo "$err_msg"
                exit 1
            fi
        fi
    done
    
    log "ERROR" "❌ Failed to apply $(basename "$manifest") after $max_retry attempts."
    exit 1
}

# --- Check Cluster Readiness ---
check_cluster_readiness() {
    section "🔍 checking cluster readiness"
    log "INFO" "Waiting for core system pods to be healthy..."
    
    local max_attempts=60  # Increased to 10 minutes
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local all_pods=$(sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get pods -A --no-headers 2>/dev/null || true)
        
        # Tools namespace pods (CloudNativePG, Ingress, etc.)
        local tools_pods=$(echo "$all_pods" | awk '$1 == "tools"' || true)
        
        # System & Flux pods
        local non_ready_system=$(echo "$all_pods" | awk '$1 ~ /^(kube-system|flux-system)$/ {split($3, a, "/"); if(a[1] != a[2] || ($4 != "Running" && $4 != "Completed")) print $0}' || true)
        
        # Tools pods (excluding monitoring)
        local non_ready_tools=$(echo "$tools_pods" | grep -vE "k8s-monitoring|alloy" | awk '{split($3, a, "/"); if(a[1] != a[2] || ($4 != "Running" && $4 != "Completed")) print $0}' || true)

        if [ -n "$tools_pods" ] && [ -z "$non_ready_system" ] && [ -z "$non_ready_tools" ]; then
            log "SUCCESS" "✅ System and Tools namespaces are ready."
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log "ERROR" "❌ Timeout waiting for cluster readiness after $max_attempts attempts."
            echo "Non-ready pods found:"
            echo -e "${non_ready_system}\n${non_ready_tools}" | grep -v "^$" || echo "None"
            exit 1
        fi

        if [ -z "$tools_pods" ]; then
            log "INFO" "   Attempt $attempt/$max_attempts: Waiting for 'tools' namespace..."
        else
            local count=$(echo -e "${non_ready_system}\n${non_ready_tools}" | grep -v "^$" | wc -l || echo 0)
            log "INFO" "   Attempt $attempt/$max_attempts: $count core pods not ready... waiting 10s"
        fi
        
        sleep 10
        ((attempt++))
    done
}

wait_for_ingress_webhook() {
    log "INFO" "⏳ Waiting for Ingress Admission Webhook..."
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local endpoints=$(sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get endpoints ingress-nginx-controller-admission -n tools -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
        
        if [ -n "$endpoints" ]; then
            log "SUCCESS" "✅ Ingress Webhook endpoint ready."
            return 0
        fi
        
        [ $attempt -eq $max_attempts ] && { log "ERROR" "❌ Ingress Webhook never became ready."; exit 1; }
        
        sleep 5
        ((attempt++))
    done
}

wait_for_crd() {
    local crd=$1
    log "INFO" "⏳ Waiting for CRD: $crd..."
    for i in {1..30}; do
        if sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get crd "$crd" &>/dev/null; then
            log "SUCCESS" "✅ CRD $crd ready."
            return 0
        fi
        sleep 10
    done
    log "ERROR" "❌ Timeout waiting for CRD: $crd."
    exit 1
}

wait_for_service_endpoints() {
    local service_name=$1
    local namespace=$2
    log "INFO" "⏳ Waiting for service endpoints: $service_name ($namespace)..."
    local max_attempts=20
    for i in $(seq 1 $max_attempts); do
        local endpoints=$(sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get endpoints "$service_name" -n "$namespace" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
        if [ -n "$endpoints" ]; then
            log "SUCCESS" "✅ Service $service_name ready."
            return 0
        fi
        sleep 5
    done
    log "ERROR" "❌ Service $service_name endpoints not ready."
    exit 1
}

# --- Main Flow ---
section "🚀 installing cluster services"
check_cluster_readiness

# --- 1. PostgreSQL ---
section "🐘 setting up postgresql"
if ! sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get namespace pgsql &>/dev/null; then
    log "INFO" "Creating namespace: pgsql"
    sudo KUBECONFIG=$KUBECONFIG_PATH kubectl create namespace pgsql
fi

wait_for_crd "clusters.postgresql.cnpg.io"
wait_for_service_endpoints "cnpg-webhook-service" "tools"

robust_apply "$BASE_DIR/okj-pos-pgsql.yaml" "pgsql"

# --- 2. Redis & Asynqmon ---
section "🏮 setting up redis & monitoring"
if ! sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get namespace apps &>/dev/null; then
    log "INFO" "Creating namespace: apps"
    sudo KUBECONFIG=$KUBECONFIG_PATH kubectl create namespace apps
fi

robust_apply "$BASE_DIR/redis.yaml" "apps"

# Ingress-nginx webhook race condition fix
wait_for_ingress_webhook
robust_apply "$BASE_DIR/asynqmon.yaml" "apps"

# --- 3. ConfigMaps ---
section "⚙️ setting up configmaps"
robust_apply "$BASE_DIR/configmap/pos-shop-terminal-cm.yaml" "apps"

# --- Notice ---
echo ""
log "WARN" "⚠️  Note: pos-shop-service-cm.yaml configuration is handled in the next step."
log "INFO" "💡 You can run Step 6 (06-config-shop.sh) to configure it interactively."

section "✨ all services applied"
sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get pod -n pgsql
sudo KUBECONFIG=$KUBECONFIG_PATH kubectl get pod -n apps
