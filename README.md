# 🚀 OKJ POS System Installation Repository

Repository นี้รวบรวมชุดสคริปต์และคอนฟิกูเรชันสำหรับติดตั้งระบบ **OKJ POS** บนสภาพแวดล้อม Kubernetes (K3s) ทั้งในรูปแบบ Linux Server และ Windows (WSL2)

## 🚀 เริ่มต้นติดตั้งด้วย Bootstrap (แนะนำ)

คุณสามารถเริ่มการติดตั้งใน Linux (WSL หรือ Server) ได้ทันทีโดยใช้คำสั่งเดียวเพื่อดึงไฟล์ทั้งหมดมาไว้ที่ `~/okj-install`:

```bash
curl -sSL https://raw.githubusercontent.com/ohkajhu/okj-install/main/bootstrap.sh | bash
```

*หมายเหตุ: สคริปต์จะตรวจสอบสภาพแวดล้อมว่าเป็น WSL หรือ Server โดยอัตโนมัติ และจะดาวน์โหลดไฟล์ที่จำเป็นมาวางไว้ที่ `~/okj-install` จากนั้นให้ทำตามขั้นตอนใน Next Steps ที่ปรากฏบนหน้าจอ*

---

## 📂 โครงสร้างโปรเจกต์ (Project Structure)

ชุดติดตั้งแบ่งออกเป็น 2 รูปแบบตามสภาพแวดล้อมการใช้งาน:

### 1. [OJ-Setup](./OJ-Setup/) (Windows + WSL2)
เหมาะสำหรับเครื่อง POS หน้าร้านที่ใช้ **Windows** โดยรันระบบผ่าน WSL2 (Ubuntu 22.04)
- **คู่มือติดตั้ง**: [Full Installation Guide (WSL)](./OJ-Setup/OJ-Setup-Guide.md)

### 2. [OKJ-Setup](./OKJ-Setup/) (Ubuntu Server)
เหมาะสำหรับเครื่อง **Server** กลางของสาขาที่ใช้ Ubuntu เป็น OS หลัก
- **คู่มือติดตั้ง**: [Setup Guide (Server)](./OKJ-Setup/OKJ-Setup-Guide.md)

---

## 🛠️ เครื่องมือหลักในชุดติดตั้ง (Component Stack)
- **Kubernetes**: [K3s](https://k3s.io/) (Lightweight Kubernetes)
- **GitOps**: [FluxCD](https://fluxcd.io/) (Automated Deployment)
- **Database**: [CloudNativePG](https://cloudnative-pg.io/) (PostgreSQL for K8s)
- **Cache & Monitor**: Redis 7.4, Asynqmon, pgAdmin4

---

## 🚀 ขั้นตอนการติดตั้งอย่างรวดเร็ว (Master Installer)

เราได้เตรียมสคริปต์ **Master Installer** เพื่อลดขั้นตอนยุ่งยาก ให้เหลือเพียงคำสั่งเดียวหลังจากใช้ Bootstrap:

1. **เข้าไปยังโฟลเดอร์โปรเจกต์**:
   ```bash
   cd ~/okj-install
   ```
2. **รันการติดตั้งทั้งหมด**:
   ```bash
   chmod +x *.sh script/*.sh
   ./install-all.sh
   ```

### สิ่งที่สคริปต์ Master Installer จัดการให้:
- ✅ ติดตั้ง Tools พื้นฐาน (Git, Flux, Helm, etc.)
- ✅ ติดตั้งและตั้งค่า K3s Cluster
- ✅ ตั้งค่า Environment & Hosts ประจำสาขา
- ✅ Bootstrap FluxCD (Staging/Production)
- ✅ ติดตั้ง Services (Database, Redis, CMs)
- ✅ สรุปข้อมูลการเข้าใช้งาน (Credentials & IPs)

---

## ⚠️ ข้อควรระวัง
**การตั้งค่า Token**: ก่อนใช้งานจริง ควรตรวจสอบและแก้ไขไฟล์ในโฟลเดอร์ `configmap/` เพื่อระบุ Token ของแต่ละสาขาให้ถูกต้อง (`pos-shop-service-cm.yaml`)

---
© 2026 TOTHEMARS - OKJ POS Deployment System