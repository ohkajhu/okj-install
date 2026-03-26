#!/bin/bash
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Logging Helpers ---
log() {
    local level=$1
    shift
    local message="$*"
    case $level in
        "INFO")    echo -e "${BLUE}[INFO]${NC}  $message" ;;
        "WARN")    echo -e "${YELLOW}[WARN]${NC}  $message" ;;
        "ERROR")   echo -e "${RED}[ERROR]${NC} $message" >&2; exit 1 ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "STEP")    echo -e "${PURPLE}[STEP]${NC} $message" ;;
    esac
}

section() {
    echo -e "\n${PURPLE}===========================================${NC}"
    echo -e "${PURPLE}   $*${NC}"
    echo -e "${PURPLE}===========================================${NC}"
}

section "🚀 Adding WSL to Windows Startup"

# 1. Detect current WSL Distribution name
log "INFO" "🔍 Detecting current WSL distribution..."
# Use PowerShell to find the default (*) distro as it's cleaner than parsing UTF-16 from bash directly
DISTRO_NAME=$(powershell.exe -NoProfile -Command "((wsl.exe -l -v | Select-String '\*') -replace '^[\s\*]+(\S+).*$', '\$1').Trim()" | tr -d '\r\n' || echo "Ubuntu")

if [ -z "$DISTRO_NAME" ]; then
    DISTRO_NAME="Ubuntu"
    log "WARN" "⚠️  Could not detect distro name, defaulting to: $DISTRO_NAME"
else
    log "SUCCESS" "Detected WSL Distro: $DISTRO_NAME"
fi

# 2. Get Windows Startup Folder path
log "INFO" "📁 Finding Windows Startup folder..."
WIN_STARTUP_FOLDER=$(powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('Startup')" | tr -d '\r\n')

if [ -z "$WIN_STARTUP_FOLDER" ]; then
    log "ERROR" "❌ Could not find Windows Startup folder."
fi

WSL_STARTUP_PATH=$(wslpath "$WIN_STARTUP_FOLDER")
log "INFO" "   └─ Windows Path: $WIN_STARTUP_FOLDER"
log "INFO" "   └─ WSL Path: $WSL_STARTUP_PATH"

# 3. Create/Update 'Start WSL.bat'
TARGET_FILE="$WSL_STARTUP_PATH/Start WSL.bat"
log "INFO" "⚙️  Creating startup batch file: $TARGET_FILE"

cat > "$TARGET_FILE" <<EOF
@echo off
echo Starting OKJ POS Monitoring...
REM Start WSL distribution '$DISTRO_NAME' with okjadmin user
start wsl -d $DISTRO_NAME -u okjadmin bash -c "watch -n 1 'sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get po -A'; exec bash"
EOF

# Also update the local Start WSL.bat in the current folder for consistency
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BAT="$(cd "$SCRIPT_DIR/.." && pwd)/Start WSL.bat"

if [ -f "$LOCAL_BAT" ]; then
    log "INFO" "⚙️  Updating local batch file: $LOCAL_BAT"
    cp "$TARGET_FILE" "$LOCAL_BAT"
fi

section "✅ Startup Setup Complete"
log "SUCCESS" "WSL monitoring will now start automatically when Windows starts up."
log "INFO" "You can find it in your Windows Startup folder."
