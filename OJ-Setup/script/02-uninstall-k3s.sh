#!/bin/bash
set -e

echo "=== 🚫 Starting Complete K3s Removal ==="

# Pre-cleanup: Remove potential lingering files from failed previous attempts
echo "🧹 Pre-cleanup: Removing common leftover files from previous installations..."
sudo rm -f /usr/local/bin/k 2>/dev/null || true
sudo rm -rf /root/.kube 2>/dev/null || true
echo "✅ Pre-cleanup complete."
echo "---"

# ใช้ sudo แค่ตอนรัน script
if [ "$(id -u)" -ne 0 ]; then
  echo "🔒 Please run this script as root (use sudo)."
  exit 1
fi

# Function helper
run_or_skip() {
  "$@" 2>/dev/null || true
}

# 1. Stop K3s services
echo "🛑 Stopping K3s service..."
run_or_skip systemctl stop k3s
run_or_skip systemctl disable k3s

# 2. Run uninstall script
if [ -x /usr/local/bin/k3s-uninstall.sh ]; then
  echo "🧹 Running official K3s uninstall script..."
  /usr/local/bin/k3s-uninstall.sh
else
  echo "⚠️ K3s uninstall script not found, continuing with manual cleanup..."
fi

# 3. Kill remaining processes
echo "🧨 Killing remaining K3s/container processes..."
for p in k3s containerd kubelet; do
  run_or_skip pkill -f "$p"
done

# 4. Show binaries before removing
echo "🔍 Existing K3s-related binaries:"
ls -la /usr/local/bin/ | grep -E "(k3s|kubectl|k$|crictl|ctr)" || echo "✅ No binaries found"

# 5. Remove binaries
echo "🧽 Removing K3s binaries and helpers..."
run_or_skip rm -f /usr/local/bin/{k3s*,kubectl*,k,generate-custom-ca-certs.sh,crictl,ctr}

# 6. Remove systemd files
echo "🗑️ Removing systemd unit files..."
run_or_skip rm -f /etc/systemd/system/{k3s,k3s-node,k3s-agent}.service
run_or_skip systemctl daemon-reload
run_or_skip systemctl reset-failed

# 7. Clean directories
echo "🧹 Removing directories and K3s data..."
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
echo "🧼 Removing kubeconfig..."
rm -rf /root/.kube 2>/dev/null || true
rm -rf "$HOME/.kube" 2>/dev/null || true

# 8.1 Remove kubectl symlink and binary if they belong to K3s
echo "🗑️ Checking and removing kubectl and k symlink if created by K3s..."

if [ -L /usr/local/bin/k ]; then
  echo "🔗 Removing symlink /usr/local/bin/k"
  rm -f /usr/local/bin/k
fi

if [ -f /usr/local/bin/kubectl ]; then
  # Check if it's symlinked to k3s or installed by k3s
  if file /usr/local/bin/kubectl | grep -q "symbolic link to.*k3s"; then
    echo "📎 kubectl is linked to k3s, removing it..."
    rm -f /usr/local/bin/kubectl
  elif strings /usr/local/bin/kubectl | grep -q 'k3s'; then
    echo "🔍 kubectl binary seems to come from K3s, removing it..."
    rm -f /usr/local/bin/kubectl
  else
    echo "⚠️ kubectl exists but does not seem to belong to K3s, skipping removal."
  fi
fi

# 9. Unmount any remaining k3s mounts
echo "⛔ Unmounting K3s mounts..."
mount | grep -i k3s | awk '{print $3}' | xargs -r -n 1 umount -f || true

# 10. Remove leftover interfaces
echo "🧯 Removing network interfaces..."
interfaces=(cni0 flannel.1 flannel-v6.1 kube-bridge kube-ipvs0 flannel-wg flannel-wg-v6)
for iface in "${interfaces[@]}"; do
  ip link show "$iface" &>/dev/null && {
    echo "🔪 Removing interface: $iface"
    run_or_skip ip link delete "$iface"
  }
done

# 11. Clean veth interfaces
echo "🧹 Cleaning up veth interfaces..."
for veth in $(ip link | awk -F: '/veth/ {print $2}' | xargs); do
  echo "🔪 Deleting veth: $veth"
  run_or_skip ip link delete "$veth"
done

# 12. Clean iptables (optional but useful)
echo "🔥 Cleaning up iptables rules..."
for table in filter nat mangle; do
  run_or_skip iptables -t "$table" -F
  run_or_skip iptables -t "$table" -X
done

# 13. Re-enable swap
echo "💾 Re-enabling swap..."
run_or_skip swapon -a

# Warn about /etc/fstab missing swap
if ! grep -q swap /etc/fstab; then
  echo -e "\n⚠️ WARNING: No swap entry found in /etc/fstab"
  echo "You might want to re-add a swap entry. Example:"
  echo "  /swapfile none swap sw 0 0"
fi

# 14. Extra safety cleanup
echo "🧨 Final cleanup of leftover files..."
run_or_skip find /etc -name '*k3s*' -type f -delete
run_or_skip find /var -name '*k3s*' -type d -exec rm -rf {} + 
run_or_skip find /run -name '*k3s*' -type d -exec rm -rf {} +

# 15. Final Notes
echo ""
echo "✅ === K3s Uninstallation Complete ==="
echo ""
echo "🔍 Verification steps:"
echo "  - ps aux | grep -i k3s"
echo "  - ls -la /usr/local/bin/ | grep -E '(k3s|kubectl)'"
echo "  - ip link show"
echo "  - mount | grep -i k3s"
echo "  - systemctl list-units | grep k3s"
echo "  - swapon --show"
echo ""
echo "💡 Recommended: sudo reboot"
