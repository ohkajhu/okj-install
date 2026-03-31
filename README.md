# 🚀 OKJ POS System Installation Repository

Repository นี้เป็นศูนย์กลางของชุดสคริปต์และคอนฟิกูเรชันอัตโนมัติ (Automated Setup) สำหรับติดตั้งและดูแลระบบ **OKJ POS** ภายใต้สภาพแวดล้อม Kubernetes (K3s) ออกแบบมาเพื่อรองรับ 2 สภาพแวดล้อมหลัก:

1.  💻 **Windows (WSL2)**: สำหรับเครื่อง POS หน้าร้าน (Ubuntu 22.04 on WSL2)
2.  🐧 **Ubuntu Server**: สำหรับเครื่องสาขาที่เป็น Native Linux Server

---

## 📋 สิ่งที่ต้องเตรียมก่อนเริ่ม (Pre-Installation Checklist)

เพื่อให้การติดตั้งเป็นไปอย่างรวดเร็ว กรุณาเตรียมข้อมูลและสภาพแวดล้อมดังนี้:

1.  ✅ **เตรียมเครื่องให้พร้อม**: ไม่ว่าจะเป็น **Ubuntu Server** (เครื่องจริง) หรือ **WSL** (บน Windows)
2.  ✅ **เตรียมชื่อ Tenant**: รหัสสาขาหลัก (เช่น `JW00`, `OJ00`)
3.  ✅ **เตรียม Shop Code และ Shop Token**: รหัสสาขาเฉพาะและรหัส Token สำหรับเชื่อมต่อระบบ Gateway/RMS (ตรวจสอบได้จากทีม Central IT)

---

## ⚡ เริ่มต้นด้วย Bootstrap (แนะนำ)

สามารถเริ่มการติดตั้งใน Linux (WSL หรือ Server) ได้ทันทีด้วย **One-Command Setup** เพื่อเตรียมสภาพแวดล้อมให้พร้อมอัตโนมัติ:

```bash
curl -sSL https://raw.githubusercontent.com/ohkajhu/okj-install/main/bootstrap.sh | bash
```

### 💡 สิ่งที่ Bootstrap จัดการให้:
-   🔍 **Detect Environment**: ตรวจสอบว่าเป็น WSL หรือ Native Server โดยอัตโนมัติ
-   📥 **Clone & Prepare**: ดึงเฉพาะชุดติดตั้งที่เหมาะสมกับสภาพแวดล้อมนั้นๆ ไว้ที่ `~/okj-install`
-   🔑 **Set Permissions**: ตั้งค่าสิทธิ์การรันไฟล์สคริปต์ (`chmod +x`) ทั้งหมด

---

## 🛠️ โครงสร้างและการเลือกใช้ (Project Structure)

ภายใน Repository แบ่งออกเป็น 2 ชุดหลักตามความต้องการ:

| โฟลเดอร์                     | สภาพแวดล้อมที่รองรับ | จุดเด่นสำคัญ                               | คู่มือการติดตั้ง |
| :-------------------------- | :------------------ | :----------------------------------------- | :------------: |
| 💻 **[OJ-Setup](./OJ-Setup/)** | **Windows + WSL2**  | ⭐ ติดตั้งง่าย + ตั้งค่า Startup อัตโนมัติ | [👉 Click Here](./OJ-Setup/OJ-Setup-Guide.md) |
| 🐧 **[OKJ-Setup](./OKJ-Setup/)** | **Ubuntu Server**   | ⚡ เสถียรสูง + เหมาะสำหรับเครื่อง Server  | [👉 Click Here](./OKJ-Setup/OKJ-Setup-Guide.md) |

---

## 🚀 ขั้นตอนการติดตั้งด้วย Master Installer

สคริปต์ถูกออกแบบมาให้เป็น **Idempotent** (รันซ้ำกี่ครั้งก็ได้) และรองรับการ **Resume** อัตโนมัติ:

```bash
cd ~/okj-install
./install-all.sh
- เลือก Environment: Staging หรือ Production
- กรอก Tenant Name: รหัสสาขาหลัก (เช่น `JW00`)
- กรอก Shop Code: รหัสระบุตัวตนของร้าน (เช่น `JW0000`)
- กรอก Shop Token: รหัสความปลอดภัยสำหรับเชื่อมต่อระบบ (Gateway/RMS Token)
```

### 🛡️ จุดเด่นของระบบติดตั้ง (Hardened Features):
-   **Smart Resume**: ระบบจดจำสถานะ หากการติดตั้งหยุดชะงัก (เน็ตหลุด/ไฟดับ) เมื่อรันสคริปต์ใหม่จะถามเพื่อรันต่อจากจุดเดิมทันที (Skip ขั้นตอนที่สำเร็จแล้ว)
-   **Apt Lock Resilience**: ตรวจสอบและรอคิว Package Manager อัตโนมัติ ป้องกัน Error จากการที่ระบบอัปเดตเบื้องหลัง
-   **Robust K8s Apply**: ระบบ Retry อัตโนมัติเมื่อเจอปัญหา Webhook TLS หรือ API Timeout ในจังหวะติดตั้ง Service

### 📦 ขั้นตอนที่ Master Installer จัดการให้โดยละเอียด:

0.  **Step 0: Pre-flight Questionnaire** (Interactive) - สคริปต์จะถามข้อมูลเพื่อตั้งค่าเบื้องต้น:
    *   **Environment**: เลือกเป็น `Staging` หรือ `Production`
    *   **Tenant Name**: ชื่อรหัสสาขาหลัก (เช่น `JW00`)
    *   **Shop Code**: รหัสระบุตัวตนของร้าน (เช่น `JW000`)
    *   **Shop Token**: รหัสความปลอดภัยสำหรับเชื่อมต่อระบบ (Gateway/RMS Token)
1.  **Step 1: Basic Tools** - ติดตั้ง Git, AnyDesk, Docker, Tailsacle, Helm และ yq
2.  **Step 2: pgAdmin4** - ตั้งค่าโปรแกรมจัดการ Database ผ่าน Web UI (Port 8080)
3.  **Step 3: K3s Cluster** - ติดตั้ง Kubernetes Cluster แบบ Lightweight (v1.31+)
4.  **Step 4: Environment** - ตั้งค่า System Hosts และ Branch Identity (Tenant URL)
5.  **Step 5: Flux Bootstrap** - เชื่อมต่อระบบ Deployment อัตโนมัติจาก GitHub
6.  **Step 6: Cluster Services** - ติดตั้ง Database (PostgreSQL), Redis และ Storage Classes
7.  **Step 7: Shop Configuration** (Interactive) - ใส่รหัสร้าน (Shop Code) และ Token เพื่อเปิดใช้งาน Service
8.  **Step 8: Summary** - สร้างไฟล์สรุปข้อมูลทั้งหมด (IP, IDs, Passwords)

---

## 📝 การตรวจสอบหลังการติดตั้ง (Post-Installation)

เมื่อรัน `install-all.sh` สำเร็จ ระบบจะแสดงผลสรุปและบันทึกไว้ที่:
👉 `cat ~/okj-install/install-summary.txt`

### 🔍 คำสั่งตรวจสอบเบื้องต้น:
-   **เช็คสถานะ Node**: `sudo kubectl get nodes`
-   **เช็คแอปพลิเคชัน**: `sudo kubectl get pod -A`
-   **เช็ค Deployment**: `sudo flux get kustomizations`

---

## 🛠️ เครื่องมือหลักที่ใช้ (Component Stack)

-   🚀 **Kubernetes**: [K3s](https://k3s.io/)
-   🔄 **GitOps/Sync**: [FluxCD](https://fluxcd.io/)
-   🗄️ **Database Operator**: [CloudNativePG (CNPG)](https://cloudnative-pg.io/)
-   📊 **Management**: pgAdmin4, AnyDesk, Tailscale
-   ⚡ **Cache**: Redis 7.4

---

## ⚠️ ข้อควรระวังและการดูแลรักษา

1.  **AnyDesk ID**: หากพบว่าสถานะเป็น `Not Ready` ในตอนเริ่ม ให้รอ 1-2 นาทีแล้วรัน `cat ~/okj-install/install-summary.txt` อีกครั้ง
2.  **Shop Token**: คุณสามารถอัปเดต Token ของร้านได้ตลอดเวลาโดยรันสคริปต์ `./script/06-config-shop.sh`
3.  **Smart Resume**: ระบบบันทึกสถานะไว้ที่ไฟล์ `.install_state` ในโฟลเดอร์ติดตั้ง หากการติดตั้งสำเร็จไฟล์นี้จะถูกลบออกอัตโนมัติ
4.  **Logs**: หาก Service มีปัญหา สามารถตรวจเช็ค Log ได้ด้วย:
    `sudo kubectl logs -f -l app=pos-shop-service -n apps`

---
© 2026 TOTHEMARS - OKJ POS Deployment Standard