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

section "🔧 K3s IP Change & Certificate Recovery"

# ตรวจสอบว่าคำสั่ง k3s และ kubectl ใช้งานได้หรือไม่
if ! command -v k3s >/dev/null 2>&1; then
    log "ERROR" "🚨 k3s command not found. Please ensure k3s is installed correctly."
fi

# --- 1. Fix: แก้ไข IP ใน Kubeconfig ---
log "INFO" "⚙️  1. Updating Kubeconfig (Fixing IP change)..."
NEW_IP=$(hostname -I | awk '{print $1}')
log "INFO" "   - Current Node IP detected: $NEW_IP"

# ดึง config ล่าสุด และแทนที่ 127.0.0.1 ด้วย IP ใหม่
k3s kubectl config view --raw | sed "s/127\.0\.0\.1/$NEW_IP/g" > "$HOME/.kube/config"

chmod 600 "$HOME/.kube/config"
log "SUCCESS" "✅ Kubeconfig updated successfully."

# --- 2. Fix: หมุนเวียน Certificate ---
log "INFO" "📜  2. Attempting Certificate Rotation..."
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

# --- 3. Fix: Re-apply CoreDNS ---
log "INFO" "🔄  3. Re-applying CoreDNS custom host entries..."

if ! command -v jq >/dev/null 2>&1; then
    log "INFO" "📥 Installing jq (required for CoreDNS fix)..."
    sudo apt-get update -qq && sudo apt-get install -y jq -qq
fi

kubectl get configmap coredns -n kube-system -o json | \
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
' | kubectl apply -f - && log "SUCCESS" "✅ CoreDNS ConfigMap updated."

# --- 4. Verification ---
log "INFO" "✅  4. Final Verification and component restart..."
kubectl rollout restart deployment -n kube-system

log "INFO" "   - Waiting for CoreDNS (90s timeout)..."
kubectl wait -n kube-system pod -l k8s-app=kube-dns --for=condition=ready --timeout=90s && log "SUCCESS" "✅ CoreDNS ready."

section "🎉 RECOVERY COMPLETE"
log "INFO" "➡️  Node Status:"
kubectl get node -o wide