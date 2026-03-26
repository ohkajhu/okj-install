#!/bin/bash

# ฟังก์ชันแสดงหัวข้อ
show_header() {
    echo "=========================================="
    echo "  Environment & Hosts Setup Script"
    echo "=========================================="
    echo ""
}

# ฟังก์ชันแสดงไฟล์เดิม
show_current_environment() {
    echo "📄 ตรวจสอบไฟล์ /etc/environment ปัจจุบัน:"
    echo "=========================================="
    
    if [ -f /etc/environment ] && [ -s /etc/environment ]; then
        cat /etc/environment
    else
        echo "(ไฟล์ว่างหรือไม่มีไฟล์)"
    fi
    
    echo "=========================================="
    echo ""
}

# ฟังก์ชันแสดง hosts file ปัจจุบัน
show_current_hosts() {
    echo "📄 ตรวจสอบไฟล์ /etc/hosts ปัจจุบัน:"
    echo "=========================================="
    
    if [ -f /etc/hosts ] && [ -s /etc/hosts ]; then
        cat /etc/hosts
    else
        echo "(ไฟล์ว่างหรือไม่มีไฟล์)"
    fi
    
    echo "=========================================="
    echo ""
}

# ฟังก์ชันสำหรับถาม TENANT name
get_tenant_name() {
    while true; do
        echo -n "กรุณาใส่ชื่อ TENANT: "
        read TENANT_NAME
        
        # ตรวจสอบว่าใส่ค่ามาหรือไม่
        if [ -z "$TENANT_NAME" ]; then
            echo "⚠️  กรุณาใส่ชื่อ TENANT"
            continue
        fi
        
        # ตรวจสอบรูปแบบ (อนุญาตเฉพาะ a-z, A-Z, 0-9, -, _)
        if [[ ! $TENANT_NAME =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "⚠️  ชื่อ TENANT ควรมีเฉพาะตัวอักษร, ตัวเลข, -, _ เท่านั้น"
            continue
        fi
        
        break
    done
}

# ฟังก์ชันยืนยันการตั้งค่า
confirm_settings() {
    echo ""
    echo "=========================================="
    echo "ตรวจสอบการตั้งค่า:"
    echo "=========================================="
    echo ""
    echo "ไฟล์ /etc/environment"
    echo "TENANT: $TENANT_NAME"
    echo "REGISTRY_HOST: registry.ohkajhu.com"
    echo "REGISTRY_USERNAME: robot\$cache-server"
    echo "REGISTRY_PASSWORD: KcHN7gPepBR2AGkKC2NQQiNAmDUheTAm"
    echo ""
    echo "ไฟล์ /etc/hosts"
    echo "125.254.54.194 registry.ohkajhu.com"
    echo "125.254.54.194 shop-gateway.ohkajhu.com"
    echo ""
    
    while true; do
        echo -n "ยืนยันการตั้งค่า? (y/n): "
        read CONFIRM
        case $CONFIRM in
            [Yy]|[Yy]es|ใช่) return 0 ;;
            [Nn]|[Nn]o|ไม่) return 1 ;;
            *) echo "กรุณาตอบ y หรือ n" ;;
        esac
    done
}

# ฟังก์ชันสร้าง/อัปเดตไฟล์ environment
create_environment_file() {
    echo "🔧 กำลังอัปเดตไฟล์ /etc/environment..."
    
    # อ่านไฟล์เดิมและกรองตัวแปรที่จะแทนที่
    TEMP_FILE=$(mktemp)
    if [ -f /etc/environment ] && [ -s /etc/environment ]; then
        # กรองออกตัวแปร TENANT, REGISTRY_HOST, REGISTRY_USERNAME, REGISTRY_PASSWORD ที่มีอยู่
        sudo grep -v "^TENANT=" /etc/environment | \
        sudo grep -v "^REGISTRY_HOST=" | \
        sudo grep -v "^REGISTRY_USERNAME=" | \
        sudo grep -v "^REGISTRY_PASSWORD=" > "$TEMP_FILE"
    fi
    
    # เพิ่มตัวแปรใหม่
    cat >> "$TEMP_FILE" <<EOF
TENANT='$TENANT_NAME'
REGISTRY_HOST='registry.ohkajhu.com'
REGISTRY_USERNAME='robot\$cache-server'
REGISTRY_PASSWORD='KcHN7gPepBR2AGkKC2NQQiNAmDUheTAm'
EOF
    
    # เขียนไฟล์ใหม่
    sudo cp "$TEMP_FILE" /etc/environment
    rm "$TEMP_FILE"
    
    if [ $? -eq 0 ]; then
        echo "✅ อัปเดตไฟล์ /etc/environment สำเร็จ"
    else
        echo "❌ เกิดข้อผิดพลาดในการอัปเดตไฟล์"
        exit 1
    fi
}

# ฟังก์ชันอัปเดต hosts file
update_hosts_file() {
    echo "🔧 กำลังอัปเดตไฟล์ /etc/hosts..."
    
    # สร้าง backup ไฟล์ hosts
    sudo cp /etc/hosts /etc/hosts.backup
    
    # ลบ entries เก่าของ ohkajhu.com (ถ้ามี)
    sudo sed -i '/ohkajhu\.com/d' /etc/hosts
    
    # เพิ่ม entries ใหม่
    sudo tee -a /etc/hosts >/dev/null << EOF
125.254.54.194 registry.ohkajhu.com
125.254.54.194 shop-gateway.ohkajhu.com
EOF
    
    if [ $? -eq 0 ]; then
        echo "✅ อัปเดตไฟล์ /etc/hosts สำเร็จ"
    else
        echo "❌ เกิดข้อผิดพลาดในการอัปเดตไฟล์ /etc/hosts"
        exit 1
    fi
}



# ฟังก์ชันโหลดตัวแปรสิ่งแวดล้อม
load_environment() {
    echo "🔄 กำลังโหลดตัวแปรสิ่งแวดล้อม..."
    source /etc/environment
    
    if [ $? -eq 0 ]; then
        echo "✅ โหลดตัวแปรสิ่งแวดล้อมสำเร็จ - ตัวแปรพร้อมใช้งานแล้ว!"
    else
        echo "⚠️  อาจมีปัญหาในการโหลดตัวแปร กรุณาตรวจสอบ"
    fi
}

# ฟังก์ชันแสดงผลลัพธ์
show_result() {
    echo ""
    echo "=========================================="
    echo "ผลลัพธ์การตั้งค่า:"
    echo "=========================================="
    echo ""
    echo "📄 Environment Variables:"
    echo "----------------------------------------"
    cat /etc/environment
    echo ""
    echo "📄 Hosts Entries:"
    echo "----------------------------------------"
    cat /etc/hosts
    echo ""
    echo "✅ การตั้งค่าเสร็จสมบูรณ์!"
}

# ฟังก์ชันตรวจสอบสิทธิ์
check_permissions() {
    if [ "$EUID" -eq 0 ]; then
        echo "⚠️  กำลังรันด้วยสิทธิ์ root"
        echo "กรุณารันสคริปต์นี้ด้วยผู้ใช้ทั่วไป (สคริปต์จะขอ sudo เมื่อจำเป็น)"
        exit 1
    fi
    
    # ตรวจสอบว่าสามารถใช้ sudo ได้หรือไม่
    sudo -v > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ ไม่สามารถใช้ sudo ได้ กรุณาตั้งค่าสิทธิ์ sudo"
        exit 1
    fi
}

# ฟังก์ชันหลัก
main() {
    # ตรวจสอบสิทธิ์
    check_permissions
    
    # แสดงหัวข้อ
    show_header
    
    # แสดงไฟล์เดิม
    show_current_environment
    show_current_hosts
    
    # ถามชื่อ TENANT
    get_tenant_name
    
    # ยืนยันการตั้งค่า
    if ! confirm_settings; then
        echo "❌ ยกเลิกการตั้งค่า"
        exit 0
    fi
    
    # สร้าง/อัปเดตไฟล์ environment
    create_environment_file
    
    # อัปเดต hosts file
    update_hosts_file
    
    # โหลดตัวแปรสิ่งแวดล้อม
    load_environment
    
    # แสดงผลลัพธ์
    show_result
}

# เรียกใช้ฟังก์ชันหลัก
main