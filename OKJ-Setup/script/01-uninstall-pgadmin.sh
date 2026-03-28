#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

LOGFILE="/tmp/pgadmin4_uninstall_$(TZ='Asia/Bangkok' date +%Y%m%d_%H%M%S).log"
TOTAL_STEPS=7
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
    echo "   • pgAdmin4 Web"
    echo "   • pgAdmin4 Server"
    echo "   • pgAdmin4 Apache configuration"
    echo "   • pgAdmin4 data and configuration files"
    echo "   • pgAdmin4 repository and GPG key"
    echo "   • Apache port configuration backup (if exists)"
    echo
    echo -e "${BLUE}ℹ️ Note: The following will be preserved:${NC}"
    echo "   • Apache web server"
    echo "   • PostgreSQL client (may be used by other applications)"
    echo "   • wsgi module (may be used by other applications)"
    echo "   • expect package (installed by install script, may be used by other applications)"
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

remove_pgadmin4_apache_config() {
    show_progress "🗑️ Removing pgAdmin4 Apache configuration..."
    
    # Disable and remove pgAdmin4 Apache config
    if [ -f /etc/apache2/conf-enabled/pgadmin4.conf ]; then
        log "INFO" "🔧 Disabling pgAdmin4 Apache configuration..."
        sudo a2disconf pgadmin4 2>/dev/null || true
    fi
    
    # Remove config files
    if [ -f /etc/apache2/conf-available/pgadmin4.conf ]; then
        log "INFO" "🗑️ Removing pgAdmin4 Apache config file..."
        sudo rm -f /etc/apache2/conf-available/pgadmin4.conf
        log "SUCCESS" "✅ pgAdmin4 Apache config removed."
    fi
    
    if [ -f /etc/apache2/conf-enabled/pgadmin4.conf ]; then
        log "INFO" "🗑️ Removing enabled symlink..."
        sudo rm -f /etc/apache2/conf-enabled/pgadmin4.conf
    fi
    
    # Remove any VirtualHost entries
    if [ -f /etc/apache2/sites-enabled/pgadmin4.conf ]; then
        log "INFO" "🗑️ Removing pgAdmin4 VirtualHost..."
        sudo a2dissite pgadmin4 2>/dev/null || true
        sudo rm -f /etc/apache2/sites-available/pgadmin4.conf
        sudo rm -f /etc/apache2/sites-enabled/pgadmin4.conf
    fi
    
    log "SUCCESS" "✅ pgAdmin4 Apache configuration removed."
}

restore_apache_port() {
    show_progress "🔧 Restoring Apache port configuration..."
    
    local port_restored=false
    
    # Restore ports.conf if backup exists
    if [ -f /etc/apache2/ports.conf.backup ]; then
        log "INFO" "📦 Restoring Apache ports.conf from backup..."
        sudo cp /etc/apache2/ports.conf.backup /etc/apache2/ports.conf
        sudo rm -f /etc/apache2/ports.conf.backup
        log "SUCCESS" "✅ Apache port configuration restored."
        port_restored=true
    else
        log "INFO" "ℹ️ No backup found. Apache port configuration unchanged."
    fi
    
    # If port was restored, also restore VirtualHost files to default port 80
    if [ "$port_restored" = true ]; then
        log "INFO" "🔧 Restoring VirtualHost files to default port 80..."
        
        # Restore 000-default.conf
        if [ -f /etc/apache2/sites-available/000-default.conf ]; then
            # Check if it contains a non-standard port (not 80)
            if grep -q "<VirtualHost \*:[0-9]*>" /etc/apache2/sites-available/000-default.conf 2>/dev/null; then
                # Replace any port with 80
                sudo sed -i "s/<VirtualHost \*:[0-9]*>/<VirtualHost *:80>/" /etc/apache2/sites-available/000-default.conf 2>/dev/null || true
                log "INFO" "  └─ Restored VirtualHost in 000-default.conf to port 80"
            fi
        fi
        
        # Restore default-ssl.conf
        if [ -f /etc/apache2/sites-available/default-ssl.conf ]; then
            # Check if it contains a non-standard port (not 80)
            if grep -q "<VirtualHost _default_:[0-9]*>" /etc/apache2/sites-available/default-ssl.conf 2>/dev/null; then
                # Replace any port with 80
                sudo sed -i "s/<VirtualHost _default_:[0-9]*>/<VirtualHost _default_:80>/" /etc/apache2/sites-available/default-ssl.conf 2>/dev/null || true
                log "INFO" "  └─ Restored VirtualHost in default-ssl.conf to port 80"
            fi
        fi
        
        log "SUCCESS" "✅ VirtualHost files restored to default port 80."
    fi
}

remove_pgadmin4_packages() {
    show_progress "🗑️ Removing pgAdmin4 packages..."
    
    # Remove pgAdmin4 Web
    if dpkg -l | grep -q "^ii.*pgadmin4-web.*"; then
        log "INFO" "📦 Removing pgAdmin4 Web..."
        sudo apt remove --purge -y pgadmin4-web 2>/dev/null || true
        log "SUCCESS" "✅ pgAdmin4 Web removed."
    else
        log "INFO" "ℹ️ pgAdmin4 Web is not installed."
    fi
    
    # Remove pgAdmin4 Server
    if dpkg -l | grep -q "^ii.*pgadmin4-server.*"; then
        log "INFO" "📦 Removing pgAdmin4 Server..."
        sudo apt remove --purge -y pgadmin4-server 2>/dev/null || true
        log "SUCCESS" "✅ pgAdmin4 Server removed."
    else
        log "INFO" "ℹ️ pgAdmin4 Server is not installed."
    fi
    
    # Remove PostgreSQL client if it was installed by pgAdmin4
    # Note: Only remove if it seems to be installed only for pgAdmin4
    # We'll be conservative and not remove it automatically
    log "INFO" "ℹ️ PostgreSQL client will be preserved (may be used by other applications)"
}

remove_pgadmin4_data() {
    show_progress "🧹 Removing pgAdmin4 data and configuration files..."
    
    # Remove pgAdmin4 data directory
    if [ -d /var/lib/pgadmin ]; then
        log "INFO" "🗑️ Removing pgAdmin4 data directory..."
        sudo rm -rf /var/lib/pgadmin 2>/dev/null || true
        log "SUCCESS" "✅ pgAdmin4 data directory removed."
    fi
    
    # Remove pgAdmin4 log directory
    if [ -d /var/log/pgadmin ]; then
        log "INFO" "🗑️ Removing pgAdmin4 log directory..."
        sudo rm -rf /var/log/pgadmin 2>/dev/null || true
        log "SUCCESS" "✅ pgAdmin4 log directory removed."
    fi
    
    # Remove pgAdmin4 installation directory (if exists)
    if [ -d /usr/pgadmin4 ]; then
        log "INFO" "🗑️ Removing pgAdmin4 installation directory..."
        sudo rm -rf /usr/pgadmin4 2>/dev/null || true
        log "SUCCESS" "✅ pgAdmin4 installation directory removed."
    fi
    
    log "SUCCESS" "✅ pgAdmin4 data and configuration files removed."
}

remove_pgadmin4_repository() {
    show_progress "🗑️ Removing pgAdmin4 repository..."
    
    # Remove repository file
    if [ -f /etc/apt/sources.list.d/pgadmin4.list ]; then
        log "INFO" "🗑️ Removing pgAdmin4 repository file..."
        sudo rm -f /etc/apt/sources.list.d/pgadmin4.list
        log "SUCCESS" "✅ Repository file removed."
    fi
    
    # Remove GPG key
    if [ -f /usr/share/keyrings/packages-pgadmin-org.gpg ]; then
        log "INFO" "🗑️ Removing pgAdmin4 GPG key..."
        sudo rm -f /usr/share/keyrings/packages-pgadmin-org.gpg
        log "SUCCESS" "✅ GPG key removed."
    fi
    
    # Update package lists
    log "INFO" "🔄 Updating package lists..."
    sudo apt update -qq 2>/dev/null || true
    
    log "SUCCESS" "✅ pgAdmin4 repository removed."
}

restart_apache() {
    show_progress "🔄 Restarting Apache..."
    
    # Test Apache configuration
    log "INFO" "🔍 Testing Apache configuration..."
    if sudo apache2ctl -t 2>/dev/null; then
        log "SUCCESS" "✅ Apache configuration is valid."
        
        # Restart Apache
        log "INFO" "🔄 Restarting Apache service..."
        if sudo systemctl restart apache2 2>/dev/null; then
            log "SUCCESS" "✅ Apache restarted successfully."
        else
            log "WARN" "⚠️  Apache restart failed, but continuing..."
        fi
    else
        log "WARN" "⚠️  Apache configuration test failed."
        log "INFO" "💡 Please check Apache configuration manually"
    fi
}

cleanup_system() {
    show_progress "🧹 Cleaning up system..."
    
    log "INFO" "📦 Running system cleanup..."
    sudo apt autoremove -y -qq 2>/dev/null || true
    sudo apt autoclean -qq 2>/dev/null || true
    
    log "SUCCESS" "✅ System cleanup complete."
}

verify_removal() {
    show_progress "🔍 Verifying removal..."
    
    local still_installed=()
    
    # Check pgAdmin4 packages
    if dpkg -l | grep -q "^ii.*pgadmin4-web.*"; then
        log "WARN" "⚠️  pgAdmin4 Web: Still installed"
        still_installed+=("pgAdmin4 Web")
    else
        log "SUCCESS" "✅ pgAdmin4 Web: Successfully removed"
    fi
    
    if dpkg -l | grep -q "^ii.*pgadmin4-server.*"; then
        log "WARN" "⚠️  pgAdmin4 Server: Still installed"
        still_installed+=("pgAdmin4 Server")
    else
        log "SUCCESS" "✅ pgAdmin4 Server: Successfully removed"
    fi
    
    # Check Apache config
    if [ -f /etc/apache2/conf-available/pgadmin4.conf ] || [ -f /etc/apache2/conf-enabled/pgadmin4.conf ]; then
        log "WARN" "⚠️  pgAdmin4 Apache config: Still exists"
        still_installed+=("Apache config")
    else
        log "SUCCESS" "✅ pgAdmin4 Apache config: Successfully removed"
    fi
    
    # Check data directory
    if [ -d /var/lib/pgadmin ]; then
        log "WARN" "⚠️  pgAdmin4 data directory: Still exists"
        still_installed+=("Data directory")
    else
        log "SUCCESS" "✅ pgAdmin4 data directory: Successfully removed"
    fi
    
    # Check repository
    if [ -f /etc/apt/sources.list.d/pgadmin4.list ]; then
        log "WARN" "⚠️  pgAdmin4 repository: Still exists"
        still_installed+=("Repository")
    else
        log "SUCCESS" "✅ pgAdmin4 repository: Successfully removed"
    fi
    
    if [ ${#still_installed[@]} -eq 0 ]; then
        log "SUCCESS" "✅ All pgAdmin4 components have been successfully removed."
    else
        log "WARN" "⚠️  Some components may require manual removal: ${still_installed[*]}"
    fi
}

show_summary() {
    echo
    echo "=========================================="
    echo -e "${GREEN}✅ pgAdmin4 Web Uninstall Completed!${NC}"
    echo "=========================================="
    echo
    echo -e "${BLUE}📋 Removed Components:${NC}"
    echo "   📦 pgAdmin4 Web"
    echo "   📦 pgAdmin4 Server"
    echo "   🔧 pgAdmin4 Apache configuration"
    echo "   📁 pgAdmin4 data and configuration files"
    echo "   📦 pgAdmin4 repository and GPG key"
    echo
    echo -e "${BLUE}📄 Log file:${NC} $LOGFILE"
    echo
    echo -e "${YELLOW}💡 Notes:${NC}"
    echo "   • Apache web server remains installed"
    echo "   • PostgreSQL client remains installed (may be used by other apps)"
    echo "   • wsgi module remains enabled (may be used by other apps)"
    echo "   • expect package remains installed (installed by install script)"
    echo "   • Apache port configuration has been restored (if backup existed)"
    echo "   • A system reboot is recommended to complete the cleanup"
    echo
    echo -e "${GREEN}🎉 pgAdmin4 Web has been removed successfully!${NC}"
    echo
}

main() {
    echo "======================================================="
    echo -e "${PURPLE}🗑️  TOTHEMARS - pgAdmin4 Web Uninstaller${NC}"
    echo -e "${CYAN}📅 $(TZ='Asia/Bangkok' date '+%H:%M:%S %d-%m-%Y')${NC}"
    echo "======================================================="
    echo
    
    log "INFO" "📄 Log file: $LOGFILE"
    echo
    
    check_root || { log "ERROR" "❌ Root check failed"; exit 1; }
    confirm_uninstall || { log "INFO" "👋 Cancelled"; exit 0; }
    
    echo
    log "INFO" "🎯 Starting uninstall process..."
    echo
    
    remove_pgadmin4_apache_config || { log "WARN" "⚠️ Apache config removal encountered issues"; }
    remove_pgadmin4_packages || { log "WARN" "⚠️ Package removal encountered issues"; }
    remove_pgadmin4_data || { log "WARN" "⚠️ Data removal encountered issues"; }
    remove_pgadmin4_repository || { log "WARN" "⚠️ Repository removal encountered issues"; }
    restore_apache_port || { log "WARN" "⚠️ Apache port restore encountered issues"; }
    restart_apache || { log "WARN" "⚠️ Apache restart encountered issues"; }
    cleanup_system || { log "WARN" "⚠️ System cleanup encountered issues"; }
    verify_removal
    show_summary
    
    log "SUCCESS" "🎉 Uninstall completed!"
}

main "$@"

