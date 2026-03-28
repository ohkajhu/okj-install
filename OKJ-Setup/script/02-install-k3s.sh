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

section "🚀 starting k3s installation"

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

section "🏁" "k3s installation complete"
k get node -o wide
log "INFO" "Add to shell : source <(kubectl completion bash) ;complete -F __start_kubectl k"