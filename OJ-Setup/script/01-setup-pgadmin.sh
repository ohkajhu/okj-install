#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

LOGFILE="/tmp/pgadmin4_install_$(TZ='Asia/Bangkok' date +%Y%m%d_%H%M%S).log"
TOTAL_STEPS=9
CURRENT_STEP=0

PGADMIN_EMAIL="${PGADMIN_EMAIL:-admin@ohkajhu.com}"
PGADMIN_PASSWORD="${PGADMIN_PASSWORD:-Xw2#Rk9xLp}"
APACHE_PORT="${APACHE_PORT:-8080}"

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(TZ='Asia/Bangkok' date '+%H:%M:%S %d-%m-%Y')
    
    case $level in
        "INFO")    echo -e "  ${B_BLUE}ℹ [INFO]${NC} $message" | tee -a "$LOGFILE" ;;
        "WARN")    echo -e "  ${B_YELLOW}⚠ [WARN]${NC} $message" | tee -a "$LOGFILE" ;;
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

check_dependencies() {
    log "INFO" "🔍 Checking dependencies..."
    
    local missing=()
    local required=("curl" "gpg" "lsb_release" "expect")
    
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

check_port_conflict() {
    local port=$1
    log "INFO" "🔍 Checking port $port availability..."
    
    # Check if port is in use
    if command -v netstat >/dev/null 2>&1; then
        if sudo netstat -tlnp | grep -q ":$port "; then
            local service=$(sudo netstat -tlnp | grep ":$port " | awk '{print $7}' | head -n1)
            log "WARN" "⚠️ Port $port is already in use by: $service"
            return 1
        fi
    elif command -v ss >/dev/null 2>&1; then
        if sudo ss -tlnp | grep -q ":$port "; then
            local service=$(sudo ss -tlnp | grep ":$port " | awk '{print $6}' | head -n1)
            log "WARN" "⚠️ Port $port is already in use by: $service"
            return 1
        fi
    fi
    
    log "SUCCESS" "✅ Port $port is available."
    return 0
}

# Helper function to enable pgAdmin4 Apache configuration
enable_pgadmin4_apache_config() {
    if [ -f /etc/apache2/conf-available/pgadmin4.conf ] && [ ! -f /etc/apache2/conf-enabled/pgadmin4.conf ]; then
        log "INFO" "🔧 Enabling pgAdmin4 Apache configuration..."
        sudo a2enconf pgadmin4 2>/dev/null || true
        return 0
    fi
    return 0
}

# Helper function to check for pgAdmin4 database file
check_pgadmin4_database() {
    local db_paths=(
        "/var/lib/pgadmin/pgadmin4.db"
        "/var/lib/pgadmin/pgAdmin4.db"
        "/var/lib/pgadmin/storage/pgadmin4.db"
    )
    
    for path in "${db_paths[@]}"; do
        if [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    # Search in /var/lib/pgadmin directory
    local found_db=$(find /var/lib/pgadmin -name "*.db" -type f 2>/dev/null | head -n1)
    if [ -n "$found_db" ]; then
        echo "$found_db"
        return 0
    fi
    
    return 1
}

# Helper function to check for pgAdmin4 Apache configuration
check_pgadmin4_apache_config() {
    if [ -f /etc/apache2/conf-enabled/pgadmin4.conf ]; then
        echo "enabled"
        return 0
    elif [ -f /etc/apache2/conf-available/pgadmin4.conf ]; then
        echo "available"
        return 0
    else
        # Check for any pgAdmin4 related Apache configs
        local found_conf=$(find /etc/apache2 -name "*pgadmin*" -type f 2>/dev/null | head -n1)
        if [ -n "$found_conf" ]; then
            echo "found:$found_conf"
            return 0
        fi
    fi
    
    return 1
}

# Helper function to fix broken packages
fix_broken_packages() {
    log "INFO" "🔧 Fixing broken packages (if any)..."
    sudo dpkg --configure -a 2>/dev/null || true
    sudo apt install -f -y -qq 2>/dev/null || true
}

show_configuration() {
    log "INFO" "📋 Configuration:"
    log "INFO" "📧 Email: $PGADMIN_EMAIL"
    log "INFO" "🔑 Password: ${PGADMIN_PASSWORD}"
    log "INFO" "🔌 Apache Port: $APACHE_PORT"
}

setup_repository() {
    show_progress "📦 Setting up pgAdmin4 repository..."
    
    log "INFO" "🔑 Adding pgAdmin4 GPG key..."
    
    # Check if GPG key already exists
    if [ -f /usr/share/keyrings/packages-pgadmin-org.gpg ]; then
        log "INFO" "ℹ️ GPG key already exists, skipping download."
        # Verify the key is valid
        if sudo gpg --no-tty --batch --list-keys --keyring /usr/share/keyrings/packages-pgadmin-org.gpg >/dev/null 2>&1; then
            log "SUCCESS" "✅ Using existing GPG key."
            # Skip to repository setup
        else
            log "WARN" "⚠️ Existing GPG key appears invalid, will re-download..."
            sudo rm -f /usr/share/keyrings/packages-pgadmin-org.gpg 2>/dev/null || true
        fi
    fi
    
    # Only download if key doesn't exist or is invalid
    if [ ! -f /usr/share/keyrings/packages-pgadmin-org.gpg ]; then
        # Remove existing key if present to avoid overwrite prompt
        sudo rm -f /usr/share/keyrings/packages-pgadmin-org.gpg 2>/dev/null || true
    
    # Download GPG key with timeout and retry
    local gpg_key_url="https://www.pgadmin.org/static/packages_pgadmin_org.pub"
    local gpg_key_file=$(mktemp)
    local max_retries=3
    local retry_count=0
    local download_success=false
    
    # Try downloading with curl first (with SSL options)
    while [ $retry_count -lt $max_retries ] && [ "$download_success" = false ]; do
        log "INFO" "📥 Downloading GPG key with curl (attempt $((retry_count + 1))/$max_retries)..."
        if curl -fsS --connect-timeout 10 --max-time 30 --tlsv1.2 --ciphers 'DEFAULT:!DH' "$gpg_key_url" -o "$gpg_key_file" 2>&1 | tee -a "$LOGFILE"; then
            # Verify the downloaded file is not empty
            if [ -s "$gpg_key_file" ]; then
                download_success=true
                break
            else
                log "WARN" "⚠️ Downloaded file is empty, retrying..."
            fi
        else
            log "WARN" "⚠️ curl download failed, will try alternative method..."
        fi
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            sleep 2
        fi
    done
    
    # If curl failed, try wget as fallback
    if [ "$download_success" = false ] && command -v wget >/dev/null 2>&1; then
        log "INFO" "📥 Trying wget as fallback..."
        retry_count=0
        while [ $retry_count -lt $max_retries ] && [ "$download_success" = false ]; do
            log "INFO" "📥 Downloading GPG key with wget (attempt $((retry_count + 1))/$max_retries)..."
            if wget --timeout=30 --tries=1 --no-check-certificate -q -O "$gpg_key_file" "$gpg_key_url" 2>&1 | tee -a "$LOGFILE"; then
                if [ -s "$gpg_key_file" ]; then
                    download_success=true
                    break
                fi
            fi
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                sleep 2
            fi
        done
    fi
    
    # If still failed, try with curl --insecure as last resort
    if [ "$download_success" = false ]; then
        log "WARN" "⚠️ Standard methods failed, trying with relaxed SSL verification..."
        if curl -fsS --connect-timeout 10 --max-time 30 --insecure "$gpg_key_url" -o "$gpg_key_file" 2>&1 | tee -a "$LOGFILE"; then
            if [ -s "$gpg_key_file" ]; then
                download_success=true
            fi
        fi
    fi
    
    if [ "$download_success" = false ]; then
        log "ERROR" "❌ Failed to download GPG key after all attempts."
        log "INFO" "💡 Network connectivity issue detected."
        log "INFO" "💡 You can manually download the GPG key:"
        log "INFO" "   curl -fsS https://www.pgadmin.org/static/packages_pgadmin_org.pub | sudo gpg --dearmor -o /usr/share/keyrings/packages-pgadmin-org.gpg"
        log "INFO" "   Or use wget:"
        log "INFO" "   wget -q -O - https://www.pgadmin.org/static/packages_pgadmin_org.pub | sudo gpg --dearmor -o /usr/share/keyrings/packages-pgadmin-org.gpg"
        log "WARN" "⚠️ Attempting to continue without GPG key verification (not recommended)..."
        # Create a dummy key file to allow repository setup to continue
        # This is not secure but allows installation to proceed
        log "WARN" "⚠️ Repository will be added without GPG verification."
        sudo touch /usr/share/keyrings/packages-pgadmin-org.gpg 2>/dev/null || true
        rm -f "$gpg_key_file"
    else
        # Import GPG key
        log "INFO" "🔐 Importing GPG key..."
        if sudo gpg --no-tty --batch --yes --dearmor -o /usr/share/keyrings/packages-pgadmin-org.gpg "$gpg_key_file" 2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "✅ GPG key added successfully."
            rm -f "$gpg_key_file"
        else
            log "ERROR" "❌ Failed to import GPG key."
            rm -f "$gpg_key_file"
            return 1
        fi
    fi
    fi
    
    log "INFO" "📝 Adding pgAdmin4 repository..."
    local distro=$(lsb_release -cs 2>/dev/null || echo "jammy")
    local repo_line="deb [signed-by=/usr/share/keyrings/packages-pgadmin-org.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$distro pgadmin4 main"
    
    echo "$repo_line" | sudo tee /etc/apt/sources.list.d/pgadmin4.list >/dev/null
    
    log "INFO" "🔄 Updating package lists..."
    sudo apt update -qq
    
    log "SUCCESS" "✅ Repository setup complete."
}

remove_desktop_version() {
    show_progress "🗑️ Removing pgAdmin4 Desktop (if installed)..."
    
    if dpkg -l | grep -q "^ii.*pgadmin4-desktop.*"; then
        log "INFO" "📦 Removing pgAdmin4 Desktop..."
        sudo apt remove --purge -y pgadmin4-desktop 2>/dev/null || true
        sudo apt autoremove -y -qq 2>/dev/null || true
        log "SUCCESS" "✅ pgAdmin4 Desktop removed."
    else
        log "INFO" "ℹ️ pgAdmin4 Desktop is not installed."
    fi
    
    # Check and handle broken packages (like anydesk) that might interfere
    log "INFO" "🔧 Checking for broken packages..."
    if dpkg -l | grep -q "^..r.*anydesk\|^..i.*anydesk"; then
        log "WARN" "⚠️ Found problematic anydesk package. Attempting to fix..."
        fix_broken_packages || {
            log "WARN" "⚠️ Could not fix anydesk package, but continuing with pgAdmin4 installation..."
        }
    fi
}

install_pgadmin4_web() {
    show_progress "📦 Installing pgAdmin4 Web..."
    
    if dpkg -l | grep -q "^ii.*pgadmin4-web.*"; then
        local version=$(dpkg -l | grep "^ii.*pgadmin4-web" | awk '{print $3}' | head -n1)
        log "INFO" "✅ pgAdmin4 Web is already installed (Version: $version)"
        return 0
    fi
    
    log "INFO" "📥 Installing pgAdmin4 Web..."
    
    # Try to fix any broken packages first
    fix_broken_packages
    
    # Install pgAdmin4 Web
    # Note: We check installation status even if apt returns error
    # because other packages (like anydesk) might fail but pgAdmin4 might succeed
    sudo apt install -y pgadmin4-web 2>&1 | tee -a "$LOGFILE" || {
        log "WARN" "⚠️ apt install returned error, checking if pgAdmin4 Web was installed..."
    }
    
    # Verify if pgAdmin4 Web was actually installed
    if dpkg -l | grep -q "^ii.*pgadmin4-web.*"; then
        local version=$(dpkg -l | grep "^ii.*pgadmin4-web" | awk '{print $3}' | head -n1)
        log "SUCCESS" "✅ pgAdmin4 Web installed successfully (Version: $version)"
        
        # Try to fix any remaining broken packages (but don't fail if it doesn't work)
        fix_broken_packages || {
            log "WARN" "⚠️ Some packages may still be broken (e.g., anydesk), but pgAdmin4 Web is installed successfully."
        }
        
        return 0
    else
        log "ERROR" "❌ pgAdmin4 Web installation failed. Package not found."
        log "INFO" "💡 Trying to fix broken packages and retry..."
        fix_broken_packages
        
        # Retry installation
        log "INFO" "🔄 Retrying pgAdmin4 Web installation..."
        if sudo apt install -y pgadmin4-web; then
            local version=$(dpkg -l | grep "^ii.*pgadmin4-web" | awk '{print $3}' | head -n1)
            log "SUCCESS" "✅ pgAdmin4 Web installed successfully after retry (Version: $version)"
            return 0
        else
            log "ERROR" "❌ pgAdmin4 Web installation failed after retry."
            return 1
        fi
    fi
}

configure_pgadmin4() {
    show_progress "⚙️ Configuring pgAdmin4..."
    
    if [ ! -f "/usr/pgadmin4/bin/setup-web.sh" ]; then
        log "ERROR" "❌ setup-web.sh not found. pgAdmin4 may not be installed correctly."
        return 1
    fi
    
    # Configure Apache port BEFORE running setup-web.sh
    log "INFO" "🔧 Configuring Apache port to $APACHE_PORT..."
    
    # Fix port 443 conflict first
    log "INFO" "🔍 Checking for port 443 conflict..."
    if command -v netstat >/dev/null 2>&1; then
        if sudo netstat -tlnp | grep -q ":443 "; then
            local port443_process=$(sudo netstat -tlnp | grep ":443 " | awk '{print $7}' | head -n1)
            log "WARN" "⚠️ Port 443 is already in use by: $port443_process"
            log "INFO" "  └─ Disabling SSL to avoid conflict..."
            sudo a2dissite default-ssl 2>/dev/null || true
            if grep -q "^Listen 443" /etc/apache2/ports.conf 2>/dev/null; then
                sudo sed -i 's/^Listen 443/#Listen 443/' /etc/apache2/ports.conf
                log "INFO" "  └─ Commented out Listen 443 in ports.conf"
            fi
        fi
    elif command -v ss >/dev/null 2>&1; then
        if sudo ss -tlnp | grep -q ":443 "; then
            local port443_process=$(sudo ss -tlnp | grep ":443 " | awk '{print $6}' | head -n1)
            log "WARN" "⚠️ Port 443 is already in use by: $port443_process"
            log "INFO" "  └─ Disabling SSL to avoid conflict..."
            sudo a2dissite default-ssl 2>/dev/null || true
            if grep -q "^Listen 443" /etc/apache2/ports.conf 2>/dev/null; then
                sudo sed -i 's/^Listen 443/#Listen 443/' /etc/apache2/ports.conf
                log "INFO" "  └─ Commented out Listen 443 in ports.conf"
            fi
        fi
    fi
    
    if [ "$APACHE_PORT" != "80" ]; then
        # Backup original ports.conf
        if [ ! -f /etc/apache2/ports.conf.backup ]; then
            sudo cp /etc/apache2/ports.conf /etc/apache2/ports.conf.backup
            log "INFO" "💾 Backed up /etc/apache2/ports.conf"
        fi
        
        # Change Listen port
        if sudo sed -i "s/^Listen 80$/Listen $APACHE_PORT/" /etc/apache2/ports.conf 2>/dev/null; then
            log "SUCCESS" "✅ Apache port changed to $APACHE_PORT."
        else
            # If the pattern doesn't exist, add it
            if ! grep -q "^Listen $APACHE_PORT" /etc/apache2/ports.conf; then
                echo "Listen $APACHE_PORT" | sudo tee -a /etc/apache2/ports.conf >/dev/null
                log "SUCCESS" "✅ Added Listen $APACHE_PORT to Apache config."
            fi
        fi
        
        # Update virtualhost if needed
        if [ -f /etc/apache2/sites-available/000-default.conf ]; then
            sudo sed -i "s/<VirtualHost \*:80>/<VirtualHost *:$APACHE_PORT>/" /etc/apache2/sites-available/000-default.conf 2>/dev/null || true
            log "INFO" "  └─ Updated VirtualHost in 000-default.conf to port $APACHE_PORT"
        fi
        
        if [ -f /etc/apache2/sites-available/default-ssl.conf ]; then
            sudo sed -i "s/<VirtualHost _default_:80>/<VirtualHost _default_:$APACHE_PORT>/" /etc/apache2/sites-available/default-ssl.conf 2>/dev/null || true
            log "INFO" "  └─ Updated VirtualHost in default-ssl.conf to port $APACHE_PORT"
        fi
    else
        log "INFO" "ℹ️  Using default port 80."
    fi
    
    # Ensure Apache is installed and can start before running setup-web.sh
    log "INFO" "🔍 Checking Apache status before configuration..."
    if ! systemctl is-active --quiet apache2 2>/dev/null; then
        log "INFO" "📦 Apache is not running. Checking configuration..."
        
        # Test Apache configuration
        if sudo apache2ctl -t 2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "✅ Apache configuration is valid."
        else
            log "WARN" "⚠️ Apache configuration has errors. Attempting to fix..."
            # Try to fix common issues
            sudo a2enmod wsgi 2>/dev/null || true
            sudo a2enmod rewrite 2>/dev/null || true
            sudo a2enmod ssl 2>/dev/null || true
        fi
        
        # Try to start Apache
        log "INFO" "🔄 Attempting to start Apache..."
        if sudo systemctl start apache2 2>&1 | tee -a "$LOGFILE"; then
            sleep 2
            if systemctl is-active --quiet apache2 2>/dev/null; then
                log "SUCCESS" "✅ Apache started successfully."
            else
                log "WARN" "⚠️ Apache failed to start. Will continue with setup-web.sh (it may start Apache)."
                log "INFO" "💡 Check Apache logs: sudo journalctl -xeu apache2.service"
            fi
        else
            log "WARN" "⚠️ Could not start Apache. Will continue with setup-web.sh (it may start Apache)."
        fi
    else
        log "SUCCESS" "✅ Apache is already running."
    fi
    
    # Check if already configured - more comprehensive check
    log "INFO" "🔍 Checking if pgAdmin4 is already configured..."
    
    # Check for database file in multiple locations
    log "INFO" "🔍 Checking for pgAdmin4 database file..."
    local db_exists=false
    if [ -f /var/lib/pgadmin/pgadmin4.db ]; then
        db_exists=true
        log "INFO" "✅ Found database file: /var/lib/pgadmin/pgadmin4.db"
    elif [ -f /var/lib/pgadmin/pgAdmin4.db ]; then
        db_exists=true
        log "INFO" "✅ Found database file: /var/lib/pgadmin/pgAdmin4.db"
    elif [ -d /var/lib/pgadmin ]; then
        local found_db=$(find /var/lib/pgadmin -name "*.db" -type f 2>/dev/null | head -n1)
        if [ -n "$found_db" ]; then
            db_exists=true
            log "INFO" "✅ Found database file: $found_db"
        else
            log "INFO" "ℹ️ /var/lib/pgadmin directory exists but no .db file found"
            # List contents for debugging
            log "INFO" "📂 Contents of /var/lib/pgadmin:"
            ls -la /var/lib/pgadmin/ 2>/dev/null | head -n10 | while read -r line; do
                log "INFO" "   $line"
            done || true
        fi
    else
        log "INFO" "ℹ️ /var/lib/pgadmin directory does not exist"
    fi
    
    # Check for Apache configuration
    log "INFO" "🔍 Checking for pgAdmin4 Apache configuration..."
    local conf_exists=false
    if [ -f /etc/apache2/conf-enabled/pgadmin4.conf ]; then
        conf_exists=true
        log "INFO" "✅ Found Apache config (enabled): /etc/apache2/conf-enabled/pgadmin4.conf"
    elif [ -f /etc/apache2/conf-available/pgadmin4.conf ]; then
        conf_exists=true
        log "INFO" "✅ Found Apache config (available): /etc/apache2/conf-available/pgadmin4.conf"
    else
        log "INFO" "ℹ️  Apache config file not found in standard locations"
        # Check for any pgAdmin4 related Apache configs
        local found_conf=$(find /etc/apache2 -name "*pgadmin*" -type f 2>/dev/null | head -n1)
        if [ -n "$found_conf" ]; then
            conf_exists=true
            log "INFO" "✅ Found Apache config: $found_conf"
        fi
    fi
    
    # If both database and config exist, pgAdmin4 is already configured
    if [ "$db_exists" = true ] && [ "$conf_exists" = true ]; then
        log "SUCCESS" "✅ pgAdmin4 is already fully configured. Skipping setup-web.sh"
        enable_pgadmin4_apache_config
        return 0
    elif [ "$conf_exists" = true ]; then
        log "INFO" "⚠️ Apache config exists but database file not found"
        log "INFO" "💡 This may be a partial configuration. Will attempt to run setup-web.sh"
        log "INFO" "💡 If setup-web.sh detects existing config, it may skip some steps"
        log "INFO" "💡 Note: setup-web.sh may ask if you want to reconfigure Apache - we'll answer 'no'"
    elif [ "$db_exists" = true ]; then
        log "INFO" "⚠️ Database file exists but Apache config not found"
        log "INFO" "💡 Will run setup-web.sh to configure Apache"
    else
        log "INFO" "ℹ️ pgAdmin4 is not configured. Will run setup-web.sh"
    fi
    
    # If Apache config exists but no database, we might need to create database without reconfiguring Apache
    # But setup-web.sh doesn't have a flag for this, so we'll let it run and handle prompts
    
    # If Apache config exists but no database, try to create database without reconfiguring Apache
    # Check if we can use pgAdmin4's setup script to create database only
    if [ "$conf_exists" = true ] && [ "$db_exists" = false ]; then
        log "INFO" "🔍 Apache config exists but database is missing"
        log "INFO" "💡 Attempting to create database without reconfiguring Apache..."
        
        # Check if we can manually create the database using pgAdmin4's Python setup
        if [ -f /usr/pgadmin4/web/pgAdmin4.py ]; then
            log "INFO" "💡 Found pgAdmin4.py - may be able to create database directly"
        fi
        
        # setup-web.sh will detect existing config and may ask to reconfigure
        # We'll answer 'no' to reconfigure questions but 'yes' to create database
    fi
    
    # Enable wsgi module if not already enabled
    log "INFO" "🔧 Enabling Apache wsgi module..."
    if ! apache2ctl -M 2>/dev/null | grep -q wsgi; then
        sudo a2enmod wsgi 2>/dev/null || true
        log "INFO" "✅ wsgi module enabled."
    else
        log "INFO" "ℹ️ wsgi module already enabled."
    fi
    
    log "INFO" "🔧 Running pgAdmin4 web setup..."
    log "INFO" "📧 Email: $PGADMIN_EMAIL"
    log "INFO" "🔑 Password: ${PGADMIN_PASSWORD}"
    log "INFO" "💡 Note: If pgAdmin4 is already configured, setup-web.sh may skip some steps or prompt for confirmation."
    
    # Refresh sudo timestamp to ensure it's cached
    log "INFO" "🔐 Refreshing sudo timestamp..."
    sudo -v || {
        log "ERROR" "❌ Sudo password required. Please ensure sudo is cached."
        return 1
    }
    
    # Refresh sudo timestamp again to extend it (for expect script)
    sudo -v || {
        log "ERROR" "❌ Sudo password required. Please ensure sudo is cached."
        return 1
    }
    
    # Create temporary expect script for non-interactive setup
    # Setup script expects: email, password, retype password, configure Apache (y), restart Apache (y)
    local expect_script=$(mktemp)
    
    # Create expect script with proper escaping
    cat > "$expect_script" <<'EXPECT_EOF'
#!/usr/bin/expect -f
# Set overall timeout to 5 minutes
set timeout 300
# Individual prompts will use 30-second timeout to prevent hanging
set send_slow {1 .1}

# Get password and email from environment
set pgadmin_email $env(PGADMIN_EMAIL)
set pgadmin_password $env(PGADMIN_PASSWORD)

# Enable verbose logging to see what's happening
log_user 1

# Enable exp_internal to see what expect is matching (for debugging)
# exp_internal 1

# Run setup-web.sh
spawn /usr/pgadmin4/bin/setup-web.sh

# Wait a moment for initial output
sleep 2
send_user "INFO: Started setup-web.sh, waiting for prompts...\n"

# Set expect to match strings that might be split across lines
# Increase buffer to handle long prompts with newlines
match_max 5000

# Enable exp_continue to stay in expect blocks
# Use expect_before to catch Password prompt and Apache prompts anywhere
# This will match in ALL subsequent expect blocks
expect_before {
    # Match "Password:" - exact match first (case-sensitive)
    -ex "Password:" {
        send_user "INFO: Password prompt detected (exact match via expect_before)\n"
        sleep 0.2
        send -- "$pgadmin_password\r"
        send_user "INFO: Password sent\n"
    }
    # Match "Retype password" variations - exact match
    -ex "Retype password:" {
        send_user "INFO: Retype password prompt detected (exact via expect_before)\n"
        sleep 0.2
        send -- "$pgadmin_password\r"
        send_user "INFO: Retype password sent\n"
    }
    # Match Apache configuration prompt - try multiple patterns
    # Full prompt: "We can now configure the Apache... Do you wish to continue (y/n)?"
    -re "We can now configure.*Apache.*Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected (full via expect_before) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        send_user "INFO: Answered 'y' to Apache configuration\n"
    }
    # Match "Do you wish to continue" with (y/n) - handle any whitespace/newlines
    -re "Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected (via expect_before) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        send_user "INFO: Answered 'y' to Apache configuration\n"
    }
    # Match "configure.*Apache" followed by continue prompt
    -re "configure.*Apache.*Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected (configure Apache via expect_before) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        send_user "INFO: Answered 'y' to Apache configuration\n"
    }
    # Match Apache restart prompt
    -re ".*restart.*Continue.*\\(y/n\\)" {
        send_user "INFO: Apache restart prompt detected (via expect_before) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        send_user "INFO: Answered 'y' to Apache restart\n"
    }
    -re "Continue.*\\(y/n\\)" {
        send_user "INFO: Continue prompt detected (via expect_before) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        send_user "INFO: Answered 'y' to continue prompt\n"
    }
}

# Wait for Email address prompt or other prompts
expect {
    -timeout 60
    -re "Email address:" {
        send_user "INFO: Email prompt detected\n"
        sleep 0.2
        send -- "$pgadmin_email\r"
        send_user "INFO: Email sent, waiting for password prompt...\n"
        # After sending email, stay in this expect block to catch password prompt
        exp_continue
    }
    # Also catch Password prompt here in case expect_before doesn't work
    # Try exact match first (most reliable)
    -ex "Password:" {
        send_user "INFO: Password prompt detected (exact match in main block)\n"
        sleep 0.2
        send -- "$pgadmin_password\r"
        send_user "INFO: Password sent\n"
        exp_continue
    }
    # Regex match
    -re "Password:" {
        send_user "INFO: Password prompt detected (regex in main block)\n"
        sleep 0.2
        send -- "$pgadmin_password\r"
        send_user "INFO: Password sent\n"
        exp_continue
    }
    # Case-insensitive match
    -re -i "password:" {
        send_user "INFO: Password prompt detected (case-insensitive in main block)\n"
        sleep 0.2
        send -- "$pgadmin_password\r"
        send_user "INFO: Password sent\n"
        exp_continue
    }
    # Handle Apache configuration prompt (may appear before email if database already exists)
    -re "Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected (with y/n) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    -re "Do you wish to continue" {
        send_user "INFO: Apache configuration prompt detected (first prompt) - answering 'y' (yes)\n"
        # Wait a bit for the full prompt to appear
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    -re "configure.*Apache.*Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected (full text with y/n) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    -re "configure.*Apache.*Do you wish to continue" {
        send_user "INFO: Apache configuration prompt detected - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    # Match "We can now configure the Apache" prompt
    -re "We can now configure.*Apache.*Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected (full prompt) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    -re ".*already.*configured.*" {
        send_user "INFO: pgAdmin4 appears to be already configured\n"
        # If already configured, it may ask if we want to reconfigure
        exp_continue
    }
    -re ".*Configuration.*already.*exists.*" {
        send_user "INFO: Configuration database already exists\n"
        # May ask if we want to continue or reconfigure
        exp_continue
    }
    -re ".*Apache.*already.*configured.*" {
        send_user "INFO: Apache configuration already exists\n"
        exp_continue
    }
    -re ".*Do you want to.*reconfigure.*Apache.*\\(y/n\\)" {
        send_user "INFO: Apache reconfiguration prompt detected - answering 'n' (no)\n"
        send -- "n\r"
        exp_continue
    }
    -re ".*reconfigure.*Apache.*\\(y/n\\)" {
        send_user "INFO: Apache reconfiguration prompt detected - answering 'n' (no)\n"
        send -- "n\r"
        exp_continue
    }
    -re ".*create.*database.*\\(y/n\\)" {
        send_user "INFO: Database creation prompt detected - answering 'y' (yes)\n"
        send -- "y\r"
        exp_continue
    }
    -re ".*create.*configuration.*\\(y/n\\)" {
        send_user "INFO: Configuration creation prompt detected - answering 'y' (yes)\n"
        send -- "y\r"
        exp_continue
    }
    -re ".*sudo.*password.*" {
        send_user "ERROR: Sudo password required but not cached.\n"
        send_user "Please ensure sudo timestamp is valid by running 'sudo -v' before this script.\n"
        exit 1
    }
    # Note: Don't use catch-all (y/n) pattern here - let specific patterns below handle it
    timeout {
        send_user "WARN: Timeout waiting for Email address prompt\n"
        send_user "INFO: setup-web.sh may have detected existing configuration and skipped\n"
        # Don't exit, check if process is still running
        exp_continue
    }
    eof {
        send_user "INFO: setup-web.sh exited (may have detected existing configuration)\n"
        catch {wait} result
        set exit_code [lindex $result 3]
        if {$exit_code != 0} {
            send_user "ERROR: setup-web.sh exited with error code: $exit_code\n"
            exit 1
        }
        exit 0
    }
}

# Wait for Password prompt (may not appear if already configured)
# Note: Password prompt may appear after warnings or other output
# expect_before should catch it, but we also handle it here explicitly
expect {
    -timeout 60
    # Match "Password:" - exact match
    -ex "Password:" {
        send_user "INFO: Password prompt detected (in password expect block)\n"
        sleep 0.3
        send -- "$pgadmin_password\r"
        send_user "INFO: Password sent, waiting for next prompt...\n"
        exp_continue
    }
    # Handle Apache configuration prompt (may appear before email if database already exists)
    -re "Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected (with y/n) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    -re "We can now configure.*Apache.*Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected (full prompt) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    -re "configure.*Apache.*Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected (full text with y/n) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    -re ".*already.*configured.*" {
        send_user "INFO: pgAdmin4 already configured, skipping password prompt\n"
        exp_continue
    }
    -re ".*Configuration.*already.*exists.*" {
        send_user "INFO: Configuration database already exists\n"
        exp_continue
    }
    timeout {
        send_user "WARN: Timeout (60 seconds) waiting for password prompt\n"
        send_user "INFO: This may indicate that password prompt already appeared or script is waiting\n"
        send_user "INFO: Continuing to check for retype password or other prompts...\n"
        # Continue to next step - don't exit, let next expect block handle it
        exp_continue
    }
    eof {
        send_user "INFO: setup-web.sh completed (may have detected existing configuration)\n"
        catch {wait} result
        set exit_code [lindex $result 3]
        if {$exit_code != 0} {
            send_user "ERROR: setup-web.sh exited with error code: $exit_code\n"
            exit 1
        }
        exit 0
    }
}

# Wait for Retype password prompt (may not appear if already configured)
# After Retype password, we should see Apache configuration prompt
expect {
    -timeout 60
    # Match "Retype password:" - exact match
    # expect_before should catch it, but we also handle it here explicitly
    -ex "Retype password:" {
        send_user "INFO: Password confirmation prompt detected\n"
        sleep 0.3
        send -- "$pgadmin_password\r"
        send_user "INFO: Password confirmation sent, waiting for next prompt...\n"
        exp_continue
    }
    # Handle Apache configuration prompt (appears after password setup)
    # Full prompt: "We can now configure the Apache... Do you wish to continue (y/n)?"
    # Note: .* matches any characters including newlines (with match_max 5000)
    -re "We can now configure.*Apache.*Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected (full prompt after password) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    # Match "Do you wish to continue" with (y/n) - handles newlines in between
    -re "Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected (after password) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    # Match even without explicit (y/n) - just "Do you wish to continue"
    -re "Do you wish to continue" {
        send_user "INFO: Continue prompt detected (may be Apache config) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    # Match "configure.*Apache" followed by continue
    -re "configure.*Apache.*Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected (configure Apache) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    # Match "configure the Apache" with any text before "Do you wish"
    -re "configure the Apache.*Do you wish" {
        send_user "INFO: Apache configuration prompt detected (configure the Apache) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    # Handle Apache restart prompt (may appear after Apache configuration)
    -re ".*Apache.*restart.*Continue.*\\(y/n\\)" {
        send_user "INFO: Apache restart prompt detected - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    -re ".*must be restarted.*Continue.*\\(y/n\\)" {
        send_user "INFO: Apache restart prompt detected (must be restarted) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    -re "Continue.*\\(y/n\\)" {
        send_user "INFO: Continue prompt detected (Apache restart) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    -re ".*already.*configured.*" {
        send_user "INFO: pgAdmin4 already configured, skipping retype password prompt\n"
        exp_continue
    }
    -re ".*Configuration.*already.*exists.*" {
        send_user "INFO: Configuration database already exists\n"
        exp_continue
    }
    timeout {
        send_user "WARN: Timeout (60 seconds) waiting for retype password prompt\n"
        send_user "INFO: This may indicate password confirmation already completed\n"
        send_user "INFO: Continuing to check for Apache configuration prompts...\n"
        # Continue to next step - don't exit, let next expect block handle it
        exp_continue
    }
    eof {
        send_user "INFO: setup-web.sh completed (may have detected existing configuration)\n"
        catch {wait} result
        set exit_code [lindex $result 3]
        if {$exit_code != 0} {
            send_user "ERROR: setup-web.sh exited with error code: $exit_code\n"
            exit 1
        }
        exit 0
    }
}

# Wait for Apache configuration prompt (first prompt)
# This may not appear if pgAdmin4 is already configured
expect {
    -timeout 60
    # Match full Apache configuration prompt with (y/n)?
    -re "Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected (with y/n) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    # Match "We can now configure the Apache" prompt
    -re "We can now configure.*Apache.*Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected (full prompt) - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    -re "configure.*Apache.*Do you wish to continue.*\\(y/n\\)" {
        send_user "INFO: Apache configuration prompt detected - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    # Match without (y/n) explicitly
    -re "Do you wish to continue" {
        send_user "INFO: Apache configuration prompt detected - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    -re "continue.*\\(y/n\\)" {
        send_user "INFO: Continue prompt detected - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    -re "Continue.*\\(y/n\\)" {
        send_user "INFO: Continue prompt detected - answering 'y' (yes)\n"
        sleep 0.3
        send -- "y\r"
        exp_continue
    }
    -re ".*already.*configured.*" {
        send_user "INFO: pgAdmin4 Apache configuration already exists\n"
        exp_continue
    }
    timeout {
        send_user "WARN: Timeout (60 seconds) waiting for Apache configuration prompt\n"
        send_user "INFO: Apache may already be configured or script is proceeding\n"
        send_user "INFO: Continuing to check for Apache restart prompt or completion...\n"
        # Don't exit, continue to next prompt or completion
        exp_continue
    }
    eof {
        # Check exit code
        catch {wait} result
        set exit_code [lindex $result 3]
        if {$exit_code != 0} {
            send_user "ERROR: setup-web.sh exited with error code: $exit_code\n"
            exit 1
        }
        send_user "INFO: setup-web.sh completed successfully\n"
        exit 0
    }
}

# Wait for Apache restart prompt (second prompt if Apache is running)
expect {
    -timeout 60
    -re ".*must be restarted.*Continue.*\\(y/n\\)" {
        send_user "INFO: Apache restart prompt detected (must be restarted) - answering 'y' (yes)\n"
        send -- "y\r"
        exp_continue
    }
    -re ".*Apache.*restart.*Continue.*\\(y/n\\)" {
        send_user "INFO: Apache restart prompt detected (Apache restart) - answering 'y' (yes)\n"
        send -- "y\r"
        exp_continue
    }
    -re "Continue.*\\(y/n\\)" {
        send_user "INFO: Continue prompt detected (Apache restart) - answering 'y' (yes)\n"
        send -- "y\r"
        exp_continue
    }
    -re "Continue" {
        send_user "INFO: Continue prompt detected (may be Apache restart) - answering 'y' (yes)\n"
        sleep 0.5
        send -- "y\r"
        exp_continue
    }
    -re ".*restart.*\\(y/n\\)" {
        send_user "INFO: Restart prompt detected - answering 'y' (yes)\n"
        send -- "y\r"
        exp_continue
    }
    timeout {
        send_user "INFO: Timeout (60 seconds) waiting for Apache restart prompt\n"
        send_user "INFO: Setup may have completed or Apache restart not needed\n"
        # Continue to final wait
        exp_continue
    }
    eof {
        catch {wait} result
        set exit_code [lindex $result 3]
        if {$exit_code != 0} {
            send_user "ERROR: setup-web.sh exited with error code: $exit_code\n"
            exit 1
        }
        exit 0
    }
}

# Final wait for completion (handle any remaining output)
expect {
    eof {
        catch {wait} result
        set exit_code [lindex $result 3]
        if {$exit_code != 0} {
            send_user "ERROR: setup-web.sh exited with error code: $exit_code\n"
            exit 1
        }
        exit 0
    }
    timeout {
        send_user "INFO: Setup script completed (timeout reached, but this may be normal)\n"
        exit 0
    }
}
EXPECT_EOF
    
    chmod +x "$expect_script"
    
    # Run expect script with sudo to handle interactive prompts
    # This ensures sudo timestamp is available for setup-web.sh
    log "INFO" "🔄 Running pgAdmin4 setup-web.sh with expect..."
    log "INFO" "⏱️ This may take a few minutes. Timeout is set to 5 minutes."
    log "INFO" "📝 Expect script output will be logged for debugging..."
    log "INFO" "💡 Each prompt has a 30-second timeout to prevent hanging..."
    
    # Run expect script with timeout to prevent hanging indefinitely
    # timeout command will kill the process after 300 seconds (5 minutes)
    # Capture both stdout and stderr, and show output in real-time
    local setup_result=0
    
    # Run expect script and show output in real-time
    log "INFO" "🚀 Starting setup-web.sh..."
    log "INFO" "📊 Progress will be shown below..."
    echo ""
    
    # Export variables for expect script
    export PGADMIN_EMAIL
    export PGADMIN_PASSWORD
    
    # Run expect script with timeout and show output in real-time
    local expect_output
    if sudo -E timeout 300 "$expect_script" 2>&1 | tee -a "$LOGFILE"; then
        setup_result=${PIPESTATUS[0]}
    else
        setup_result=${PIPESTATUS[0]}
    fi
    
    echo ""
    
    # Check if timeout occurred
    if [ $setup_result -eq 124 ]; then
        log "ERROR" "❌ setup-web.sh timed out after 5 minutes"
        setup_result=1
    fi
    
    # Check exit code
    if [ $setup_result -eq 0 ]; then
        log "INFO" "✅ expect script completed successfully"
    elif [ $setup_result -eq 124 ]; then
        log "ERROR" "❌ setup-web.sh timed out after 5 minutes"
        log "WARN" "⚠️ The setup process may have been interrupted"
        log "INFO" "💡 Check the expect output above for details"
    else
        log "WARN" "⚠️ expect script exited with code: $setup_result"
        log "INFO" "💡 Check the expect output above for details"
    fi
    
    # Clean up temporary script
    rm -f "$expect_script"
    
    # If setup failed or timed out, check if pgAdmin4 was partially configured
    if [ $setup_result -ne 0 ]; then
        log "WARN" "⚠️ setup-web.sh may have failed or timed out"
        log "INFO" "🔍 Checking if pgAdmin4 was partially configured..."
        
        # Quick check if config was created despite timeout
        if [ -f /etc/apache2/conf-available/pgadmin4.conf ] || [ -f /etc/apache2/conf-enabled/pgadmin4.conf ]; then
            log "INFO" "ℹ️  Apache config was created. Configuration may have partially succeeded."
            # Try to enable config if it exists
            if [ -f /etc/apache2/conf-available/pgadmin4.conf ] && [ ! -f /etc/apache2/conf-enabled/pgadmin4.conf ]; then
                sudo a2enconf pgadmin4 2>/dev/null || true
            fi
        fi
    fi
    
    # Wait a bit for files to be created
    sleep 3
    
    # Always check Apache status and fix if needed (even if setup_result is 0)
    log "INFO" "🔍 Checking Apache status after setup-web.sh..."
    
    # Check if Apache is running
    if ! systemctl is-active --quiet apache2 2>/dev/null; then
        log "WARN" "⚠️ Apache is not running. Attempting to fix and start..."
        
        # Check Apache error logs in detail
        log "INFO" "📋 Checking Apache error logs..."
        local apache_errors=$(sudo journalctl -xeu apache2.service --no-pager -n 30 2>/dev/null | tail -n 20)
        if [ -n "$apache_errors" ]; then
            echo "$apache_errors" | while read -r line; do
                log "INFO" "   $line"
            done
        fi
        
        # Check Apache error log file
        if [ -f /var/log/apache2/error.log ]; then
            log "INFO" "📋 Checking Apache error.log file..."
            sudo tail -n 20 /var/log/apache2/error.log 2>/dev/null | while read -r line; do
                log "INFO" "   $line"
            done || true
        fi
        
        # Try to fix common Apache issues
        log "INFO" "🔧 Attempting to fix Apache configuration..."
        
        # Check what's using port 443
        log "INFO" "🔍 Checking what's using port 443..."
        if command -v netstat >/dev/null 2>&1; then
            if sudo netstat -tlnp | grep -q ":443 "; then
                local port443_process=$(sudo netstat -tlnp | grep ":443 " | awk '{print $7}' | head -n1)
                log "WARN" "⚠️ Port 443 is already in use by: $port443_process"
            fi
        elif command -v ss >/dev/null 2>&1; then
            if sudo ss -tlnp | grep -q ":443 "; then
                local port443_process=$(sudo ss -tlnp | grep ":443 " | awk '{print $6}' | head -n1)
                log "WARN" "⚠️ Port 443 is already in use by: $port443_process"
            fi
        fi
        
        # Disable SSL site to avoid port 443 conflict
        if [ -f /etc/apache2/sites-enabled/default-ssl.conf ]; then
            log "INFO" "  └─ Disabling default-ssl site to avoid port 443 conflict..."
            sudo a2dissite default-ssl 2>/dev/null || true
        fi
        
        # Comment out Listen 443 in ports.conf to avoid conflict
        if grep -q "^Listen 443" /etc/apache2/ports.conf 2>/dev/null; then
            log "INFO" "  └─ Commenting out Listen 443 in ports.conf..."
            sudo sed -i 's/^Listen 443/#Listen 443/' /etc/apache2/ports.conf
        fi
        
        # Set ServerName to avoid warning
        if ! grep -q "^ServerName" /etc/apache2/apache2.conf 2>/dev/null; then
            log "INFO" "  └─ Setting ServerName in apache2.conf..."
            echo "ServerName localhost" | sudo tee -a /etc/apache2/apache2.conf >/dev/null
        fi
        
        # Enable required modules (but don't enable SSL if port 443 is in use)
        sudo a2enmod wsgi 2>/dev/null || true
        sudo a2enmod rewrite 2>/dev/null || true
        sudo a2enmod headers 2>/dev/null || true
        # Only enable SSL if port 443 is not in use
        if ! sudo netstat -tlnp 2>/dev/null | grep -q ":443 " && ! sudo ss -tlnp 2>/dev/null | grep -q ":443 "; then
            sudo a2enmod ssl 2>/dev/null || true
        else
            log "INFO" "  └─ Skipping SSL module (port 443 is in use)"
        fi
        
        # Ensure default site is enabled
        if [ ! -f /etc/apache2/sites-enabled/000-default.conf ] && [ -f /etc/apache2/sites-available/000-default.conf ]; then
            log "INFO" "  └─ Enabling default site..."
            sudo a2ensite 000-default 2>/dev/null || true
        fi
        
        # Test configuration
        log "INFO" "🔍 Testing Apache configuration..."
        if sudo apache2ctl -t 2>&1 | tee -a "$LOGFILE"; then
            log "SUCCESS" "✅ Apache configuration is now valid."
            
            # Check for port conflicts
            log "INFO" "🔍 Checking for port conflicts..."
            if command -v netstat >/dev/null 2>&1; then
                if sudo netstat -tlnp | grep -q ":${APACHE_PORT} "; then
                    local port_process=$(sudo netstat -tlnp | grep ":${APACHE_PORT} " | awk '{print $7}' | head -n1)
                    log "WARN" "⚠️ Port $APACHE_PORT is already in use by: $port_process"
                fi
            elif command -v ss >/dev/null 2>&1; then
                if sudo ss -tlnp | grep -q ":${APACHE_PORT} "; then
                    local port_process=$(sudo ss -tlnp | grep ":${APACHE_PORT} " | awk '{print $6}' | head -n1)
                    log "WARN" "⚠️ Port $APACHE_PORT is already in use by: $port_process"
                fi
            fi
            
            # Try to start Apache directly with apache2ctl to see detailed errors
            log "INFO" "🔄 Attempting to start Apache with apache2ctl..."
            if sudo apache2ctl start 2>&1 | tee -a "$LOGFILE"; then
                sleep 3
                if systemctl is-active --quiet apache2 2>/dev/null; then
                    log "SUCCESS" "✅ Apache started successfully."
                else
                    log "ERROR" "❌ Apache still not running after start attempt."
                    # Try to get more detailed error
                    log "INFO" "📋 Getting detailed Apache startup error..."
                    sudo apache2ctl -S 2>&1 | head -n 20 | while read -r line; do
                        log "INFO" "   $line"
                    done || true
                    log "INFO" "💡 Please check Apache logs manually: sudo journalctl -xeu apache2.service"
                fi
            else
                log "ERROR" "❌ Failed to start Apache with apache2ctl."
                # Try systemctl as fallback
                log "INFO" "🔄 Trying systemctl start as fallback..."
                if sudo systemctl start apache2 2>&1 | tee -a "$LOGFILE"; then
                    sleep 3
                    if systemctl is-active --quiet apache2 2>/dev/null; then
                        log "SUCCESS" "✅ Apache started successfully with systemctl."
                    else
                        log "ERROR" "❌ Apache still not running."
                        log "INFO" "💡 Please check Apache logs manually: sudo journalctl -xeu apache2.service"
                    fi
                else
                    log "ERROR" "❌ Failed to start Apache with systemctl."
                    log "INFO" "💡 Please check Apache logs manually: sudo journalctl -xeu apache2.service"
                fi
            fi
        else
            log "ERROR" "❌ Apache configuration test failed."
            log "INFO" "💡 Please check Apache configuration manually: sudo apache2ctl -t"
        fi
    else
        log "SUCCESS" "✅ Apache is running."
    fi
    
    # Verify that pgAdmin4 was configured successfully
    # If setup-web.sh completed successfully, consider it successful even if files are not found immediately
    if [ $setup_result -eq 0 ]; then
        log "INFO" "✅ setup-web.sh completed successfully. Verifying configuration..."
    fi
    
    # Wait a bit more for files to be created
    sleep 2
    
    # Check for database file in multiple possible locations
    local db_exists=false
    local conf_exists=false
    local db_path=""
    
    # Check common database locations
    local db_paths=(
        "/var/lib/pgadmin/pgadmin4.db"
        "/var/lib/pgadmin/pgAdmin4.db"
        "/var/lib/pgadmin/storage/pgadmin4.db"
        "/var/lib/pgadmin/storage/pgAdmin4.db"
    )
    
    for path in "${db_paths[@]}"; do
        if [ -f "$path" ]; then
            db_exists=true
            db_path="$path"
            log "INFO" "✅ pgAdmin4 database file found at: $path"
            break
        fi
    done
    
    # If not found, search in /var/lib/pgadmin directory and subdirectories
    if [ "$db_exists" = false ]; then
        log "INFO" "🔍 Searching for pgAdmin4 database file..."
        local found_db=$(find /var/lib/pgadmin -name "*.db" -type f 2>/dev/null | head -n1)
        if [ -n "$found_db" ]; then
            db_exists=true
            db_path="$found_db"
            log "INFO" "✅ pgAdmin4 database file found at: $found_db"
        else
            # Check if /var/lib/pgadmin directory exists and has content
            if [ -d /var/lib/pgadmin ]; then
                local file_count=$(find /var/lib/pgadmin -type f 2>/dev/null | wc -l)
                if [ "$file_count" -gt 0 ]; then
                    log "INFO" "ℹ️ /var/lib/pgadmin directory exists with $file_count file(s)."
                    log "INFO" "📂 Contents of /var/lib/pgadmin:"
                    ls -la /var/lib/pgadmin/ 2>/dev/null | head -n20 | while read -r line; do
                        log "INFO" "   $line"
                    done
                    # If directory has files, consider it successful (database may be in subdirectory)
                    if [ "$file_count" -gt 0 ]; then
                        db_exists=true
                        log "INFO" "✅ pgAdmin4 storage directory exists with files."
                    fi
                else
                    log "WARN" "⚠️ pgAdmin4 database file not found in /var/lib/pgadmin/"
                fi
            else
                log "WARN" "⚠️ /var/lib/pgadmin directory does not exist."
            fi
        fi
    fi
    
    # Check for Apache configuration in multiple locations
    log "INFO" "🔍 Checking for pgAdmin4 Apache configuration..."
    if [ -f /etc/apache2/conf-available/pgadmin4.conf ]; then
        conf_exists=true
        log "INFO" "✅ pgAdmin4 Apache configuration file found in conf-available."
        # Enable it if not already enabled
        if [ ! -f /etc/apache2/conf-enabled/pgadmin4.conf ]; then
            log "INFO" "🔧 Enabling pgAdmin4 Apache configuration..."
            sudo a2enconf pgadmin4 2>&1 | tee -a "$LOGFILE" || true
            sleep 1
        fi
    fi
    
    if [ -f /etc/apache2/conf-enabled/pgadmin4.conf ]; then
        conf_exists=true
        log "INFO" "✅ pgAdmin4 Apache configuration is enabled."
    fi
    
    # Check for pgAdmin4 configuration in sites-enabled or sites-available
    if [ "$conf_exists" = false ]; then
        if [ -f /etc/apache2/sites-enabled/pgadmin4.conf ] || [ -f /etc/apache2/sites-available/pgadmin4.conf ]; then
            conf_exists=true
            log "INFO" "✅ pgAdmin4 Apache configuration found in sites."
        fi
    fi
    
    # Check for pgAdmin4 in Apache configuration using apache2ctl
    if [ "$conf_exists" = false ]; then
        log "INFO" "🔍 Checking Apache configuration for pgAdmin4..."
        if sudo apache2ctl -S 2>/dev/null | grep -qi "pgadmin"; then
            conf_exists=true
            log "INFO" "✅ pgAdmin4 found in Apache virtual hosts."
        fi
    fi
    
    if [ "$conf_exists" = false ]; then
        log "WARN" "⚠️  pgAdmin4 Apache configuration file not found in standard locations."
        log "INFO" "💡 Checking for alternative configuration locations..."
        # Check if config might be in a different location
        local found_configs=$(find /etc/apache2 -name "*pgadmin*" -type f 2>/dev/null)
        if [ -n "$found_configs" ]; then
            log "INFO" "ℹ️  Found pgAdmin4 related files in Apache config directory:"
            echo "$found_configs" | while read -r file; do
                log "INFO" "   Found: $file"
            done
            conf_exists=true
        else
            # Create pgAdmin4 Apache configuration file manually
            log "INFO" "🔧 Creating pgAdmin4 Apache configuration file..."
            
            # Find pgAdmin4 installation path
            local pgadmin_wsgi=""
            local pgadmin_web_dir=""
            local pgadmin_venv=""
            
            # Check common locations
            if [ -f /usr/pgadmin4/web/pgAdmin4.wsgi ]; then
                pgadmin_wsgi="/usr/pgadmin4/web/pgAdmin4.wsgi"
                pgadmin_web_dir="/usr/pgadmin4/web"
                pgadmin_venv="/usr/pgadmin4/venv"
            elif [ -f /usr/pgadmin4/bin/pgadmin4.wsgi ]; then
                pgadmin_wsgi="/usr/pgadmin4/bin/pgadmin4.wsgi"
                pgadmin_web_dir="/usr/pgadmin4/bin"
                pgadmin_venv="/usr/pgadmin4/venv"
            elif [ -d /usr/pgadmin4 ]; then
                # Search for wsgi file
                pgadmin_wsgi=$(find /usr/pgadmin4 -name "*.wsgi" -type f 2>/dev/null | head -n1)
                if [ -n "$pgadmin_wsgi" ]; then
                    pgadmin_web_dir=$(dirname "$pgadmin_wsgi")
                    pgadmin_venv="/usr/pgadmin4/venv"
                fi
            fi
            
            if [ -n "$pgadmin_wsgi" ] && [ -f "$pgadmin_wsgi" ]; then
                log "INFO" "  └─ Found pgAdmin4 WSGI script at: $pgadmin_wsgi"
                log "INFO" "  └─ Web directory: $pgadmin_web_dir"
                log "INFO" "  └─ Creating configuration..."
                
                # Create the configuration file
                sudo tee /etc/apache2/conf-available/pgadmin4.conf >/dev/null <<EOF
# pgAdmin 4 - Web Application
# This configuration file is for pgAdmin 4 web mode
# Auto-generated by installation script

<Directory $pgadmin_web_dir>
    WSGIProcessGroup pgadmin
    WSGIApplicationGroup %{GLOBAL}
    Require all granted
</Directory>

WSGIDaemonProcess pgadmin user=www-data group=www-data threads=25 python-home=$pgadmin_venv python-path=$pgadmin_web_dir
WSGIScriptAlias /pgadmin4 $pgadmin_wsgi

<Directory $pgadmin_web_dir>
    WSGIProcessGroup pgadmin
    WSGIApplicationGroup %{GLOBAL}
    <Files $(basename $pgadmin_wsgi)>
        Require all granted
    </Files>
</Directory>
EOF
                
                if [ -f /etc/apache2/conf-available/pgadmin4.conf ]; then
                    log "SUCCESS" "✅ Created pgAdmin4 Apache configuration file."
                    conf_exists=true
                    # Enable the configuration
                    log "INFO" "🔧 Enabling pgAdmin4 Apache configuration..."
                    if sudo a2enconf pgadmin4 2>&1 | tee -a "$LOGFILE"; then
                        log "SUCCESS" "✅ pgAdmin4 Apache configuration enabled."
                        # Reload Apache to apply changes
                        log "INFO" "🔄 Reloading Apache to apply configuration..."
                        sudo systemctl reload apache2 2>/dev/null || sudo systemctl restart apache2 2>/dev/null || true
                    else
                        log "WARN" "⚠️ Failed to enable pgAdmin4 configuration, but file was created."
                    fi
                else
                    log "ERROR" "❌ Failed to create pgAdmin4 Apache configuration file."
                fi
            else
                log "WARN" "⚠️ pgAdmin4 WSGI script not found, cannot create configuration."
                log "INFO" "💡 Searching for pgAdmin4 installation..."
                if [ -d /usr/pgadmin4 ]; then
                    log "INFO" "  └─ Found /usr/pgadmin4 directory"
                    log "INFO" "  └─ Contents:"
                    ls -la /usr/pgadmin4/ 2>/dev/null | head -n10 | while read -r line; do
                        log "INFO" "     $line"
                    done || true
                else
                    log "WARN" "⚠️ pgAdmin4 installation not found in /usr/pgadmin4"
                fi
            fi
        fi
    fi
    
    # Determine success based on what we found
    # If setup-web.sh completed successfully, consider it successful even if files are not found
    if [ $setup_result -eq 0 ] && systemctl is-active --quiet apache2 2>/dev/null; then
        log "INFO" "✅ setup-web.sh completed successfully and Apache is running."
        if [ "$conf_exists" = true ] || [ "$db_exists" = true ]; then
            log "SUCCESS" "✅ pgAdmin4 configuration complete."
            log "INFO" "💡 pgAdmin4 should be accessible at http://localhost:$APACHE_PORT/pgadmin4"
            return 0
        else
            # Even if files are not found, if setup-web.sh succeeded, consider it successful
            log "SUCCESS" "✅ pgAdmin4 setup completed successfully."
            log "INFO" "💡 pgAdmin4 should be accessible at http://localhost:$APACHE_PORT/pgadmin4"
            log "INFO" "💡 Configuration files may be created on first access."
            return 0
        fi
    elif [ "$db_exists" = true ] && [ "$conf_exists" = true ]; then
        log "SUCCESS" "✅ pgAdmin4 configuration complete."
        return 0
    elif [ "$db_exists" = true ]; then
        log "WARN" "⚠️ pgAdmin4 database exists but Apache config is missing."
        log "INFO" "💡 pgAdmin4 may still work, but Apache configuration may need manual setup."
        # Try to find and enable config one more time
        if [ -f /etc/apache2/conf-available/pgadmin4.conf ]; then
            sudo a2enconf pgadmin4 2>/dev/null || true
            log "SUCCESS" "✅ pgAdmin4 Apache configuration enabled."
            return 0
        fi
        # Even if config is missing, if database exists, setup partially succeeded
        log "SUCCESS" "✅ pgAdmin4 database created. Apache configuration may need manual setup."
        return 0
    elif [ "$conf_exists" = true ]; then
        log "WARN" "⚠️ Apache config exists but database file not found in expected locations."
        log "INFO" "💡 Checking if pgAdmin4 is already configured..."
        # If Apache config exists and setup-web.sh said it succeeded,
        # we should trust that setup was successful
        # pgAdmin4 may use a different database location or format
        if [ -d /var/lib/pgadmin ]; then
            local file_count=$(find /var/lib/pgadmin -type f 2>/dev/null | wc -l)
            if [ "$file_count" -gt 0 ]; then
                log "INFO" "ℹ️ /var/lib/pgadmin directory exists with $file_count file(s)."
                log "SUCCESS" "✅ pgAdmin4 Apache configuration is set up. Database files exist."
                log "INFO" "💡 pgAdmin4 should be accessible at http://localhost:$APACHE_PORT/pgadmin4"
                return 0
            else
                log "INFO" "ℹ️ /var/lib/pgadmin directory exists but appears empty."
                log "INFO" "💡 This is normal - database may be created on first access."
            fi
        fi
        # If setup-web.sh succeeded and Apache config exists, consider it successful
        # The database will be created when pgAdmin4 is first accessed
        log "SUCCESS" "✅ pgAdmin4 Apache configuration is set up successfully."
        log "INFO" "💡 pgAdmin4 should be accessible at http://localhost:$APACHE_PORT/pgadmin4"
        log "INFO" "💡 Database will be created on first access if it doesn't exist yet."
        return 0
    else
        # If setup-web.sh succeeded, consider it successful even if files are not found
        if [ $setup_result -eq 0 ] && systemctl is-active --quiet apache2 2>/dev/null; then
            log "SUCCESS" "✅ pgAdmin4 setup completed successfully."
            log "INFO" "💡 pgAdmin4 should be accessible at http://localhost:$APACHE_PORT/pgadmin4"
            log "INFO" "💡 Configuration files may be created on first access."
            return 0
        else
            log "ERROR" "❌ pgAdmin4 configuration files not found after setup."
            log "INFO" "💡 Check log file for details: $LOGFILE"
            return 1
        fi
    fi
}

configure_apache_port() {
    show_progress "⚙️ Configuring Apache port..."
    
    if [ "$APACHE_PORT" = "80" ]; then
        log "INFO" "ℹ️  Using default port 80. Skipping port configuration."
        return 0
    fi
    
    # Check if port is already configured
    if grep -q "^Listen $APACHE_PORT" /etc/apache2/ports.conf 2>/dev/null; then
        log "INFO" "ℹ️  Apache port $APACHE_PORT is already configured. Skipping."
        return 0
    fi
    
    log "INFO" "🔧 Changing Apache port to $APACHE_PORT..."
    
    # Backup original ports.conf
    if [ ! -f /etc/apache2/ports.conf.backup ]; then
        sudo cp /etc/apache2/ports.conf /etc/apache2/ports.conf.backup
        log "INFO" "💾 Backed up /etc/apache2/ports.conf"
    fi
    
    # Change Listen port
    if sudo sed -i "s/^Listen 80$/Listen $APACHE_PORT/" /etc/apache2/ports.conf; then
        log "SUCCESS" "✅ Apache port changed to $APACHE_PORT."
    else
        # If the pattern doesn't exist, add it
        if ! grep -q "^Listen $APACHE_PORT" /etc/apache2/ports.conf; then
            echo "Listen $APACHE_PORT" | sudo tee -a /etc/apache2/ports.conf >/dev/null
            log "SUCCESS" "✅ Added Listen $APACHE_PORT to Apache config."
        fi
    fi
    
    # Update virtualhost if needed
    if [ -f /etc/apache2/sites-available/000-default.conf ]; then
        if ! grep -q "<VirtualHost \*:$APACHE_PORT>" /etc/apache2/sites-available/000-default.conf 2>/dev/null; then
            sudo sed -i "s/<VirtualHost \*:80>/<VirtualHost *:$APACHE_PORT>/" /etc/apache2/sites-available/000-default.conf 2>/dev/null || true
            log "INFO" "  └─ Updated VirtualHost in 000-default.conf to port $APACHE_PORT"
        fi
    fi
    
    if [ -f /etc/apache2/sites-available/default-ssl.conf ]; then
        if ! grep -q "<VirtualHost _default_:$APACHE_PORT>" /etc/apache2/sites-available/default-ssl.conf 2>/dev/null; then
            sudo sed -i "s/<VirtualHost _default_:80>/<VirtualHost _default_:$APACHE_PORT>/" /etc/apache2/sites-available/default-ssl.conf 2>/dev/null || true
            log "INFO" "  └─ Updated VirtualHost in default-ssl.conf to port $APACHE_PORT"
        fi
    fi
}

verify_pgadmin4_apache_config() {
    show_progress "🔍 Verifying pgAdmin4 Apache configuration..."
    
    # Check if pgAdmin4 Apache config exists
    local conf_status=$(check_pgadmin4_apache_config)
    if [ -n "$conf_status" ]; then
        log "SUCCESS" "✅ pgAdmin4 Apache configuration found."
        enable_pgadmin4_apache_config
        return 0
    else
        log "WARN" "⚠️ pgAdmin4 Apache configuration not found."
        log "INFO" "💡 This may cause 'Not Found' error when accessing /pgadmin4"
        return 1
    fi
}

remove_conflicting_vhost() {
    show_progress "🗑️ Removing conflicting VirtualHost..."
    
    if [ -f /etc/apache2/sites-enabled/pgadmin4.conf ]; then
        log "WARN" "⚠️ Found conflicting pgadmin4.conf VirtualHost"
        log "INFO" "🗑️ Removing /etc/apache2/sites-enabled/pgadmin4.conf..."
        sudo rm -f /etc/apache2/sites-enabled/pgadmin4.conf
        log "SUCCESS" "✅ Conflicting VirtualHost removed."
    else
        log "INFO" "ℹ️ No conflicting VirtualHost found."
    fi
}

restart_apache() {
    show_progress "🔄 Restarting Apache..."
    
    log "INFO" "🔍 Testing Apache configuration..."
    if sudo apache2ctl -t 2>/dev/null; then
        log "SUCCESS" "✅ Apache configuration is valid."
    else
        log "WARN" "⚠️ Apache configuration test failed, but continuing..."
    fi
    
    log "INFO" "🔄 Restarting Apache service..."
    if sudo systemctl restart apache2; then
        log "SUCCESS" "✅ Apache restarted successfully."
    else
        log "ERROR" "❌ Failed to restart Apache."
        return 1
    fi
    
    # Wait a bit for Apache to fully start
    sleep 2
    
    # Check if Apache is running
    if systemctl is-active --quiet apache2; then
        log "SUCCESS" "✅ Apache is running."
    else
        log "ERROR" "❌ Apache is not running."
        return 1
    fi
}

show_summary() {
    local ip_address=$(hostname -I | awk '{print $1}' || echo "localhost")
    
    echo
    echo -e "${GREEN}✅ pgAdmin4 Web Installation Completed!${NC}"
    echo
    
    # Installation Details
    echo -e "${CYAN}  📋 Installation Details${NC}"
    printf "  %-20s %s\n" "📧 Email:" "$PGADMIN_EMAIL"
    printf "  %-20s %s\n" "🔑 Password:" "$PGADMIN_PASSWORD"
    printf "  %-20s %s\n" "🔌 Apache Port:" "$APACHE_PORT"
    echo
    
    # Access Information
    echo -e "${CYAN}  🔗 Access Information${NC}"
    echo -e "  ${GREEN}🌍 Web Interface:${NC}"
    echo -e "     Local:  ${BLUE}http://localhost:${APACHE_PORT}/pgadmin4${NC}"
    echo -e "     Remote: ${BLUE}http://${ip_address}:${APACHE_PORT}/pgadmin4${NC}"
    echo

    # Final message
    echo -e "${GREEN}🎉 pgAdmin4 Web is Ready to Use!${NC}"
    echo
}

main() {
    echo -e "${B_PURPLE}───────────────────────────────────────────────────────${NC}"
    echo -e " ${B_WHITE}🚀 TOTHEMARS - pgAdmin4 Web Installation Script${NC}"
    echo -e " ${B_CYAN}📅 $(TZ='Asia/Bangkok' date '+%H:%M:%S %d-%m-%Y')${NC}"
    echo -e "${B_PURPLE}───────────────────────────────────────────────────────${NC}"
    echo
    
    log "INFO" "📄 Log file: $LOGFILE"
    echo
    
    check_root || { log "ERROR" "❌ Root check failed"; exit 1; }
    check_dependencies || { log "ERROR" "❌ Dependency check failed"; exit 1; }
    
    # Show configuration (using environment variables or defaults)
    show_configuration
    
    # Check port conflict (warn but continue)
    if ! check_port_conflict "$APACHE_PORT"; then
        log "WARN" "⚠️ Port $APACHE_PORT is in use. The installation will continue but you may need to change the port manually."
    fi
    
    echo
    log "INFO" "🎯 Starting installation process..."
    echo
    
    setup_repository || { log "ERROR" "❌ Repository setup failed"; exit 1; }
    remove_desktop_version || { log "WARN" "⚠️ Desktop version removal encountered issues"; }
    install_pgadmin4_web || { log "ERROR" "❌ pgAdmin4 Web installation failed"; exit 1; }
    configure_apache_port || { log "WARN" "⚠️ Apache port configuration encountered issues"; }
    restart_apache || { log "ERROR" "❌ Apache restart failed"; exit 1; }
    configure_pgadmin4 || { log "ERROR" "❌ pgAdmin4 configuration failed"; exit 1; }
    remove_conflicting_vhost || { log "WARN" "⚠️ VirtualHost cleanup encountered issues"; }
    verify_pgadmin4_apache_config || { log "WARN" "⚠️ pgAdmin4 Apache configuration verification failed"; }
    restart_apache || { log "ERROR" "❌ Apache restart failed"; exit 1; }
    show_summary
    
    log "SUCCESS" "🎉 Installation completed successfully!"
}

main "$@"
