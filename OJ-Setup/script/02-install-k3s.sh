#!/bin/bash
# =============================================================================
# 02-install-k3s.sh  —  Install k3s on Ubuntu/WSL2
# =============================================================================
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

# ── Must run as root ──────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    log "ERROR" "🔒 Please run as root: $0"
fi

# ── Detect WSL ───────────────────────────────────────────────────────────────
is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

# ── Find powershell.exe ──────────────────────────────────────────────────────
find_powershell() {
    for p in \
        /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
        /mnt/c/Windows/SysNative/WindowsPowerShell/v1.0/powershell.exe \
        $(command -v powershell.exe 2>/dev/null || true)
    do
        [ -x "$p" ] && echo "$p" && return
    done
}

# =============================================================================
# 1. SYNC TIME
# =============================================================================
section "🕒 Time Sync"

if is_wsl; then
    log "INFO" "🖥️ WSL detected — syncing clock from Windows host..."
    PS=$(find_powershell)
    if [ -n "$PS" ]; then
        WIN_TIME=$("$PS" -Command 'Get-Date -Format "yyyy-MM-dd HH:mm:ss"' 2>/dev/null | tr -d '\r\n')
        if [ -n "$WIN_TIME" ]; then
            date -s "$WIN_TIME" >/dev/null
            log "SUCCESS" "✅ Clock set to: $(date)"
        else
            log "WARN" "⚠️ powershell.exe returned empty — clock: $(date)"
        fi
    else
        log "WARN" "⚠️ powershell.exe not found — clock: $(date)"
    fi
else
    log "INFO" "🌐 Non-WSL: using system NTP"
    timedatectl set-ntp true 2>/dev/null || true
fi

# =============================================================================
# 2. SWAP
# =============================================================================
section "🚫 Disabling Swap"
swapoff -a
sed -i '/ swap /d' /etc/fstab
log "SUCCESS" "✅ Swap disabled."

# =============================================================================
# 3. PACKAGES
# =============================================================================
section "📦 Checking Required Packages"

missing=""
command -v openssl  >/dev/null 2>&1 || missing+=" openssl"
command -v chronyc  >/dev/null 2>&1 || missing+=" chrony"

if [ -n "$missing" ]; then
    log "INFO" "📥 Installing:$missing"
    apt-get update -qq
    apt-get install -y $missing
else
    log "SUCCESS" "✅ All packages already installed."
fi

# =============================================================================
# 4. K3S CONFIG
# =============================================================================
section "⚙️ Configuring K3s"

mkdir -p /etc/rancher/k3s
tee /etc/rancher/k3s/registries.yaml >/dev/null <<'EOF'
mirrors:
  "docker.io":
    endpoint:
      - "https://mirror.gcr.io"
EOF
log "SUCCESS" "✅ Registry mirror configured."

# =============================================================================
# 5. DOWNLOAD BINARIES
# =============================================================================
section "📥 Downloading K3s Binaries"

DOWNLOAD_URL="https://storage.googleapis.com/ttm-infra-public/k3s"

log "INFO" "📥 Fetching k3s binary..."
wget -q $DOWNLOAD_URL/k3s-1326 -O /usr/local/bin/k3s
log "INFO" "📥 Fetching install scripts..."
wget -q $DOWNLOAD_URL/k3s-install.sh  -O /usr/local/bin/k3s-install.sh
wget -q $DOWNLOAD_URL/generate-custom-ca-certs.sh -O /usr/local/bin/generate-custom-ca-certs.sh
log "INFO" "📥 Fetching kubectl..."
wget -q $DOWNLOAD_URL/kubectl -O /usr/local/bin/kubectl_
chmod 755 /usr/local/bin/k3s /usr/local/bin/k3s-install.sh /usr/local/bin/generate-custom-ca-certs.sh /usr/local/bin/kubectl_
log "SUCCESS" "✅ Binaries downloaded and ready."

# =============================================================================
# 6. INSTALL K3S
# =============================================================================
section "🚀 Installing K3s"

export INSTALL_K3S_SKIP_START=true
export INSTALL_K3S_SKIP_DOWNLOAD="true"
export INSTALL_K3S_EXEC="--disable=traefik --cluster-cidr=10.96.0.0/16 --service-cidr=10.69.0.0/16"

log "INFO" "🏗️ Running k3s-install.sh..."
/usr/local/bin/k3s-install.sh &> /dev/null
log "SUCCESS" "✅ k3s installed."

if is_wsl; then
    log "INFO" "🔧 Applying shared mount fix for WSL (node-exporter support)..."
    mkdir -p /etc/systemd/system/k3s.service.d
    cat << 'EOF' > /etc/systemd/system/k3s.service.d/rshared.conf
[Service]
ExecStartPre=-/bin/mount --make-rshared /
EOF
    systemctl daemon-reload
    log "SUCCESS" "✅ Shared mount override applied."
fi

# =============================================================================
# 7. GENERATE CA CERTS
# =============================================================================
section "🔐 Generating 100yr CA Certificates"
/usr/local/bin/generate-custom-ca-certs.sh &>/dev/null
log "SUCCESS" "✅ CA certs generated."

# =============================================================================
# 8. ROTATE CERTIFICATES
# =============================================================================
section "🔄 Rotating Certificates"

systemctl restart k3s
sleep 3
systemctl stop chrony 2>/dev/null || true

for i in 1 2 3; do
    log "INFO" "🔄 Rotation pass $i/3..."
    date -s "+364 days" &>/dev/null
    k3s certificate rotate &>/dev/null
    systemctl restart k3s
    sleep 3
done

# Restore real time
log "INFO" "🕒 Restoring real time..."
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
log "SUCCESS" "✅ Clock restored: $(date)"

# =============================================================================
# 9. VERIFY K3S
# =============================================================================
section "🔍 K3s Status"
systemctl status k3s --no-pager | head -n 12 || true
echo ""
k3s certificate check --output table 2>/dev/null | grep -v "a long while" | head -n 8 || true

# =============================================================================
# 10. KUBECTL SETUP
# =============================================================================
section "⌨️  Setting up Kubectl"

rm -f /usr/local/bin/kubectl
cd /usr/local/bin
mv kubectl_ kubectl
ln -sf kubectl k

mkdir -p "$HOME/.kube"
k3s kubectl config view --raw \
    | sed "s/127\.0\.0\.1/$(hostname -I | awk '{print $1}')/g" \
    > "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
log "SUCCESS" "✅ kubeconfig written to ~/.kube/config"

# =============================================================================
# 11. WAIT FOR CORE COMPONENTS
# =============================================================================
section "⏳ Waiting for K3s Core Components"

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
# 12. RESTART DEPLOYMENTS
# =============================================================================
section "🔄 Restarting System Deployments"

k rollout restart deployment -n kube-system
sleep 2
kubectl wait -n kube-system pod -l k8s-app=kube-dns \
    --for=condition=ready --timeout=90s &>/dev/null && log "SUCCESS" "✅ CoreDNS ready." \
    || log "WARN" "⚠️ CoreDNS not ready within 90s — continuing anyway."

k get node -o wide
echo ""
k get pod -A
echo ""

# =============================================================================
# 13. PATCH COREDNS
# =============================================================================
section "🛠️ Patching CoreDNS NodeHosts"

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
' | kubectl apply -f - && log "SUCCESS" "✅ CoreDNS NodeHosts patched."

# Restart CoreDNS
kubectl rollout restart deployment coredns -n kube-system
kubectl wait -n kube-system pod -l k8s-app=kube-dns \
    --for=condition=ready --timeout=60s &>/dev/null \
    && log "SUCCESS" "✅ CoreDNS restarted and ready." \
    || log "WARN" "⚠️ CoreDNS not ready within 60s"

section "🏁 K3s Installation Complete"
log "INFO" "Current time : $(date)"
log "INFO" "Add to shell : source <(kubectl completion bash); complete -F __start_kubectl k"