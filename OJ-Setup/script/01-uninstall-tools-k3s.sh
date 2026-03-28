#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

LOGFILE="/tmp/k8s_uninstall_$(TZ='Asia/Bangkok' date +%Y%m%d_%H%M%S).log"
TOTAL_STEPS=11
CURRENT_STEP=0

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(TZ='Asia/Bangkok' date '+%H:%M:%S %d-%m-%Y')
    
    case $level in
        "INFO")    echo -e "  ${B_BLUE}ℹ [INFO]${NC}    $message" | tee -a "$LOGFILE" ;;
        "WARN")    echo -e "  ${B_YELLOW}⚠ [WARN]${NC}    $message" | tee -a "$LOGFILE" ;;
        "ERROR")   echo -e "
${BG_RED} ❌ ERROR ${NC} $message
" | tee -a "$LOGFILE" ;;
        "SUCCESS") echo -e "     ${B_GREEN}╰─ ✔${NC} $message" | tee -a "$LOGFILE" ;;
        "STEP")    echo -e "${B_CYAN} ➜ ${NC} ${B_WHITE}$message${NC}" | tee -a "$LOGFILE" ;;
    esac
}

show_progress() {
    ((CURRENT_STEP++))
    local desc=$1
    echo -e "
${BG_PURPLE} ✦ STEP $CURRENT_STEP/$TOTAL_STEPS ${NC} ${B_PURPLE}───────────────────────────────────────────────────${NC}" | tee -a "$LOGFILE"
    echo -e "${B_CYAN} ➜ ${NC} ${B_WHITE}$desc${NC}" | tee -a "$LOGFILE"
}

error_handler() {
    local line_number=$1
    log "ERROR" "❌ An error occurred on line $line_number"
    log "ERROR" "📄 Check log file: $LOGFILE"
    exit 1
}

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

confirm_uninstall() {
    echo -e "${YELLOW}⚠️ WARNING: This will remove the following components:${NC}"
    echo "   • XFCE4 Desktop Environment"
    echo "   • XRDP Remote Desktop"
    echo "   • FluxCD"
    echo "   • yq"
    echo "   • Kustomize"
    echo "   • Helm"
    echo "   • Custom compiled curl"
    echo "   • Kubeconform"
    echo "   • AnyDesk"
    echo "   • Build dependencies"
    echo
    echo -e "${BLUE}ℹ️ Note: The following will be preserved:${NC}"
    echo "   • Git (may be used by other applications)"
    echo "   • SSH (system essential service)"
    echo
    
    read -p "Are you sure you want to proceed? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "👋 Uninstall cancelled by user."
        exit 0
    fi
}

is_installed() {
    command -v "$1" >/dev/null 2>&1
}

service_exists() {
    systemctl list-unit-files --type=service | grep -q "^$1.service"
}

remove_desktop() {
    show_progress "🗑️ Removing XFCE4 Desktop and XRDP..."
    
    # Stop and disable XRDP service
    if service_exists "xrdp"; then
        log "INFO" "🛑 Stopping XRDP service..."
        sudo systemctl stop xrdp 2>/dev/null || true
        sudo systemctl disable xrdp 2>/dev/null || true
    fi
    
    # Remove XRDP packages
    if dpkg -l | grep -q "^ii.*xrdp.*"; then
        log "INFO" "📦 Removing XRDP packages..."
        sudo apt remove --purge -y xrdp xorgxrdp 2>/dev/null || true
    fi
    
    # Remove XFCE4 packages
    if dpkg -l | grep -q "^ii.*xfce4.*"; then
        log "INFO" "📦 Removing XFCE4 packages..."
        sudo apt remove --purge -y xfce4 xfce4-goodies 2>/dev/null || true
        sudo apt remove --purge -y xfce4-* 2>/dev/null || true
    fi
    
    # Remove X11 server packages that were specifically installed
    log "INFO" "📦 Removing X server packages..."
    sudo apt remove --purge -y xserver-xorg-core xserver-xorg-video-dummy 2>/dev/null || true
    
    # Remove user session files
    log "INFO" "🧹 Cleaning up user session files..."
    rm -f ~/.xsession 2>/dev/null || true
    rm -rf ~/.config/xfce4 2>/dev/null || true
    rm -rf ~/.cache/sessions 2>/dev/null || true
    
    log "SUCCESS" "✅ XFCE4 and XRDP removal complete."
}

remove_fluxcd() {
    show_progress "🗑️  Removing FluxCD..."
    
    if is_installed flux; then
        log "INFO" "📦 Removing FluxCD binary..."
        sudo rm -f /usr/local/bin/flux
        
        # Remove from alternative locations
        sudo rm -f /usr/bin/flux
        
        log "SUCCESS" "✅ FluxCD removed successfully."
    else
        log "INFO" "ℹ️  FluxCD is not installed."
    fi
}

remove_yq() {
    show_progress "🗑️  Removing yq..."
    
    if is_installed yq; then
        log "INFO" "📦 Removing yq binary..."
        sudo rm -f /usr/local/bin/yq
        sudo rm -f /usr/bin/yq
        
        log "SUCCESS" "✅ yq removed successfully."
    else
        log "INFO" "ℹ️  yq is not installed."
    fi
}

remove_kustomize() {
    show_progress "🗑️  Removing Kustomize..."
    
    if is_installed kustomize; then
        log "INFO" "📦 Removing Kustomize binary..."
        sudo rm -f /usr/local/bin/kustomize
        sudo rm -f /usr/bin/kustomize
        
        log "SUCCESS" "✅ Kustomize removed successfully."
    else
        log "INFO" "ℹ️  Kustomize is not installed."
    fi
}

remove_helm() {
    show_progress "🗑️  Removing Helm..."
    
    if is_installed helm; then
        log "INFO" "📦 Removing Helm binary and data..."
        sudo rm -f /usr/local/bin/helm
        sudo rm -f /usr/bin/helm
        
        # Remove Helm data directories
        rm -rf ~/.helm 2>/dev/null || true
        rm -rf ~/.config/helm 2>/dev/null || true
        rm -rf ~/.cache/helm 2>/dev/null || true
        
        log "SUCCESS" "✅ Helm removed successfully."
    else
        log "INFO" "ℹ️  Helm is not installed."
    fi
}

remove_curl() {
    show_progress "🗑️  Removing custom compiled curl..."
    
    if [ -f "/usr/local/bin/curl" ]; then
        log "INFO" "📦 Removing custom curl installation..."
        sudo rm -f /usr/local/bin/curl
        sudo rm -f /usr/local/lib/libcurl*
        sudo rm -rf /usr/local/include/curl
        sudo rm -f /usr/local/lib/pkgconfig/libcurl.pc
        sudo rm -f /usr/local/share/man/man1/curl.1
        sudo rm -f /usr/local/share/man/man3/libcurl*
        
        # Remove curl library configuration
        sudo rm -f /etc/ld.so.conf.d/curl.conf
        sudo ldconfig
        
        log "SUCCESS" "✅ Custom curl removed successfully."
    else
        log "INFO" "ℹ️  Custom curl is not installed."
    fi
}

remove_kubeconform() {
    show_progress "🗑️  Removing Kubeconform..."
    
    if is_installed kubeconform; then
        log "INFO" "📦 Removing Kubeconform binary..."
        sudo rm -f /usr/local/bin/kubeconform
        sudo rm -f /usr/bin/kubeconform
        
        log "SUCCESS" "✅ Kubeconform removed successfully."
    else
        log "INFO" "ℹ️  Kubeconform is not installed."
    fi
}

remove_anydesk() {
    show_progress "🗑️  Removing AnyDesk..."
    
    # Find real username (not root)
    if [ -n "$SUDO_USER" ]; then
        USER_NAME="$SUDO_USER"
    else
        USER_NAME=$(logname 2>/dev/null || echo $USER)
    fi
    
    # Stop and disable AnyDesk service
    if service_exists "anydesk"; then
        log "INFO" "🛑 Stopping AnyDesk service..."
        sudo systemctl stop anydesk.service 2>/dev/null || true
        sudo systemctl disable anydesk.service 2>/dev/null || true
    fi
    
    # Remove AnyDesk package
    if dpkg -l | grep -q "^ii.*anydesk.*"; then
        log "INFO" "📦 Removing AnyDesk package..."
        sudo apt remove --purge -y anydesk 2>/dev/null || true
    fi
    
    # Remove AnyDesk configuration files
    if [ -f /etc/sudoers.d/anydesk ]; then
        log "INFO" "🗑️  Removing AnyDesk sudoers file..."
        sudo rm -f /etc/sudoers.d/anydesk
    fi
    
    # Remove AnyDesk systemd service override
    if [ -f /etc/systemd/system/anydesk.service ]; then
        log "INFO" "🗑️  Removing AnyDesk systemd service override..."
        sudo rm -f /etc/systemd/system/anydesk.service
    fi
    
    # Remove AnyDesk user configuration
    if [ -d "/home/$USER_NAME/.anydesk" ]; then
        log "INFO" "🗑️  Removing AnyDesk user configuration..."
        sudo rm -rf "/home/$USER_NAME/.anydesk" 2>/dev/null || true
    fi
    
    # Remove AnyDesk binary if still exists
    if [ -f /usr/bin/anydesk ]; then
        log "INFO" "🗑️  Removing AnyDesk binary..."
        sudo rm -f /usr/bin/anydesk
    fi
    
    # Reload systemd daemon
    sudo systemctl daemon-reload 2>/dev/null || true
    
    log "SUCCESS" "✅ AnyDesk removed successfully."
}

remove_build_dependencies() {
    show_progress "🗑️  Removing build dependencies..."
    
    log "INFO" "📦 Removing build tools and development libraries..."
    
    # Remove build dependencies that were installed for curl compilation
    local build_deps=(
        "build-essential"
        "autoconf"
        "libtool"
        "pkg-config"
        "libssl-dev"
        "libnghttp2-dev"
        "libbrotli-dev"
        "zlib1g-dev"
        "libidn2-0-dev"
        "libpsl-dev"
        "libssh2-1-dev"
    )
    
    log "WARN" "⚠️ Note: This will only remove build dependencies, not system essentials."
    log "INFO" "📦 Removing development packages..."
    
    for dep in "${build_deps[@]}"; do
        if dpkg -l | grep -q "^ii.*$dep.*"; then
            sudo apt remove --purge -y "$dep" 2>/dev/null || true
        fi
    done
    
    log "SUCCESS" "✅ Build dependencies removal complete."
}

cleanup_system() {
    show_progress "🧹 Cleaning up system..."
    
    log "INFO" "📦 Running system cleanup..."
    sudo apt autoremove -y -qq 2>/dev/null || true
    sudo apt autoclean -qq 2>/dev/null || true
    
    # Remove temporary files
    log "INFO" "🗑️  Removing temporary files..."
    rm -f /tmp/kustomize_*.tar.gz /tmp/kubeconform.tar.gz /tmp/curl-*.tar.gz 2>/dev/null || true
    
    # Clean up any leftover directories
    sudo rm -rf /tmp/curl-* 2>/dev/null || true
    
    log "SUCCESS" "✅ System cleanup complete."
}

verify_removal() {
    show_progress "🔍 Verifying removal..."
    
    local tools=(
        "flux:FluxCD"
        "yq:yq"
        "kustomize:Kustomize"
        "helm:Helm"
        "kubeconform:Kubeconform"
    )
    
    local still_installed=()
    
    for tool_info in "${tools[@]}"; do
        local tool=$(echo "$tool_info" | cut -d: -f1)
        local name=$(echo "$tool_info" | cut -d: -f2)
        
        if is_installed "$tool"; then
            log "WARN" "⚠️ $name: Still installed"
            still_installed+=("$name")
        else
            log "SUCCESS" "✅ $name: Successfully removed"
        fi
    done
    
    # Check custom curl
    if [ -f "/usr/local/bin/curl" ]; then
        log "WARN" "⚠️ Custom curl: Still installed"
        still_installed+=("curl")
    else
        log "SUCCESS" "✅ Custom curl: Successfully removed"
    fi
    
    # Check XRDP service
    if service_exists "xrdp"; then
        log "WARN" "⚠️ XRDP service: Still exists"
        still_installed+=("XRDP")
    else
        log "SUCCESS" "✅ XRDP service: Successfully removed"
    fi
    
    # Check AnyDesk
    if command -v anydesk >/dev/null 2>&1 || dpkg -l | grep -q "^ii.*anydesk" || service_exists "anydesk"; then
        log "WARN" "⚠️ AnyDesk: Still installed"
        still_installed+=("AnyDesk")
    else
        log "SUCCESS" "✅ AnyDesk: Successfully removed"
    fi
    
    if [ ${#still_installed[@]} -eq 0 ]; then
        log "SUCCESS" "✅ All tools have been successfully removed."
    else
        log "WARN" "⚠️ Some tools may require manual removal: ${still_installed[*]}"
    fi
}

show_summary() {
    echo
    echo -e "${B_GREEN}──────────────────────────────────────────${NC}"
    echo -e " ${B_WHITE}✅ Uninstall completed!${NC}"
    echo -e "${B_GREEN}──────────────────────────────────────────${NC}"
    echo
    echo -e "${BLUE}📋 Removed Components:${NC}"
    echo "   🖥️ XFCE4 Desktop Environment"
    echo "   🖥️ XRDP Remote Desktop Server"
    echo "   📦 FluxCD"
    echo "   🔧 yq"
    echo "   📦 Kustomize"
    echo "   📦 Helm"
    echo "   📡 Custom compiled curl"
    echo "   📦 Kubeconform"
    echo "   🖥️ AnyDesk"
    echo "   🔨 Build dependencies"
    echo
    echo -e "${BLUE}📄 Log file:${NC} $LOGFILE"
    echo
    echo -e "${YELLOW}💡 Notes:${NC}"
    echo "   • System packages (git, wget, jq, etc.) were preserved"
    echo "   • SSH service was preserved (system essential)"
    echo "   • User configuration files have been cleaned up"
    echo "   • A system reboot is recommended"
    echo "   • Standard curl from apt packages remains available"
    echo
    echo -e "${GREEN}🎉 Your system has been cleaned up successfully!${NC}"
    echo
}

main() {
    echo -e "${B_PURPLE}───────────────────────────────────────────────────────${NC}"
    echo -e " ${B_WHITE}🗑️  TOTHEMARS - Kubernetes Tools Uninstaller${NC}"
    echo -e " ${B_CYAN}📅 $(TZ='Asia/Bangkok' date '+%H:%M:%S %d-%m-%Y')${NC}"
    echo -e "${B_PURPLE}───────────────────────────────────────────────────────${NC}"
    echo
    
    log "INFO" "📄 Log file: $LOGFILE"
    echo
    
    check_root || { log "ERROR" "❌ Root check failed"; exit 1; }
    confirm_uninstall || { log "INFO" "👋 Cancelled"; exit 0; }
    
    echo
    log "INFO" "🎯 Starting uninstall process..."
    echo
    
    remove_desktop || { log "WARN" "⚠️ Desktop removal encountered issues"; }
    remove_fluxcd || { log "WARN" "⚠️ FluxCD removal encountered issues"; }
    remove_yq || { log "WARN" "⚠️ yq removal encountered issues"; }
    remove_kustomize || { log "WARN" "⚠️ Kustomize removal encountered issues"; }
    remove_helm || { log "WARN" "⚠️ Helm removal encountered issues"; }
    remove_curl || { log "WARN" "⚠️ curl removal encountered issues"; }
    remove_kubeconform || { log "WARN" "⚠️ Kubeconform removal encountered issues"; }
    remove_anydesk || { log "WARN" "⚠️ AnyDesk removal encountered issues"; }
    remove_build_dependencies || { log "WARN" "⚠️ Build dependencies removal encountered issues"; }
    cleanup_system || { log "WARN" "⚠️ System cleanup encountered issues"; }
    verify_removal
    show_summary
    
    log "SUCCESS" "🎉 Uninstall completed!"
}

main "$@"