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

section "🔧 K3s IP Change & Certificate Recovery (Server)"

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

section "🎉 RECOVERY COMPLETE"
log "INFO" "➡️ Node Status:"
KUBECONFIG=/etc/rancher/k3s/k3s.yaml sudo kubectl get node -o wide