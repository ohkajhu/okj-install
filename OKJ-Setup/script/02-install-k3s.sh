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

section "🚀 Starting K3s Installation (Server)"

log "INFO" "🚫 Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap /d' /etc/fstab
log "SUCCESS" "✅ Swap disabled."

# Check for missing packages
missing=""
! command -v openssl >/dev/null 2>&1 && missing+=" openssl"
! command -v chronyc >/dev/null 2>&1 && missing+=" chrony"

if [ -n "$missing" ]; then
    log "INFO" "📥 Installing missing packages:$missing"
    sudo apt-get update -qq && sudo apt-get install -y $missing -qq
else
    log "SUCCESS" "✅ All required packages are already installed."
fi

# Create K3s config
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml >/dev/null <<EOF
mirrors:
  "docker.io":
    endpoint:
      - "https://mirror.gcr.io"
EOF
log "SUCCESS" "✅ Registry mirror configured."

# Download
DOWNLOAD_URL="https://storage.googleapis.com/ttm-infra-public/k3s"
log "INFO" "📥 Downloading K3s binaries..."
wget -q $DOWNLOAD_URL/k3s-1326 -O /usr/local/bin/k3s
wget -q $DOWNLOAD_URL/k3s-install.sh  -O /usr/local/bin/k3s-install.sh
wget -q $DOWNLOAD_URL/generate-custom-ca-certs.sh -O /usr/local/bin/generate-custom-ca-certs.sh
wget -q $DOWNLOAD_URL/kubectl -O /usr/local/bin/kubectl_
chmod 755 /usr/local/bin/k3s /usr/local/bin/k3s-install.sh /usr/local/bin/generate-custom-ca-certs.sh /usr/local/bin/kubectl_
log "SUCCESS" "✅ Download complete."

# Install
export INSTALL_K3S_SKIP_START=true
export INSTALL_K3S_SKIP_DOWNLOAD="true"
export INSTALL_K3S_EXEC="--disable=traefik --cluster-cidr=10.96.0.0/16 --service-cidr=10.69.0.0/16"
log "INFO" "🏗️ Installing K3s Cluster..."
/usr/local/bin/k3s-install.sh &> /dev/null

log "INFO" "🔐 Generating 100 years CA certificate..."
/usr/local/bin/generate-custom-ca-certs.sh &>/dev/null

# Certificate Rotation
log "INFO" "🔄 Rotating certificates..."
systemctl restart k3s
sleep 3
systemctl stop chrony || true

for i in $(seq 1 3); do
    log "INFO" "🔄 Rotation pass $i/3..."
    date -s "+364 days" &>/dev/null
    k3s certificate rotate &>/dev/null
    systemctl restart k3s
    sleep 3
done

log "INFO" "🕒 Restoring clock..."
systemctl restart chrony || true
if command -v chronyc >/dev/null 2>&1; then
    chronyc -a makestep || true
fi
systemctl restart k3s
log "SUCCESS" "✅ Clock restored: $(date)"

# Kubectl setup
log "INFO" "⌨️ Setting up kubectl..."
rm -f /usr/local/bin/kubectl
cd /usr/local/bin
mv kubectl_ kubectl
ln -sf kubectl k
mkdir -p "$HOME/.kube"
k3s kubectl config view --raw | sed "s/127\.0\.0\.1/$(hostname -I | awk '{print $1}')/g" > "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"

# Wait
log "INFO" "⏳ Waiting for K3s components..."
while true; do
    count=$(crictl ps 2>/dev/null | grep -c Running || true)
    if [ "$count" -ge 3 ]; then
        break
    fi
    echo -n "."
    sleep 5
done
echo " ready."

# Rollout
log "INFO" "🔄 Restarting system deployments..."
k rollout restart deployment -n kube-system
sleep 1
kubectl wait -n kube-system pod -l k8s-app=kube-dns --for=condition=ready --timeout=90s &> /dev/null || true

# Patch CoreDNS
log "INFO" "🛠️ Patching CoreDNS NodeHosts..."
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
' | kubectl apply -f - && log "SUCCESS" "✅ CoreDNS NodeHosts patched."

section "🏁 K3s Installation Complete"
k get node -o wide
log "INFO" "Add to shell : source <(kubectl completion bash) ;complete -F __start_kubectl k"