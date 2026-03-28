#!/bin/bash
set -e

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

# Configuration variables
KUSTOMIZE_VERSION="latest"
CURL_VERSION="latest"
YQ_VERSION="latest"
ANYDESK_PASSWORD="${ANYDESK_PASSWORD:-mu,wvmu2023}"

TEMP_DIR=""
LOGFILE="/tmp/k8s_setup_$(TZ='Asia/Bangkok' date +%Y%m%d_%H%M%S).log"
TOTAL_STEPS=15
CURRENT_STEP=0
ARCH=""
CLEANUP_CALLED=false

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

show_progress() {
    ((CURRENT_STEP++))
    local desc=$1
    local title="STEP $CURRENT_STEP/$TOTAL_STEPS: $desc"
    local clean_title=$(echo -e "$title" | sed 's/\x1b\[[0-9;]*m//g')
    local title_len=${#clean_title}
    local width=55
    local pad_len=$((width - title_len))
    [ $pad_len -lt 0 ] && pad_len=0
    local padding=$(printf "%${pad_len}s" "")

    echo -e "\n${B_PURPLE}╭──────────────────────────────────────────────────────────╮${NC}" | tee -a "$LOGFILE"
    echo -e "${B_PURPLE}│${NC} ${B_WHITE}${title}${NC}${padding} ${B_PURPLE}│${NC}" | tee -a "$LOGFILE"
    echo -e "${B_PURPLE}╰──────────────────────────────────────────────────────────╯${NC}" | tee -a "$LOGFILE"
}

cleanup() {
    if [ "$CLEANUP_CALLED" = true ]; then
        return 0
    fi
    CLEANUP_CALLED=true
    
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        log "INFO" "🧹 Cleaning up temporary files..."
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
    
    rm -f /tmp/kustomize_*.tar.gz /tmp/kubeconform.tar.gz /tmp/curl-*.tar.gz /tmp/anydesk*.deb 2>/dev/null || true
}

error_handler() {
    local line_number=$1
    log "ERROR" "❌ An error occurred on line $line_number"
    log "ERROR" "📄 Check log file: $LOGFILE"
    cleanup
    exit 1
}

trap cleanup EXIT
trap 'error_handler $LINENO' ERR

check_root() {
    if [ "$EUID" -eq 0 ]; then
        log "ERROR" "❌ This script must not be run as root."
        log "INFO" "💡 Please run with a regular user with sudo privileges."
        exit 1
    fi
    
    if ! sudo -n true 2>/dev/null; then
        log "INFO" "🔐 Please enter your sudo password:"
        sudo -v
    fi
}

check_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64) export ARCH="amd64" ;;
        aarch64) export ARCH="arm64" ;;
        armv7l) export ARCH="arm" ;;
        *) 
            log "ERROR" "❌ Unsupported architecture: $arch"
            log "INFO" "💡 Supported architectures: x86_64, aarch64, armv7l"
            exit 1 
        ;;
    esac
    log "INFO" "✅ Architecture: $arch ($ARCH)"
}

check_network() {
    log "INFO" "📶 Checking internet connectivity..."
    
    local test_urls=(
        "https://github.com"
        "https://fluxcd.io"
        "https://get.helm.sh"
    )
    
    for url in "${test_urls[@]}"; do
        if ! curl -Is "$url" --connect-timeout 10 >/dev/null 2>&1; then
            log "ERROR" "❌ Could not connect to $url"
            exit 1
        fi
    done
    
    log "SUCCESS" "✅ Internet connection is stable."
}

check_dependencies() {
    log "INFO" "🔍 Checking basic dependencies..."
    
    local missing=()
    local required=("wget" "curl" "tar" "gzip" "make" "gcc" "jq")
    
    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        log "WARN" "⚠️ Missing dependencies: ${missing[*]}"
        log "INFO" "📦 Installing dependencies..."
        sudo apt update -qq
        sudo apt install -y "${missing[@]}"
    fi
    
    log "SUCCESS" "✅ Dependencies are ready."
}

is_installed() {
    command -v "$1" >/dev/null 2>&1
}

download_with_retry() {
    local url=$1
    local output=$2
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "INFO" "📥 Downloading (Attempt $attempt): $(basename "$url")"
        
        if wget -q --show-progress "$url" -O "$output"; then
            log "SUCCESS" "✅ Download successful: $(basename "$output")"
            return 0
        fi
        
        log "WARN" "⚠️ Download failed. Attempt $attempt"
        ((attempt++))
        
        if [ $attempt -le $max_attempts ]; then
            sleep 2
        fi
    done
    
    log "ERROR" "❌ Download failed after $max_attempts attempts"
    return 1
}

get_latest_version() {
    local repo=$1
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    
    if command -v jq >/dev/null 2>&1; then
        local version=$(curl -s "$api_url" | jq -r '.tag_name' 2>/dev/null)
    else
        local version=$(curl -s "$api_url" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' 2>/dev/null)
    fi
    
    if [ -n "$version" ] && [ "$version" != "null" ]; then
        echo "$version"
    else
        log "ERROR" "❌ Failed to get latest version for $repo"
        return 1
    fi
}

compare_versions() {
    local current=$1
    local latest=$2
    
    current=$(echo "$current" | sed 's/^v//')
    latest=$(echo "$latest" | sed 's/^v//')
    
    if [ "$current" = "$latest" ]; then
        return 0
    else
        return 1
    fi
}

update_system() {
    show_progress "🔄 Updating system..."
    
    log "INFO" "📦 Updating package lists..."
    sudo apt update -qq
    
    log "INFO" "⬆️ Upgrading packages..."
    sudo apt upgrade -y -qq
    
    log "INFO" "🧹 Cleaning up package cache..."
    sudo apt autoremove -y -qq
    sudo apt autoclean -qq
    
    log "SUCCESS" "✅ System update complete."
}

install_desktop() {
    show_progress "🖥️ Installing XFCE4 Desktop and XRDP..."
    
    if dpkg -l | grep -q "^ii.*xfce4.*"; then
        log "INFO" "✅ XFCE4 is already installed."
    else
        log "INFO" "📦 Installing XFCE4..."
        sudo apt install -y xfce4 xfce4-goodies -qq
    fi
    
    if dpkg -l | grep -q "^ii.*xrdp.*"; then
        log "INFO" "✅ XRDP is already installed."
    else
        log "INFO" "📦 Installing XRDP..."
        sudo apt install -y xrdp -qq
    fi
    
    log "INFO" "🔧 Configuring XRDP..."
    echo "startxfce4" > ~/.xsession
    sudo sed -i 's/^new_cursors=true/new_cursors=false/' /etc/xrdp/xrdp.ini 2>/dev/null || true
    
    sudo apt install -y xserver-xorg-core xserver-xorg-video-dummy -qq
    
    sudo systemctl enable xrdp
    sudo systemctl restart xrdp
    
    log "SUCCESS" "✅ XFCE4 and XRDP installation complete."
}

install_browser() {
    show_progress "🌐 Installing Google Chrome Browser (.deb Direct)..."
    
    if is_installed google-chrome; then
        log "INFO" "✅ Google Chrome is already installed."
        return 0
    fi

    if [ "$ARCH" != "amd64" ]; then
        log "WARN" "⚠️ Google Chrome .deb is only available for amd64 (x64). Your architecture is: $ARCH."
        log "INFO" "📦 Falling back to Firefox via apt..."
        sudo apt install -y firefox -qq
        return 0
    fi
    
    log "INFO" "📦 Downloading Google Chrome .deb (Approx 100MB)..."
    local chrome_deb="/tmp/google-chrome-stable_current_amd64.deb"
    
    if wget -q --show-progress "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" -O "$chrome_deb"; then
        log "INFO" "📦 Installing Google Chrome (Direct .deb - No Snap)..."
        # dpkg might fail dependencies, apt install -f fixes them
        sudo dpkg -i "$chrome_deb" 2>/dev/null || sudo apt install -f -y -qq
        
        if is_installed google-chrome; then
            log "SUCCESS" "✅ Google Chrome installation successful (Native .deb)."
            rm -f "$chrome_deb"
        else
            log "ERROR" "❌ Google Chrome installation failed."
        fi
    else
        log "ERROR" "❌ Failed to download Google Chrome .deb."
    fi
}

install_git() {
    show_progress "📦 Installing Git..."
    
    if is_installed git; then
        local version=$(git --version 2>/dev/null | awk '{print $3}' || echo "unknown")
        log "INFO" "✅ Git is already installed (Version: $version)"
    else
        log "INFO" "📦 Installing Git..."
        sudo apt install -y git git-lfs -qq
        
        if is_installed git; then
            local version=$(git --version 2>/dev/null | awk '{print $3}' || echo "unknown")
            log "SUCCESS" "✅ Git installation successful (Version: $version)"
        else
            log "ERROR" "❌ Git installation failed."
            return 1
        fi
    fi
    
    # Install additional useful Git tools
    log "INFO" "📦 Installing additional Git tools..."
    sudo apt install -y git-flow tig -qq
    
    log "SUCCESS" "✅ Git and additional tools installed successfully."
}

install_ssh() {
    show_progress "🔐 Installing SSH Client and Server..."
    
    # Install SSH client
    if is_installed ssh; then
        local version=$(ssh -V 2>&1 | head -n1 | awk '{print $1}' || echo "unknown")
        log "INFO" "✅ SSH client is already installed (Version: $version)"
    else
        log "INFO" "📦 Installing SSH client..."
        sudo apt install -y openssh-client -qq
    fi
    
    # Install SSH server
    if systemctl is-active --quiet ssh 2>/dev/null; then
        log "INFO" "✅ SSH server is already running."
    else
        log "INFO" "📦 Installing SSH server..."
        sudo apt install -y openssh-server -qq
        
        log "INFO" "🔧 Configuring SSH server..."
        # Enable SSH service
        sudo systemctl enable ssh
        sudo systemctl start ssh
        
        # Basic SSH hardening
        sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
        sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
        sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
        
        # Restart SSH service to apply changes
        sudo systemctl restart ssh
    fi
    
    # Create SSH directory for user if it doesn't exist
    if [ ! -d "$HOME/.ssh" ]; then
        log "INFO" "📁 Creating SSH directory..."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
    fi
    
    log "SUCCESS" "✅ SSH client and server installation complete."
}

install_fluxcd() {
    show_progress "📦 Installing FluxCD..."

    local REQUIRED_FLUX_VERSION="2.6.4"

    if is_installed flux; then
        local version=$(flux --version 2>/dev/null | awk '{print $3}' || echo "unknown")
        if [ "$version" = "$REQUIRED_FLUX_VERSION" ]; then
            log "INFO" "✅ FluxCD is already installed (Version: $version)"
            return 0
        else
            log "WARN" "⚠️ FluxCD version mismatch (installed: $version, required: $REQUIRED_FLUX_VERSION)"
            log "INFO" "🔄 Reinstalling FluxCD $REQUIRED_FLUX_VERSION..."
        fi
    fi

    log "INFO" "📥 Installing FluxCD v${REQUIRED_FLUX_VERSION}..."
    curl -s https://fluxcd.io/install.sh | sudo FLUX_VERSION="$REQUIRED_FLUX_VERSION" bash

    if is_installed flux; then
        local version=$(flux --version 2>/dev/null | awk '{print $3}' || echo "unknown")
        log "SUCCESS" "✅ FluxCD installation successful (Version: $version)"
    else
        log "ERROR" "❌ FluxCD installation failed."
        return 1
    fi
}

install_yq() {
    show_progress "🔧 Installing yq..."
    
    if is_installed yq; then
        local version=$(yq --version 2>/dev/null | awk '{print $4}' || echo "unknown")
        log "INFO" "✅ yq is already installed (Version: $version)"
        return 0
    fi
    
    log "INFO" "📥 Downloading yq..."
    local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}"
    
    if download_with_retry "$yq_url" "$TEMP_DIR/yq"; then
        sudo mv "$TEMP_DIR/yq" /usr/local/bin/yq
        sudo chmod +x /usr/local/bin/yq
        
        local version=$(yq --version 2>/dev/null | awk '{print $4}' || echo "unknown")
        log "SUCCESS" "✅ yq installation successful (Version: $version)"
    else
        log "ERROR" "❌ yq installation failed."
        return 1
    fi
}

install_kustomize() {
    show_progress "📦 Installing kustomize (latest)..."
    
    log "INFO" "🔍 Getting latest kustomize version..."
    local latest_version=$(get_latest_version "kubernetes-sigs/kustomize")
    
    if [ -z "$latest_version" ]; then
        log "ERROR" "❌ Failed to get latest kustomize version"
        return 1
    fi
    
    latest_version=$(echo "$latest_version" | sed 's|kustomize/||')
    
    if is_installed kustomize; then
        local current_version=$(kustomize version --short 2>/dev/null | sed -n 's/.*\(v[0-9.]*\).*/\1/p' | head -n1 || echo "unknown")
        log "INFO" "✅ kustomize is already installed (Version: $current_version)"
        
        if compare_versions "$current_version" "$latest_version"; then
            log "INFO" "✅ kustomize is up to date ($current_version)"
            return 0
        else
            log "INFO" "🔄 Updating kustomize from $current_version to $latest_version..."
        fi
    fi
    
    log "INFO" "📥 Downloading kustomize $latest_version..."
    local kustomize_url="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/${latest_version}/kustomize_${latest_version}_linux_${ARCH}.tar.gz"
    
    if download_with_retry "$kustomize_url" "$TEMP_DIR/kustomize.tar.gz"; then
        cd "$TEMP_DIR"
        tar -xzf kustomize.tar.gz
        chmod +x kustomize
        sudo mv kustomize /usr/local/bin/
        
        local version=$(kustomize version --short 2>/dev/null | sed -n 's/.*\(v[0-9.]*\).*/\1/p' | head -n1 || echo "unknown")
        log "SUCCESS" "✅ kustomize installation successful (Version: $version)"
    else
        log "ERROR" "❌ kustomize installation failed."
        return 1
    fi
}

install_helm() {
    show_progress "📦 Installing Helm..."
    
    if is_installed helm; then
        local version=$(helm version --short 2>/dev/null | awk '{print $1}' | sed 's/v//' || echo "unknown")
        log "INFO" "✅ Helm is already installed (Version: $version)"
        return 0
    fi
    
    log "INFO" "📥 Downloading and installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    if is_installed helm; then
        local version=$(helm version --short 2>/dev/null | awk '{print $1}' | sed 's/v//' || echo "unknown")
        log "SUCCESS" "✅ Helm installation successful (Version: $version)"
    else
        log "ERROR" "❌ Helm installation failed."
        return 1
    fi
}

install_curl() {
    show_progress "📦 Compiling and installing curl (latest)..."
    
    log "INFO" "🔍 Getting latest curl version..."
    local latest_version=$(get_latest_version "curl/curl")
    
    if [ -z "$latest_version" ]; then
        log "ERROR" "❌ Failed to get latest curl version"
        return 1
    fi
    
    local version_number=$(echo "$latest_version" | sed 's/curl-//' | tr '_' '.')
    
    if command -v /usr/local/bin/curl >/dev/null 2>&1; then
        local current_version=$(/usr/local/bin/curl --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "unknown")
        if compare_versions "$current_version" "$version_number"; then
            log "INFO" "✅ curl $version_number is already installed and up to date."
            return 0
        else
            log "INFO" "🔄 Updating curl from $current_version to $version_number..."
        fi
    fi
    
    log "INFO" "📥 Downloading curl source code ($latest_version)..."
    local download_version=$(echo "$version_number" | tr '.' '_')
    local curl_url="https://github.com/curl/curl/releases/download/curl-${download_version}/curl-${version_number}.tar.gz"
    
    if download_with_retry "$curl_url" "$TEMP_DIR/curl.tar.gz"; then
        cd "$TEMP_DIR"
        tar -xzf curl.tar.gz
        cd "curl-${version_number}"
        
        log "INFO" "📦 Installing build dependencies..."
        sudo apt install -y build-essential autoconf libtool pkg-config \
            libssl-dev libnghttp2-dev libbrotli-dev zlib1g-dev libidn2-0-dev \
            libpsl-dev libssh2-1-dev ca-certificates -qq
        
        log "INFO" "🔧 Configuring compilation..."
        ./configure --prefix=/usr/local --with-ssl --with-nghttp2 --with-brotli \
            --enable-optimize --disable-dependency-tracking >/dev/null
        
        log "INFO" "🔨 Compiling curl (this may take a while)..."
        make -j"$(nproc)" >/dev/null
        
        log "INFO" "📦 Installing curl..."
        sudo make install >/dev/null
        
        echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/curl.conf >/dev/null
        sudo ldconfig
        
        if /usr/local/bin/curl --version >/dev/null 2>&1; then
            local version=$(/usr/local/bin/curl --version | head -n1 | awk '{print $2}')
            log "SUCCESS" "✅ curl compiled and installed successfully (Version: $version)"
        else
            log "ERROR" "❌ curl installation failed."
            return 1
        fi
    else
        log "ERROR" "❌ Failed to download curl source."
        return 1
    fi
}

install_kubeconform() {
    show_progress "📦 Installing kubeconform..."
    
    if is_installed kubeconform; then
        local version=$(kubeconform -v 2>/dev/null | sed 's/^v//' || echo "unknown")
        log "INFO" "✅ kubeconform is already installed (Version: $version)"
        return 0
    fi
    
    log "INFO" "📥 Downloading kubeconform..."
    local kubeconform_url="https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-${ARCH}.tar.gz"
    
    if download_with_retry "$kubeconform_url" "$TEMP_DIR/kubeconform.tar.gz"; then
        cd "$TEMP_DIR"
        tar -xzf kubeconform.tar.gz
        chmod +x kubeconform
        sudo mv kubeconform /usr/local/bin/
        
        local version=$(kubeconform -v 2>/dev/null | sed 's/^v//' || echo "unknown")
        log "SUCCESS" "✅ kubeconform installation successful (Version: $version)"
    else
        log "ERROR" "❌ kubeconform installation failed."
        return 1
    fi
}

install_anydesk() {
    show_progress "🖥️ Installing AnyDesk..."

    # Find real username (not root)
    if [ -n "$SUDO_USER" ]; then
        USER_NAME="$SUDO_USER"
    else
        USER_NAME=$(logname 2>/dev/null || echo $USER)
    fi

    log "INFO" "Installing AnyDesk for user: $USER_NAME"

    # Create config directory for AnyDesk
    log "INFO" "📁 Creating config directory..."
    sudo mkdir -p /home/$USER_NAME/.anydesk
    echo "ad.unattended.access=true" | sudo tee /home/$USER_NAME/.anydesk/user.conf >/dev/null
    sudo chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.anydesk
    
    # Add sudo permission for user to use anydesk --get-id (because AnyDesk daemon runs as root)
    log "INFO" "🔐 Adding sudo permission for anydesk --get-id..."
    if ! sudo grep -q "^${USER_NAME}.*anydesk.*get-id" /etc/sudoers.d/anydesk 2>/dev/null; then
        echo "${USER_NAME} ALL=(ALL) NOPASSWD: /usr/bin/anydesk --get-id" | sudo tee /etc/sudoers.d/anydesk >/dev/null
        sudo chmod 440 /etc/sudoers.d/anydesk
        log "INFO" "✅ Sudo permission added"
    else
        log "INFO" "✅ Sudo permission already exists"
    fi

    # Update package list
    log "INFO" "📦 Update package list..."
    sudo apt update &>/dev/null

    # Install Desktop Environment (XFCE)
    log "INFO" "🖥️ Installing XFCE Desktop Environment..."
    DEBIAN_FRONTEND=noninteractive sudo apt install --no-install-recommends -y \
      xfce4 \
      lightdm lightdm-gtk-greeter \
      xorg dbus-x11 &>/dev/null

    # Set graphical target
    log "INFO" "⚙️ Setting graphical target..."
    sudo systemctl set-default graphical.target
    sudo systemctl start graphical.target 2>/dev/null || true

    # Check Display Manager and Desktop Environment
    log "INFO" "🔍 Checking Display Manager and Desktop Environment..."
    sudo systemctl status gdm3 &>/dev/null && log "INFO" "Found GDM3 (GNOME Display Manager)" || log "INFO" "GDM3 not found"
    sudo systemctl status lightdm &>/dev/null && log "INFO" "Found LightDM (XFCE Display Manager)" || log "INFO" "LightDM not found"
    log "INFO" ""
    log "INFO" "Installed Desktop Environment list:"
    dpkg -l | grep -E "ubuntu-desktop|xfce4|gnome-shell" || log "INFO" "No other Desktop Environment found"

    # Set LightDM as default
    log "INFO" ""
    log "INFO" "🎨 Setting LightDM as default..."

    # Stop and disable GDM3 (if exists)
    if sudo systemctl list-unit-files 2>/dev/null | grep -q gdm3.service; then
        log "INFO" "  └─ Disabling GDM3..."
        sudo systemctl stop gdm3 || true
        sudo systemctl disable gdm3 || true
    fi

    # Enable LightDM
    log "INFO" "  └─ Enabling LightDM..."
    sudo systemctl enable lightdm
    sudo systemctl start lightdm

    # Set LightDM as default in system
    log "INFO" "  └─ Setting LightDM as default..."
    echo "lightdm shared/default-x-display-manager select lightdm" | sudo debconf-set-selections
    sudo dpkg-reconfigure -f noninteractive lightdm

    # (Optional) Remove GNOME to save resources
    if dpkg -l | grep -q gnome-shell; then
        log "INFO" "  └─ Removing GNOME to save resources..."
        sudo apt remove --purge -y ubuntu-desktop gnome-shell gdm3 &>/dev/null || true
        sudo apt autoremove -y &>/dev/null
    fi

    # Restart LightDM
    log "INFO" "  └─ Restart LightDM..."
    sudo systemctl restart lightdm || true
    sleep 10

    # Check if AnyDesk is already installed
    log "INFO" ""
    log "INFO" "🔍 Checking AnyDesk installation..."
    if command -v anydesk >/dev/null 2>&1 || dpkg -l | grep -q "^ii.*anydesk"; then
        log "INFO" "✅ AnyDesk is already installed, skipping installation"
        
        # Wait for AnyDesk service to be ready before getting ID
        log "INFO" "⏳ Waiting for AnyDesk service to be ready..."
        sleep 5
        
        # Run anydesk --get-id with sudo (because AnyDesk daemon runs as root)
        ANYDESK_ID=$(sudo anydesk --get-id 2>/dev/null | head -n 1 | tr -d '[:space:]')

        # Check if ID is valid (not 0 or empty)
        if [ -z "$ANYDESK_ID" ] || [ "$ANYDESK_ID" = "0" ]; then
            log "INFO" "🖥️ Current AnyDesk ID: (not ready - will retry later)"
            ANYDESK_ID=""  # Reset for retry in next section
        else
            log "INFO" "🖥️ Current AnyDesk ID: $ANYDESK_ID"
        fi
        
        # Check if password needs to be set
        log "INFO" "🔐 Checking unattended access password..."
        # Set password again to ensure it's correct
        echo "$ANYDESK_PASSWORD" | sudo /usr/bin/anydesk --set-password 2>/dev/null || true
        log "INFO" "✅ Password has been set"
    else
        # Download and install AnyDesk
        log "INFO" "📦 AnyDesk not installed, installing now..."
        cd /tmp
        wget -q https://storage.googleapis.com/ttm-infra-public/anydesk/anydesk_7.1.1-1_amd64.deb

        sudo apt install -f -y &>/dev/null
        sudo dpkg -i anydesk_7.1.1-1_amd64.deb &>/dev/null || sudo apt install -f -y &>/dev/null

        # Set unattended access password
        log "INFO" "🔐 Setting unattended access password..."
        echo "$ANYDESK_PASSWORD" | sudo /usr/bin/anydesk --set-password
        ANYDESK_ID=$(sudo anydesk --get-id 2>/dev/null | head -n 1 | tr -d '[:space:]')
        
        # Check if ID is valid (not 0 or empty)
        if [ -z "$ANYDESK_ID" ] || [ "$ANYDESK_ID" = "0" ]; then
            ANYDESK_ID=""  # Reset for retry in next section
        fi
    fi

    # Configure systemd service to disable PulseAudio
    log "INFO" "🔧 Configuring systemd service..."
    if [ -f /etc/systemd/system/anydesk.service ]; then
        if ! grep -q "PULSE_SERVER" /etc/systemd/system/anydesk.service; then
            sudo sed -i '/^\[Service\]/a Environment="PULSE_SERVER=0"' /etc/systemd/system/anydesk.service
        fi
    fi

    # Reload and restart service
    log "INFO" "🔄 Restarting AnyDesk service..."
    sudo systemctl daemon-reload
    sudo systemctl enable anydesk.service
    sudo systemctl restart anydesk.service
    sleep 10

    # Wait for service to actually run
    log "INFO" "⏳ Waiting for AnyDesk service to be ready..."
    sleep 3

    # Check service status
    log "INFO" ""
    log "INFO" "📊 AnyDesk Service Status"
    sudo systemctl status anydesk.service --no-pager

    # Show AnyDesk ID (if not retrieved yet)
    log "INFO" ""
    log "INFO" "⏳ Retrieving AnyDesk ID..."
    if [ -z "$ANYDESK_ID" ] || [ "$ANYDESK_ID" = "0" ] || [ "$ANYDESK_ID" = "" ]; then
        # Wait for AnyDesk service to be ready (may need to connect to server first)
        max_attempts=10
        attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            sleep 2
            # Run anydesk --get-id with sudo (because AnyDesk daemon runs as root)
            ANYDESK_ID=$(sudo anydesk --get-id 2>/dev/null | head -n 1 | tr -d '[:space:]')
            
            # Check if we got a valid ID (not 0 or empty)
            if [ -n "$ANYDESK_ID" ] && [ "$ANYDESK_ID" != "0" ] && [ "$ANYDESK_ID" != "" ]; then
                log "INFO" "✅ Got AnyDesk ID: $ANYDESK_ID"
                break
            fi
            
            ((attempt++))
            log "INFO" "   Attempt $attempt/$max_attempts..."
        done
        
        # If still no ID, show warning
        if [ -z "$ANYDESK_ID" ] || [ "$ANYDESK_ID" = "0" ] || [ "$ANYDESK_ID" = "" ]; then
            log "WARN" "⚠️ Unable to retrieve AnyDesk ID immediately"
            log "INFO" "   AnyDesk may need some time to connect to server"
            log "INFO" "   Try running: anydesk --get-id"
            ANYDESK_ID="(Waiting for connection...)"
        fi
    fi

    # Remove installation file
    rm -f /tmp/anydesk_7.1.1-1_amd64.deb
}

test_installations() {
    show_progress "🧪 Testing installed tools..."
    
    local tools=(
        "git:Git"
        "ssh:SSH Client"
        "flux:FluxCD"
        "yq:yq"
        "kustomize:Kustomize"
        "helm:Helm"
        "kubeconform:Kubeconform"
    )
    
    local failed=()
    
    for tool_info in "${tools[@]}"; do
        local tool=$(echo "$tool_info" | cut -d: -f1)
        local name=$(echo "$tool_info" | cut -d: -f2)
        
        if is_installed "$tool"; then
            log "SUCCESS" "✅ $name: Operational"
        else
            log "ERROR" "❌ $name: Not operational"
            failed+=("$name")
        fi
    done
    
    if /usr/local/bin/curl --version >/dev/null 2>&1; then
        log "SUCCESS" "✅ curl: Operational"
    else
        log "ERROR" "❌ curl: Not operational"
        failed+=("curl")
    fi
    
    # Test SSH server
    if systemctl is-active --quiet ssh 2>/dev/null; then
        log "SUCCESS" "✅ SSH Server: Operational"
    else
        log "ERROR" "❌ SSH Server: Not operational"
        failed+=("SSH Server")
    fi
    
    # Test AnyDesk
    if systemctl is-active --quiet anydesk.service 2>/dev/null; then
        log "SUCCESS" "✅ AnyDesk Service: Operational"
    else
        log "WARN" "⚠️ AnyDesk Service: Not operational"
        failed+=("AnyDesk Service")
    fi
    
    if [ ${#failed[@]} -eq 0 ]; then
        log "SUCCESS" "✅ All tools are working correctly."
    else
        log "WARN" "⚠️  Tools with issues: ${failed[*]}"
    fi
}

show_summary() {
    show_progress "📋 Displaying summary information..."
    
    local ip_address=$(hostname -I | awk '{print $1}' || echo "unknown")
    
    echo
    echo "=========================================="
    echo -e "${GREEN}✅ Installation completed successfully!${NC}"
    echo "=========================================="
    echo
    echo -e "${BLUE}📋 Installed Tools:${NC}"
    echo "   🖥️ XFCE4 Desktop + XRDP"
    
    if is_installed git; then
        local git_version=$(git --version 2>/dev/null | awk '{print $3}' || echo 'Unknown')
        echo "   🌟 Git: $git_version"
    fi
    
    if is_installed ssh; then
        local ssh_version=$(ssh -V 2>&1 | head -n1 | awk '{print $1}' || echo 'Unknown')
        echo "   🔐 SSH: $ssh_version"
    fi
    
    if is_installed flux; then
        local flux_version=$(flux --version 2>/dev/null | head -n1 | sed -n 's/.*flux version \([^ ]*\).*/\1/p' || echo 'Unknown')
        echo "   📦 FluxCD: $flux_version"
    fi
    
    if is_installed helm; then
        local helm_version=$(helm version --short 2>/dev/null | cut -d'+' -f1 || echo 'Unknown')
        echo "   📦 Helm: $helm_version"
    fi

    if is_installed kustomize; then
        local kustomize_version=$(kustomize version --short 2>/dev/null | sed -n 's/.*\(v[0-9.]*\).*/\1/p' | head -n1 || echo 'Unknown')
        echo "   📦 Kustomize: $kustomize_version"
    fi
    
    if is_installed yq; then
        local yq_version=$(yq --version 2>/dev/null | awk '{print $NF}' || echo 'Unknown')
        echo "   🔧 yq: $yq_version"
    fi
    
    if is_installed kubeconform; then
        local kubeconform_version=$(kubeconform -v 2>&1 | awk '{print $NF}' || echo 'Unknown')
        echo "   📦 Kubeconform: $kubeconform_version"
    fi
    
    if /usr/local/bin/curl --version >/dev/null 2>&1; then
        local curl_version=$(/usr/local/bin/curl --version 2>/dev/null | head -n1 | awk '{print $2}')
        echo "   📡 curl: $curl_version"
    fi
    
    # Check AnyDesk
    if command -v anydesk >/dev/null 2>&1 || dpkg -l | grep -q "^ii.*anydesk"; then
        local anydesk_version=$(dpkg -l | grep "^ii.*anydesk" | awk '{print $3}' | head -n1 2>/dev/null)
        if [ -z "$anydesk_version" ] || [ "$anydesk_version" = "Unknown" ]; then
            anydesk_version="7.1.1"
        fi
        echo "   🖥️ AnyDesk: $anydesk_version"
    fi
    
    echo
    echo -e "${BLUE}🔗 Connectivity:${NC}"
    echo "   Remote Desktop: rdp://${ip_address}:3389"
    echo "   SSH: ssh $(whoami)@${ip_address}"
    
    # AnyDesk Access
    if systemctl is-active --quiet anydesk.service 2>/dev/null; then
        echo
        echo -e "${BLUE}🔐 AnyDesk Remote Access:${NC}"
        
        # Get USER_NAME for anydesk --get-id
        local anydesk_user_name=""
        if [ -n "$SUDO_USER" ]; then
            anydesk_user_name="$SUDO_USER"
        else
            anydesk_user_name=$(logname 2>/dev/null || echo $USER)
        fi
        
        # Use global ANYDESK_ID from install_anydesk() if available
        # If not available or empty, try to get it one more time
        if [ -z "$ANYDESK_ID" ] || [ "$ANYDESK_ID" = "0" ] || [ "$ANYDESK_ID" = "" ]; then
            echo -e "     ${BLUE}⏳ Retrieving AnyDesk ID...${NC}"
            
            local max_attempts=10
            local attempt=0
            
            # Disable set -e for this section to prevent premature exit
            set +e
            while [ $attempt -lt $max_attempts ]; do
                sleep 2
                # Run anydesk --get-id with sudo (because AnyDesk daemon runs as root)
                ANYDESK_ID=$(sudo anydesk --get-id 2>/dev/null | head -n 1 | tr -d '[:space:]')
                
                # Check if we got a valid ID (not empty, not 0)
                if [ -n "$ANYDESK_ID" ] && [ "$ANYDESK_ID" != "0" ] && [ "$ANYDESK_ID" != "" ]; then
                    echo -e "     ${GREEN}✅ Got AnyDesk ID: $ANYDESK_ID${NC}"
                    break
                fi
                
                ((attempt++))
                echo -e "     ${BLUE}   Attempt $attempt/$max_attempts...${NC}"
            done
            set -e
            
            # If still no valid ID, set to message
            if [ -z "$ANYDESK_ID" ] || [ "$ANYDESK_ID" = "0" ] || [ "$ANYDESK_ID" = "" ]; then
                ANYDESK_ID="(Waiting for connection...)"
                echo -e "     ${YELLOW}⚠️ AnyDesk not ready yet${NC}"
                echo -e "     ${BLUE}💡 AnyDesk may need some time to connect to server${NC}"
                echo -e "     ${BLUE}💡 Try running: sudo anydesk --get-id${NC}"
            fi
        fi
        
        # Always show ID and Password
        echo -e "     ${BLUE}ID:${NC}       ${BLUE}$ANYDESK_ID${NC}"
        echo -e "     ${BLUE}Password:${NC} ${BLUE}$ANYDESK_PASSWORD${NC}"
    fi

    echo
    echo -e "${BLUE}📄 Log file:${NC} $LOGFILE"
    echo
    echo -e "${GREEN}🎉 Your Kubernetes development environment is ready!${NC}"
    echo
}

main() {
    echo "======================================================="
    echo -e "${PURPLE}🚀 TOTHEMARS - Kubernetes Environment Setup Script${NC}"
    echo -e "${CYAN}📅 $(TZ='Asia/Bangkok' date '+%H:%M:%S %d-%m-%Y')${NC}"
    echo "======================================================="
    echo
    
    TEMP_DIR=$(mktemp -d)
    log "INFO" "📁 Temporary directory: $TEMP_DIR"
    log "INFO" "📄 Log file: $LOGFILE"
    echo
    
    log "INFO" "🔍 Starting system checks..."
    
    check_root || { log "ERROR" "❌ Root check failed"; exit 1; }
    check_architecture || { log "ERROR" "❌ Architecture check failed"; exit 1; }
    check_network || { log "ERROR" "❌ Network check failed"; exit 1; }
    check_dependencies || { log "ERROR" "❌ Dependency check failed"; exit 1; }
    
    echo
    log "INFO" "🎯 Starting installation process..."
    echo
    
    update_system || { log "ERROR" "❌ System update failed"; exit 1; }
    install_desktop || { log "ERROR" "❌ Desktop installation failed"; exit 1; }
    install_browser || { log "ERROR" "❌ Browser installation failed"; exit 1; }
    install_git || { log "ERROR" "❌ Git installation failed"; exit 1; }
    install_ssh || { log "ERROR" "❌ SSH installation failed"; exit 1; }
    install_fluxcd || { log "ERROR" "❌ FluxCD installation failed"; exit 1; }
    install_yq || { log "ERROR" "❌ yq installation failed"; exit 1; }
    install_kustomize || { log "ERROR" "❌ kustomize installation failed"; exit 1; }
    install_helm || { log "ERROR" "❌ Helm installation failed"; exit 1; }
    install_curl || { log "ERROR" "❌ curl installation failed"; exit 1; }
    install_kubeconform || { log "ERROR" "❌ kubeconform installation failed"; exit 1; }
    install_anydesk || { log "ERROR" "❌ AnyDesk installation failed"; exit 1; }
    test_installations || { log "WARN" "⚠️  Testing encountered issues"; }
    show_summary
    
    log "SUCCESS" "🎉 Installation completed successfully!"
}

main "$@"
