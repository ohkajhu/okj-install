#!/bin/bash
# =============================================================================
# 02-install-k3s.sh  —  Install k3s on Ubuntu/WSL2
# =============================================================================
set -euo pipefail

# ── Must run as root ──────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: $0"
    exit 1
fi

# ── Helpers ──────────────────────────────────────────────────────────────────
info()    { echo -e "\e[32m[INFO]\e[0m  $*"; }
warn()    { echo -e "\e[33m[WARN]\e[0m  $*"; }
error()   { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }
section() { echo -e "\n\e[1;34m══ $* ══\e[0m"; }

# ── Detect WSL ───────────────────────────────────────────────────────────────
is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

# ── Find powershell.exe (not available in PATH by default) ───────────────
find_powershell() {
    # Common locations when running under in WSL
    for p in \
        /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
        /mnt/c/Windows/SysNative/WindowsPowerShell/v1.0/powershell.exe \
        $(command -v powershell.exe 2>/dev/null || true)
    do
        [ -x "$p" ] && echo "$p" && return
    done
}

# =============================================================================
# 1. SYNC TIME  (critical — k3s cert validation fails if clock is wrong)
# =============================================================================
section "Time sync"

if is_wsl; then
    info "WSL detected — syncing clock from Windows host..."
    PS=$(find_powershell)
    if [ -n "$PS" ]; then
        WIN_TIME=$("$PS" -Command 'Get-Date -Format "yyyy-MM-dd HH:mm:ss"' 2>/dev/null | tr -d '\r\n')
        if [ -n "$WIN_TIME" ]; then
            date -s "$WIN_TIME" >/dev/null
            info "Clock set to: $(date)"
        else
            warn "powershell.exe returned empty — clock: $(date)"
        fi
    else
        warn "powershell.exe not found — clock: $(date)"
    fi
else
    info "Non-WSL: using system NTP"
    timedatectl set-ntp true 2>/dev/null || true
fi

# =============================================================================
# 2. SWAP
# =============================================================================
section "Disabling swap"
swapoff -a
sed -i '/ swap /d' /etc/fstab
info "Swap disabled."

# =============================================================================
# 3. PACKAGES
# =============================================================================
section "Checking required packages"

missing=""
command -v openssl  >/dev/null 2>&1 || missing+=" openssl"
command -v chronyc  >/dev/null 2>&1 || missing+=" chrony"

if [ -n "$missing" ]; then
    info "Installing:$missing"
    apt-get update -qq
    apt-get install -y $missing
else
    info "All packages already installed."
fi

# =============================================================================
# 4. K3S CONFIG
# =============================================================================
section "Configuring k3s"

mkdir -p /etc/rancher/k3s
tee /etc/rancher/k3s/registries.yaml >/dev/null <<'EOF'
mirrors:
  "docker.io":
    endpoint:
      - "https://mirror.gcr.io"
EOF
info "Registry mirror configured."

# =============================================================================
# 5. DOWNLOAD BINARIES
# =============================================================================
section "Downloading k3s binaries"

DOWNLOAD_URL="https://storage.googleapis.com/ttm-infra-public/k3s"

wget -q $DOWNLOAD_URL/k3s-1326 -O /usr/local/bin/k3s
# source: https://github.com/k3s-io/k3s/blob/master/install.sh
wget -q $DOWNLOAD_URL/k3s-install.sh  -O /usr/local/bin/k3s-install.sh
wget -q $DOWNLOAD_URL/generate-custom-ca-certs.sh -O /usr/local/bin/generate-custom-ca-certs.sh
wget -q $DOWNLOAD_URL/kubectl -O /usr/local/bin/kubectl_
chmod 755 /usr/local/bin/k3s /usr/local/bin/k3s-install.sh /usr/local/bin/generate-custom-ca-certs.sh /usr/local/bin/kubectl_

# =============================================================================
# 6. INSTALL K3S
# =============================================================================
section "Installing k3s"

export INSTALL_K3S_SKIP_START=true
export INSTALL_K3S_SKIP_DOWNLOAD="true"
export INSTALL_K3S_EXEC="--disable=traefik --cluster-cidr=10.96.0.0/16 --service-cidr=10.69.0.0/16"

/usr/local/bin/k3s-install.sh &> /dev/null
info "k3s installed."

# =============================================================================
# 7. GENERATE CA CERTS (100-year validity)
# =============================================================================
section "Generating CA certificates (100yr)"
/usr/local/bin/generate-custom-ca-certs.sh &>/dev/null
info "CA certs generated."

# =============================================================================
# 8. ROTATE CERTIFICATES  (advance date trick — WSL-safe)
# =============================================================================
section "Rotating certificates"

systemctl restart k3s
sleep 3
systemctl stop chrony 2>/dev/null || true

for i in 1 2 3; do
    info "Rotation pass $i/3..."
    date -s "+364 days" &>/dev/null
    k3s certificate rotate &>/dev/null
    systemctl restart k3s
    sleep 3
done

# Restore real time
if is_wsl; then
    PS=$(find_powershell)
    if [ -n "$PS" ]; then
        WIN_TIME=$("$PS" -Command 'Get-Date -Format "yyyy-MM-dd HH:mm:ss"' 2>/dev/null | tr -d '\r\n')
        [ -n "$WIN_TIME" ] && date -s "$WIN_TIME" >/dev/null
    fi
else
    ntpdate -u time.google.com &>/dev/null || true
fi

systemctl start chrony 2>/dev/null || true
systemctl restart k3s
info "Clock restored: $(date)"

# =============================================================================
# 9. VERIFY K3S
# =============================================================================
section "k3s status"
systemctl status k3s --no-pager | head -12
k3s certificate check --output table 2>/dev/null | grep -v "a long while" | head -8

# =============================================================================
# 10. KUBECTL SETUP
# =============================================================================
section "Setting up kubectl"

rm -f /usr/local/bin/kubectl
cd /usr/local/bin
mv kubectl_ kubectl
ln -sf kubectl k

mkdir -p "$HOME/.kube"
k3s kubectl config view --raw \
    | sed "s/127\.0\.0\.1/$(hostname -I | awk '{print $1}')/g" \
    > "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
info "kubeconfig written to ~/.kube/config"

# =============================================================================
# 11. WAIT FOR CORE COMPONENTS
# =============================================================================
section "Waiting for k3s core components"

echo -n "  Waiting"
while true; do
    count=$(crictl ps 2>/dev/null | grep -c Running || true)
    count=${count:-0}
    if [ "$count" -ge 3 ]; then
        break
    fi
    echo -n "."
    sleep 5
done
echo " ready."

# =============================================================================
# 12. RESTART DEPLOYMENTS & WAIT FOR DNS
# =============================================================================
section "Restarting system deployments"

k rollout restart deployment -n kube-system
sleep 2
kubectl wait -n kube-system pod -l k8s-app=kube-dns \
    --for=condition=ready --timeout=90s &>/dev/null && info "CoreDNS ready." \
    || warn "CoreDNS not ready within 90s — continuing anyway."

k get node -o wide
echo ""
k get pod -A
echo ""

# =============================================================================
# 13. PATCH COREDNS NodeHosts
# =============================================================================
section "Patching CoreDNS NodeHosts"

REGISTRY_IP="125.254.54.194"

kubectl get configmap coredns -n kube-system -o json | \
jq --arg ip "$REGISTRY_IP" '
  .data.NodeHosts |= (
    split("\n")
    | map(select(length > 0))
    | map(select(
        (test("registry\\.ohkajhu\\.com")    | not) and
        (test("shop-gateway\\.ohkajhu\\.com") | not)
      ))
    + [
        "\($ip) registry.ohkajhu.com",
        "\($ip) shop-gateway.ohkajhu.com"
      ]
    | join("\n")
  )
' | kubectl apply -f - && info "CoreDNS NodeHosts patched."

# Restart CoreDNS to pick up new NodeHosts
kubectl rollout restart deployment coredns -n kube-system
kubectl wait -n kube-system pod -l k8s-app=kube-dns \
    --for=condition=ready --timeout=60s &>/dev/null \
    && info "CoreDNS restarted and ready." \
    || warn "CoreDNS not ready within 60s"

# Verify
info "CoreDNS NodeHosts:"
kubectl get configmap coredns -n kube-system -o jsonpath='{.data.NodeHosts}'
echo ""

# =============================================================================
# DONE
# =============================================================================
section "Complete"
echo ""
info "Current time : $(date)"
info "Add to shell : source <(kubectl completion bash); complete -F __start_kubectl k"
echo ""