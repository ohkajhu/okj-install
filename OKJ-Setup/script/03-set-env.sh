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

section "🌍 Environment & Hosts Setup"

# ฟังก์ชันแสดงไฟล์เดิม
show_current_environment() {
    log "INFO" "📄 ตรวจสอบไฟล์ /etc/environment ปัจจุบัน:"
    echo "------------------------------------------"
    if [ -f /etc/environment ] && [ -s /etc/environment ]; then
        cat /etc/environment
    else
        log "INFO" "(ไฟล์ว่างหรือไม่มีไฟล์)"
    fi
    echo "------------------------------------------"
    echo ""
}

# ฟังก์ชันแสดง hosts file ปัจจุบัน
show_current_hosts() {
    log "INFO" "📄 ตรวจสอบไฟล์ /etc/hosts ปัจจุบัน:"
    echo "------------------------------------------"
    if [ -f /etc/hosts ] && [ -s /etc/hosts ]; then
        cat /etc/hosts
    else
        log "INFO" "(ไฟล์ว่างหรือไม่มีไฟล์)"
    fi
    echo "------------------------------------------"
    echo ""
}

# ฟังก์ชันสำหรับถาม TENANT name
get_tenant_name() {
    while true; do
        echo -n -e "${CYAN}กรุณาใส่ชื่อ TENANT: ${NC}"
        read TENANT_NAME
        
        if [ -z "$TENANT_NAME" ]; then
            log "WARN" "⚠️ กรุณาใส่ชื่อ TENANT"
            continue
        fi
        
        if [[ ! $TENANT_NAME =~ ^[a-zA-Z0-9_-]+$ ]]; then
            log "WARN" "⚠️ ชื่อ TENANT ควรมีเฉพาะตัวอักษร, ตัวเลข, -, _ เท่านั้น"
            continue
        fi
        
        break
    done
}

# ฟังก์ชันยืนยันการตั้งค่า
confirm_settings() {
    echo ""
    log "INFO" "📋 ตรวจสอบการตั้งค่า:"
    echo "------------------------------------------"
    echo "ไฟล์ /etc/environment"
    echo "TENANT: $TENANT_NAME"
    echo "REGISTRY_HOST: registry.ohkajhu.com"
    echo "REGISTRY_USERNAME: robot\$cache-server"
    echo "REGISTRY_PASSWORD: KcHN7gPepBR2AGkKC2NQQiNAmDUheTAm"
    echo ""
    echo "ไฟล์ /etc/hosts"
    echo "125.254.54.194 registry.ohkajhu.com"
    echo "125.254.54.194 shop-gateway.ohkajhu.com"
    echo "------------------------------------------"
    echo ""
    
    while true; do
        echo -n -e "${YELLOW}ยืนยันการตั้งค่า? (y/n): ${NC}"
        read CONFIRM
        case $CONFIRM in
            [Yy]|[Yy]es|ใช่) return 0 ;;
            [Nn]|[Nn]o|ไม่) return 1 ;;
            *) log "WARN" "กรุณาตอบ y หรือ n" ;;
        esac
    done
}

# ฟังก์ชันสร้าง/อัปเดตไฟล์ environment
create_environment_file() {
    log "INFO" "🔧 กำลังอัปเดตไฟล์ /etc/environment..."
    
    TEMP_FILE=$(mktemp)
    if [ -f /etc/environment ] && [ -s /etc/environment ]; then
        sudo grep -v "^TENANT=" /etc/environment | \
        sudo grep -v "^REGISTRY_HOST=" | \
        sudo grep -v "^REGISTRY_USERNAME=" | \
        sudo grep -v "^REGISTRY_PASSWORD=" > "$TEMP_FILE" || true
    fi
    
    cat >> "$TEMP_FILE" <<EOF
TENANT='$TENANT_NAME'
REGISTRY_HOST='registry.ohkajhu.com'
REGISTRY_USERNAME='robot\$cache-server'
REGISTRY_PASSWORD='KcHN7gPepBR2AGkKC2NQQiNAmDUheTAm'
EOF
    
    sudo cp "$TEMP_FILE" /etc/environment
    rm "$TEMP_FILE"
    
    log "SUCCESS" "✅ อัปเดตไฟล์ /etc/environment สำเร็จ"
}

# ฟังก์ชันอัปเดต hosts file
update_hosts_file() {
    log "INFO" "🔧 กำลังอัปเดตไฟล์ /etc/hosts..."
    
    sudo cp /etc/hosts /etc/hosts.backup
    sudo sed -i '/ohkajhu\.com/d' /etc/hosts
    
    sudo tee -a /etc/hosts >/dev/null << EOF
125.254.54.194 registry.ohkajhu.com
125.254.54.194 shop-gateway.ohkajhu.com
EOF
    
    log "SUCCESS" "✅ อัปเดตไฟล์ /etc/hosts สำเร็จ"
}

# ฟังก์ชันโหลดตัวแปรสิ่งแวดล้อม
load_environment() {
    log "INFO" "🔄 กำลังโหลดตัวแปรสิ่งแวดล้อม..."
    log "SUCCESS" "✅ ตัวแปรพร้อมใช้งานแล้ว (กรุณาเปิด Terminal ใหม่เพื่อให้ค่ามีผลสมบูรณ์)"
}

# ฟังก์ชันตรวจสอบสิทธิ์
check_permissions() {
    if [ "$EUID" -eq 0 ]; then
        log "WARN" "⚠️ กำลังรันด้วยสิทธิ์ root"
        log "INFO" "กรุณารันสคริปต์นี้ด้วยผู้ใช้ทั่วไป (สคริปต์จะขอ sudo เมื่อจำเป็น)"
        exit 1
    fi
    
    sudo -v > /dev/null 2>&1 || log "ERROR" "❌ ไม่สามารถใช้ sudo ได้ กรุณาตั้งค่าสิทธิ์ sudo"
}

# ฟังก์ชันหลัก
main() {
    check_permissions
    show_current_environment
    show_current_hosts
    get_tenant_name
    
    if ! confirm_settings; then
        log "WARN" "❌ ยกเลิกการตั้งค่า"
        exit 0
    fi
    
    create_environment_file
    update_hosts_file
    load_environment
    
    section "✅ Setup Complete"
    log "INFO" "📄 New Environment:"
    cat /etc/environment
}

main