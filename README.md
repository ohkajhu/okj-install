## 🚀 เริ่มต้นติดตั้งด้วย Bootstrap (แนะนำ)

คุณสามารถเริ่มการติดตั้งใน Linux (WSL หรือ Server) ได้ทันทีโดยใช้คำสั่งเดียวเพื่อดึงไฟล์ทั้งหมดมาไว้ที่ `~/okj-install`:

```bash
curl -sSL https://raw.githubusercontent.com/ohkajhu/okj-install/main/bootstrap.sh | bash
```

*หมายเหตุ: สคริปต์จะตรวจสอบสภาพแวดล้อมว่าเป็น WSL หรือ Server โดยอัตโนมัติ และจะดึงไฟล์จาก Git มาวางไว้ที่ `~/okj-install` เพื่อใช้ในการติดตั้งต่อ*

---

## 📂 โครงสร้าง Repository

Repository นี้แบ่งออกเป็น 2 รูปแบบหลักตามสภาพแวดล้อมที่ใช้งาน:

### 1. [OJ-Setup](./OJ-Setup/) (Windows + WSL2)
เหมาะสำหรับเครื่อง POS หน้าร้านที่ติดตั้งระบบปฏิบัติการ **Windows** โดยใช้ WSL2 (Ubuntu 22.04) ในการรันชุดเครื่องมือ POS
- **จุดเด่น**: มี Batch file สำหรับเปิดระบบอัตโนมัติ (Startup), มีระบบ Sync เวลาจาก Windows ไปยัง WSL
- **คู่มือติดตั้ง**: [Full Installation Guide (WSL)](./OJ-Setup/OKJ-Setup-Detailed-Guide.md)

### 2. [OKJ-Setup](./OKJ-Setup/) (Ubuntu Server)
เหมาะสำหรับเครื่อง **Server** หรือเครื่องที่ลง Linux (Ubuntu) เป็น OS หลักในการรันระบบ POS
- **จุดเด่น**: มีความเสถียรสูง เหมาะสำหรับใช้เป็น Server กลางของสาขา
- **คู่มือติดตั้ง**: [Setup Guide (Server)](./OKJ-Setup/OKJ-Setup-Guide.md)

---

## 🛠️ เครื่องมือหลักในชุดติดตั้ง (Component Stack)
- **Kubernetes**: [K3s](https://k3s.io/) (Lightweight Kubernetes)
- **GitOps**: [FluxCD](https://fluxcd.io/) (Automated Deployment)
- **Database**: [CloudNativePG](https://cloudnative-pg.io/) (PostgreSQL for Kubernetes)
- **Cache**: Redis 7.4
- **Monitoring**: Asynqmon & pgAdmin4

---

## 🚀 ขั้นตอนการติดตั้งเบื้องต้น (Quick Overview)

ลำดับการติดตั้งพื้นฐานในทั้งสองสภาพแวดล้อมประกอบด้วย 4 ขั้นตอนหลักในโฟลเดอร์ `script/`:

1.  **`01-install-tools-k3s.sh`**: ติดตั้ง Docker tools, FluxCD, Helm และ Desktop Environment (เฉพาะ WSL)
2.  **`01-setup-pgadmin.sh`**: ติดตั้ง pgAdmin4
3.  **`02-install-k3s.sh`**: ติดตั้ง K3s Cluster พร้อมสร้าง Alias `k` แทน `kubectl`
4.  **`03-set-env.sh`**: ระบุ Tenant / สาขา เพื่อตั้งค่า Domain และ Environment
5.  **`Bootstrap Flux`**: นำเข้าไฟล์โปรเจกต์จาก `flux-bootstrap.tar.gz` เพื่อดึงแอพเข้าคลัสเตอร์

---

## ⚠️ ข้อควรระวังก่อนเริ่ม
**การตั้งค่าสาขา**: ก่อนติดตั้ง ควรแก้ไขไฟล์ในโฟลเดอร์ `configmap/` เพื่อระบุ Token และรหัสผ่านที่ถูกต้องของแต่ละสาขา

---