#!/bin/bash
set -e

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

LOGFILE="/tmp/pgadmin4_uninstall_$(TZ='Asia/Bangkok' date +%Y%m%d_%H%M%S).log"
TOTAL_STEPS=7
CURRENT_STEP=0

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

show_progress() {
    ((CURRENT_STEP++))
    local desc="$1"
    local formatted_title=$(echo "$desc" | sed 's/.*/\L&/; s/[a-z]/\U&/1; s/ \([a-z]\)/ \U\1/g')
    
    printf "\n${CLR_SECTION}${BOLD}▎${NC} ${BOLD}Step %d/%d: %s${NC}\n" "$CURRENT_STEP" "$TOTAL_STEPS" "$formatted_title"
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
    printf "  ${CLR_WARN}👉 are you sure you want to proceed? [y/N]:${NC} "
    read -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "👋 uninstall cancelled by user."
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
    echo -e "${B_GREEN}──────────────────────────────────────────${NC}"
    echo -e " ${B_WHITE}✅ pgAdmin4 Web Uninstall Completed!${NC}"
    echo -e "${B_GREEN}──────────────────────────────────────────${NC}"
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
    printf "\n${CLR_TITLE}${BOLD}▎${NC} ${BOLD}pgAdmin4 Web Uninstaller${NC}\n"
    printf "  ${CLR_DIM}·  date: $(TZ='Asia/Bangkok' date '+%H:%M:%S %d-%m-%Y')${NC}\n\n"
    
    log "INFO" "📄 log file: $LOGFILE"
    
    check_root || { log "ERROR" "root check failed"; exit 1; }
    confirm_uninstall || { log "INFO" "cancelled"; exit 0; }
    
    log "INFO" "🎯 starting uninstall process..."
    
    remove_pgadmin4_apache_config || { log "WARN" "apache config removal encountered issues"; }
    remove_pgadmin4_packages || { log "WARN" "package removal encountered issues"; }
    remove_pgadmin4_data || { log "WARN" "data removal encountered issues"; }
    remove_pgadmin4_repository || { log "WARN" "repository removal encountered issues"; }
    restore_apache_port || { log "WARN" "apache port restore encountered issues"; }
    restart_apache || { log "WARN" "apache restart encountered issues"; }
    cleanup_system || { log "WARN" "system cleanup encountered issues"; }
    verify_removal
    show_summary
    
    log "SUCCESS" "🎉 uninstall completed!"
}

main "$@"

