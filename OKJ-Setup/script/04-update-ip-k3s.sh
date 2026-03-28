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

section "🔧 k3s ip change & certificate recovery"

# Check if k3s and kubectl commands are available
if ! command -v k3s >/dev/null 2>&1; then
    log "ERROR" "🚨 k3s command not found. Please ensure k3s is installed correctly."
fi

# --- 1. Fix: Rotate Certificates ---
log "INFO" "📜  1. Attempting Certificate Rotation..."
log "INFO" "   - Stopping k3s service..."
sudo systemctl stop k3s

if sudo k3s certificate rotate; then
    log "SUCCESS" "✅ Certificates rotated successfully."
else
    log "WARN" "⚠️  Failed to execute k3s certificate rotate. Check k3s logs."
fi

log "INFO" "   - Starting k3s service and waiting 15s for components..."
sudo systemctl start k3s
sleep 15
log "SUCCESS" "✅ k3s started."

# --- 2. Fix: Update IP in Kubeconfig ---
log "INFO" "⚙️  2. Updating Kubeconfig (Fixing IP change)..."
NEW_IP=$(hostname -I | awk '{print $1}')
log "INFO" "   - Current Node IP detected: $NEW_IP"

# Read fresh config directly from k3s system path to ensure 127.0.0.1 is available to be replaced
sudo cat /etc/rancher/k3s/k3s.yaml | sed "s/127\.0\.0\.1/$NEW_IP/g" > "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
log "SUCCESS" "✅ Kubeconfig updated successfully."

# --- 3. Fix: Re-apply CoreDNS ---
log "INFO" "🔄 3. Re-applying CoreDNS custom host entries..."

if ! command -v jq >/dev/null 2>&1; then
    log "INFO" "📥 Installing jq..."
    sudo apt-get update -qq && sudo apt-get install -y jq -qq
fi

KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo kubectl get configmap coredns -n kube-system -o json | \
jq --arg ip1 "125.254.54.194" '
  .data.NodeHosts |= (
    split("\n")
    | map(select(length > 0))
    | map(select(
        (test("registry\\.ohkajhu\\.com") | not) and
        (test("shop-gateway\\.ohkajhu\\.com") | not)
      ))
    + [
        "\($ip1) registry.ohkajhu.com",
        "\($ip1) shop-gateway.ohkajhu.com"
      ]
    | join("\n")
  )
' | KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo kubectl apply -f - && log "SUCCESS" "✅ CoreDNS ConfigMap updated."

# --- 4. Verification ---
log "INFO" "✅ 4. Final Verification and component restart..."
KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo kubectl rollout restart deployment -n kube-system

log "INFO" "   - Waiting for CoreDNS (90s timeout)..."
KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo kubectl wait -n kube-system pod -l k8s-app=kube-dns --for=condition=ready --timeout=90s && log "SUCCESS" "✅ CoreDNS ready."

section "✨ recovery complete"
log "INFO" "➡️ Node Status:"
KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo kubectl get node -o wide