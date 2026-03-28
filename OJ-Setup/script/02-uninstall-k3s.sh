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

section "🚫 Starting Complete K3s Removal"

# Pre-cleanup: Remove potential lingering files from failed previous attempts
log "INFO" "🧹 Pre-cleanup: Removing common leftover files..."
sudo rm -f /usr/local/bin/k 2>/dev/null || true
sudo rm -rf /root/.kube 2>/dev/null || true
log "SUCCESS" "✅ Pre-cleanup complete."

# Check root
if [ "$(id -u)" -ne 0 ]; then
    log "ERROR" "🔒 Please run this script as root (use sudo)."
fi

# Function helper
run_or_skip() {
    "$@" 2>/dev/null || true
}

# 1. Stop K3s services
log "INFO" "🛑 Stopping K3s service..."
run_or_skip systemctl stop k3s
run_or_skip systemctl disable k3s

# 2. Run uninstall script
if [ -x /usr/local/bin/k3s-uninstall.sh ]; then
    log "INFO" "🧹 Running official K3s uninstall script..."
    /usr/local/bin/k3s-uninstall.sh
else
    log "WARN" "⚠️ K3s uninstall script not found, continuing with manual cleanup..."
fi

# 3. Kill remaining processes
log "INFO" "🧨 Killing remaining K3s/container processes..."
for p in k3s containerd kubelet; do
    run_or_skip pkill -f "$p"
done

# 4. Show binaries before removing
log "INFO" "🔍 Existing K3s-related binaries:"
ls -la /usr/local/bin/ | grep -E "(k3s|kubectl|k$|crictl|ctr)" || log "INFO" "✅ No binaries found"

# 5. Remove binaries
log "INFO" "🧽 Removing K3s binaries and helpers..."
run_or_skip rm -f /usr/local/bin/{k3s*,kubectl*,k,generate-custom-ca-certs.sh,crictl,ctr}

# 6. Remove systemd files
log "INFO" "🗑️ Removing systemd unit files..."
run_or_skip rm -f /etc/systemd/system/{k3s,k3s-node,k3s-agent}.service
run_or_skip systemctl daemon-reload
run_or_skip systemctl reset-failed

# 7. Clean directories
log "INFO" "🧹 Removing directories and K3s data..."
dirs_to_remove=(
    /etc/rancher/k3s
    /etc/rancher/node
    /var/lib/rancher/k3s
    /var/lib/rancher/k3s-storage
    /var/lib/kubelet
    /var/lib/cni
    /var/log/pods
    /var/log/containers
    /opt/cni
    /run/k3s
    /run/flannel
    /var/lib/containerd
    /run/containerd
)
for dir in "${dirs_to_remove[@]}"; do
    run_or_skip rm -rf "$dir"
done

# 8. Kube config cleanup
log "INFO" "🧼 Removing kubeconfig..."
rm -rf /root/.kube 2>/dev/null || true
rm -rf "$HOME/.kube" 2>/dev/null || true

# 8.1 Remove kubectl symlink and binary if they belong to K3s
log "INFO" "🗑️ Checking and removing kubectl and k symlink..."

if [ -L /usr/local/bin/k ]; then
    log "INFO" "🔗 Removing symlink /usr/local/bin/k"
    rm -f /usr/local/bin/k
fi

if [ -f /usr/local/bin/kubectl ]; then
    if file /usr/local/bin/kubectl | grep -q "symbolic link to.*k3s"; then
        log "INFO" "📎 kubectl is linked to k3s, removing it..."
        rm -f /usr/local/bin/kubectl
    elif strings /usr/local/bin/kubectl | grep -q 'k3s'; then
        log "INFO" "🔍 kubectl binary seems to come from K3s, removing it..."
        rm -f /usr/local/bin/kubectl
    else
        log "WARN" "⚠️ kubectl exists but does not seem to belong to K3s, skipping removal."
    fi
fi

# 9. Unmount any remaining k3s mounts
log "INFO" "⛔ Unmounting K3s mounts..."
mount | grep -i k3s | awk '{print $3}' | xargs -r -n 1 umount -f || true

# 10. Remove leftover interfaces
log "INFO" "🧯 Removing network interfaces..."
interfaces=(cni0 flannel.1 flannel-v6.1 kube-bridge kube-ipvs0 flannel-wg flannel-wg-v6)
for iface in "${interfaces[@]}"; do
    if ip link show "$iface" &>/dev/null; then
        log "INFO" "🔪 Removing interface: $iface"
        run_or_skip ip link delete "$iface"
    fi
done

# 11. Clean veth interfaces
log "INFO" "🧹 Cleaning up veth interfaces..."
for veth in $(ip link | awk -F: '/veth/ {print $2}' | xargs); do
    log "INFO" "🔪 Deleting veth: $veth"
    run_or_skip ip link delete "$veth"
done

# 12. Clean iptables
log "INFO" "🔥 Cleaning up iptables rules..."
for table in filter nat mangle; do
    run_or_skip iptables -t "$table" -F
    run_or_skip iptables -t "$table" -X
done

# 13. Re-enable swap
log "INFO" "💾 Re-enabling swap..."
run_or_skip swapon -a

# 14. Extra safety cleanup
log "INFO" "🧨 Final cleanup of leftover files..."
run_or_skip find /etc -name '*k3s*' -type f -delete
run_or_skip find /var -name '*k3s*' -type d -exec rm -rf {} + 
run_or_skip find /run -name '*k3s*' -type d -exec rm -rf {} +

# 15. Restore External Container Networking (Docker)
if command -v docker >/dev/null 2>&1 && systemctl list-unit-files --type=service | grep -q "^docker.service"; then
    log "INFO" "🐳 Restarting Docker service to restore its network rules (iptables/veth)..."
    run_or_skip systemctl restart docker
    log "SUCCESS" "✅ Docker service restarted successfully."
fi

section "✅ K3s Uninstallation Complete"
log "SUCCESS" "Verification steps recommended:"
log "INFO" "  - ps aux | grep -i k3s"
log "INFO" "  - ip link show"
log "WARN" "💡 Recommended: sudo reboot"
