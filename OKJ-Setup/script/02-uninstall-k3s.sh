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
        "INFO")    echo -e "  ${B_BLUE}ℹ [INFO]${NC} $message" | tee -a "$log_out" ;;
        "WARN")    echo -e "  ${B_YELLOW}⚠ [WARN]${NC} $message" | tee -a "$log_out" ;;
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

section "🚫 Starting Complete K3s Removal"

# Pre-cleanup
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

# 3. Kill processes
log "INFO" "🧨 Killing remaining K3s processes..."
for p in k3s containerd kubelet; do
    run_or_skip pkill -f "$p"
done

# 4. Show binaries
log "INFO" "🔍 Existing K3s-related binaries:"
ls -la /usr/local/bin/ | grep -E "(k3s|kubectl|k$|crictl|ctr)" || log "INFO" "✅ No binaries found"

# 5. Remove binaries
log "INFO" "🧽 Removing K3s binaries..."
run_or_skip rm -f /usr/local/bin/{k3s*,kubectl*,k,generate-custom-ca-certs.sh,crictl,ctr}

# 6. Remove systemd
log "INFO" "🗑️ Removing systemd unit files..."
run_or_skip rm -f /etc/systemd/system/{k3s,k3s-node,k3s-agent}.service
run_or_skip systemctl daemon-reload
run_or_skip systemctl reset-failed

# 7. Clean directories
log "INFO" "🧹 Removing directories..."
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

# 8.1 Remove kubectl symlink
log "INFO" "🗑️ Checking and removing kubectl symlink..."
rm -f /usr/local/bin/k /usr/local/bin/kubectl 2>/dev/null || true

# 9. Unmount
log "INFO" "⛔ Unmounting K3s mounts..."
mount | grep -i k3s | awk '{print $3}' | xargs -r -n 1 umount -f || true

# 10. Network
log "INFO" "🧯 Removing network interfaces..."
interfaces=(cni0 flannel.1 flannel-v6.1 kube-bridge kube-ipvs0 flannel-wg flannel-wg-v6)
for iface in "${interfaces[@]}"; do
    if ip link show "$iface" &>/dev/null; then
        log "INFO" "🔪 Removing interface: $iface"
        run_or_skip ip link delete "$iface"
    fi
done

# 11. Iptables
log "INFO" "🔥 Cleaning up iptables rules..."
for table in filter nat mangle; do
    run_or_skip iptables -t "$table" -F
    run_or_skip iptables -t "$table" -X
done

# 12. Swap
log "INFO" "💾 Re-enabling swap..."
run_or_skip swapon -a

# 13. Safety
log "INFO" "🧨 Final cleanup..."
run_or_skip find /etc -name '*k3s*' -type f -delete
run_or_skip find /var -name '*k3s*' -type d -exec rm -rf {} + 

# 14. Restore External Container Networking (Docker)
if command -v docker >/dev/null 2>&1 && systemctl list-unit-files --type=service | grep -q "^docker.service"; then
    log "INFO" "🐳 Restarting Docker service to restore its network rules (iptables/veth)..."
    run_or_skip systemctl restart docker
    log "SUCCESS" "✅ Docker service restarted successfully."
fi

section "✅ K3s Uninstallation Complete"
log "WARN" "💡 Recommended: sudo reboot"
