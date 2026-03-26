#!/bin/bash
set -e

# --- Configuration ---
# แนะนำให้เปลี่ยน URL เป็น Repo จริงของคุณ
REPO_URL="https://github.com/ohkajhu/okj-install.git"
TARGET_DIR="$HOME/usb"

echo "==========================================="
echo "   OKJ POS System Bootstrap Script"
echo "==========================================="

# 1. Check for Git
if ! command -v git >/dev/null 2>&1; then
    echo "📦 Installing Git..."
    sudo apt update -qq && sudo apt install -y git -qq
fi

# 2. Detect environment (WSL vs Server)
if grep -qi microsoft /proc/version 2>/dev/null; then
    SETUP_TYPE="OJ-Setup"
    echo "🖥️  Detected WSL environment"
else
    SETUP_TYPE="OKJ-Setup"
    echo "🛠️  Detected Ubuntu Server environment"
fi

# 3. Clone Repository
TEMP_DIR=$(mktemp -d)
echo "📥 Cloning files from $REPO_URL..."
if git clone --depth 1 "$REPO_URL" "$TEMP_DIR" -q; then
    echo "✅ Clone successful"
else
    echo "❌ Failed to clone repository. Please check your internet or REPO_URL."
    exit 1
fi

# 4. Prepare ~/usb
echo "📁 Preparing $TARGET_DIR directory..."
mkdir -p "$TARGET_DIR"

# 5. Copy files
echo "🚚 Moving $SETUP_TYPE files to $TARGET_DIR..."
# ลบไฟล์เก่าถ้ามี (Optional: เพื่อความสะอาด)
# rm -rf "$TARGET_DIR"/* 
cp -r "$TEMP_DIR/$SETUP_TYPE/"* "$TARGET_DIR/"

# 6. Set permissions
echo "🔐 Setting executable permissions on scripts..."
chmod +x "$TARGET_DIR/script/"*.sh

# 7. Cleanup
rm -rf "$TEMP_DIR"

echo "==========================================="
echo "✅ Bootstrap Complete!"
echo "==========================================="
echo "ไฟล์ทั้งหมดพร้อมแล้วที่: $TARGET_DIR"
echo "คุณสามารถทำตามคู่มือต่อได้โดยเริ่มจาก:"
echo "cd $TARGET_DIR/script"
echo "==========================================="
