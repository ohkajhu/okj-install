# คู่มือติดตั้งระบบ OKJ POS (WSL Guide)

คู่มือฉบับนี้รวบรวมขั้นตอนการติดตั้งระบบ OKJ POS บน Windows โดยใช้ WSL (Windows Subsystem for Linux) และ Ubuntu 22.04 LTS อย่างละเอียด

## โครงสร้างไฟล์
| โฟลเดอร์/ไฟล์ | ใช้ทำอะไร |
| :--- | :--- |
| **`install-all.sh`** | **สคริปต์หลัก (Master Installer)** รันตัวเดียวติดตั้งครบทุกขั้นตอน |
| **`install-services.sh`** | ติดตั้งบริการ Postgres, Redis และ ConfigMap เข้าสู่ระบบ |
| `script/` | รวมสคริปต์ย่อย (Tools, K3s, Env, Startup) |
| `configmap/` | ไฟล์ ConfigMap ประจำระบบ POS |
| `Start WSL.bat` | ไฟล์ Batch สำหรับเปิด Kubernetes Monitor ฝั่ง Windows |

```
OJ-Setup/
├── install-all.sh              # <--- สคริปต์รวม (Master Installer)
├── configmap/
│   ├── pos-shop-service-cm.yaml
│   └── pos-shop-terminal-cm.yaml
├── script/
│   ├── 01-install-tools-k3s.sh
│   ├── 02-install-k3s.sh
│   ├── 03-set-env.sh
│   ├── 04-update-ip-k3s.sh
│   ├── 05-install-services.sh
│   └── 06-startup.sh           # <--- สคริปต์ตั้งค่า Auto Startup ฝั่ง Windows
└── ... (ไฟล์ Manifest อื่นๆ)
```

## ลำดับการติดตั้ง (แนะนำ - วิธีที่ง่ายที่สุด) 🚀

เราได้ทำสคริปต์รวมเพื่อให้ติดตั้งได้หมดในชุดเดียว:

```bash
# พิมพ์คำสั่งใน Ubuntu (WSL)
cd ~/okj-install/OJ-Setup
chmod +x *.sh script/*.sh
./install-all.sh
```

> **สิ่งที่ทำโดยอัตโนมัติ:**
> 1.  **Step 1:** ติดตั้งเครื่องมือพื้นฐาน (Git, FluxCD, etc.)
> 2.  **Step 2:** ติดตั้ง pgAdmin4 (Web Interface)
> 3.  **Step 3:** ติดตั้ง K3s Cluster และตั้งค่าสิทธิ์ให้เข้าถึงได้จาก Windows
> 4.  **Step 4:** ตั้งชื่อ Tenant (สาขา) และตั้งค่า Hosts
> 5.  **Step 5:** Bootstrap FluxCD ตามสภาพแวดล้อม
> 6.  **Step 6:** ติดตั้ง Cluster Services (Database และ ConfigMaps)
> 7.  **Step 7:** **Auto Startup:** ตรวจหาชื่อ WSL Distro และนำไฟล์ `Start WSL.bat` ไปไว้ใน Startup folder ของ Windows ให้อัตโนมัติ!
> 8.  **Step 8:** สรุปข้อมูลการเข้าใช้งานไว้ใน `~/okj-install/install-summary.txt`

---

## ขั้นตอนการติดตั้ง (กรณีต้องการรันแยกแยก)

หากคุณต้องการรันแยกเอง สามารถทำได้ตามลำดับดังนี้:

1.  **เตรียมระบบและเครื่องมือพื้นฐาน**
    ```bash
    cd ~/okj-install/script
    ./01-install-tools-k3s.sh
    ./01-setup-pgadmin.sh
    ```
2.  **ติดตั้ง K3s และ Environment**
    ```bash
    sudo ./02-install-k3s.sh
    ./03-set-env.sh
    ```
3.  **ติดตั้งบริการในคลัสเตอร์ (Postgres, Redis, CM)**
    ```bash
    cd ~/okj-install/OJ-Setup
    ./install-services.sh
    ```
4.  **ตั้งค่าเปิดโปรแกรมอัตโนมัติ (Startup)**
    ```bash
    cd ~/okj-install/script
    ./05-startup.sh
    ```

## การแก้ปัญหาเบื้องต้น
*   **เช็คสถานะระบบ**: `sudo kubectl get pods -A`
*   **IP เครื่องเปลี่ยน**: หากย้ายที่ตั้งใช้บริการไม่ได้ ให้รัน:
    ```bash
    cd ~/okj-install/script
    ./04-update-ip-k3s.sh
    ```
*   **ดูสรุปข้อมูล**: `cat ~/okj-install/install-summary.txt`

**สำคัญ:** อย่าลืมปรับค่า Token ใน `configmap/pos-shop-service-cm.yaml` ให้ตรงตามสาขาก่อนนำไปใช้งานจริงทุกครั้ง