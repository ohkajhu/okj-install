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
        "INFO")    echo -e "  ${B_BLUE}ℹ [INFO]${NC} $message" | tee -a "$log_out" ;;
        "WARN")    echo -e "  ${B_YELLOW}⚠ [WARN]${NC} $message" | tee -a "$log_out" ;;
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

section "🚀 Adding WSL to Windows Startup"

# 1. Detect current WSL Distribution name
log "INFO" "🔍 Detecting current WSL distribution..."

# Priority 1: Use native WSL environment variable (Most reliable & efficient)
DISTRO_NAME=${WSL_DISTRO_NAME:-}

# Priority 2: PowerShell fallback if env var is empty
if [ -z "$DISTRO_NAME" ]; then
    DISTRO_NAME=$(powershell.exe -NoProfile -Command "wsl.exe -l -v | Select-String '\*' | ForEach-Object { \$_.ToString().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)[1] }" | tr -d '\0\r\n' || echo "")
fi

# Priority 3: Final hard fallback
if [ -z "$DISTRO_NAME" ] || [ "$DISTRO_NAME" == "Ubuntu" ]; then
    DISTRO_NAME="Ubuntu"
    log "INFO" "Detected WSL Distro (Default): $DISTRO_NAME"
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
