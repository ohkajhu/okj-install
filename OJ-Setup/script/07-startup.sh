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

section "🚀 adding wsl to windows startup"

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

section "✨ startup setup complete"
log "SUCCESS" "WSL monitoring will now start automatically when Windows starts up."
log "INFO" "You can find it in your Windows Startup folder."
