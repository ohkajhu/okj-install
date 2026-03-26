# คู่มือใช้งาน OKJ Setup (Ubuntu Server)

คู่มือวิธีใช้งาน `OKJ-Setup` เพื่อเตรียมเครื่อง Ubuntu ให้พร้อมทำงานเป็นเซิร์ฟเวอร์ OKJ POS ที่ใช้ K3s พร้อมเครื่องมือสำคัญ เช่น FluxCD, Redis, CloudNativePG, AnyDesk และ pgAdmin

## โครงสร้างไฟล์หลัก ๆ
| โฟลเดอร์/ไฟล์ | ใช้ทำอะไร |
| :--- | :--- |
| **`install-all.sh`** | **สคริปต์หลัก (Master Installer)** รันตัวเดียวติดตั้งครบทุกลูป |
| **`install-services.sh`** | สคริปต์ติดตั้ง Database, Redis และ ConfigMap เข้าคลัสเตอร์ |
| `script/` | รวมสคริปต์ Bash ย่อยสำหรับติดตั้ง/ถอนการติดตั้งโปรแกรม |
| `configmap/` | ไฟล์ตั้งค่า ConfigMap สำหรับ POS |
| `redis.yaml` | ไฟล์สำหรับติดตั้ง Redis (Deployment + Service) |
| `okj-pos-pgsql.yaml` | ไฟล์ CloudNativePG สำหรับ PostgreSQL |
| `asynqmon.yaml` | ไฟล์ติดตั้ง Asynq Monitor UI |
| `flux-bootstrap.tar.gz` | ไฟล์สำหรับ bootstrap FluxCD |

```
OKJ-Setup/
├── install-all.sh              # <--- รันตัวนี้เพื่อติดตั้งทั้งหมด
├── configmap/
│   ├── pos-shop-service-cm.yaml        # ไฟล์ configmap ของ pos-shop-service (ต้องแก้ Token แต่ละสาขา)
│   └── pos-shop-terminal-cm.yaml       # ไฟล์ configmap ของ pos-shop-terminal
├── script/
│   ├── 01-install-tools-k3s.sh
│   ├── 02-install-k3s.sh
│   ├── 03-set-env.sh
│   ├── 04-update-ip-k3s.sh
│   └── 05-install-services.sh
└── ... (ไฟล์ Manifest อื่นๆ)
```

## เริ่มต้นใช้งาน (วิธีที่แนะนำ)
หากเครื่อง Server ต่ออินเทอร์เน็ตได้ แนะนำให้ใช้ Bootstrap script เพื่อดึงไฟล์มาไว้ที่ `~/okj-install`:
```bash
curl -sSL https://raw.githubusercontent.com/ohkajhu/okj-install/main/bootstrap.sh | bash
```

## ลำดับการติดตั้ง (Master Installer) 🚀

เราได้ทำสคริปต์รวมเพื่อให้ติดตั้งได้ง่ายที่สุดในคำสั่งเดียว:

```bash
cd ~/okj-install/OKJ-Setup
chmod +x *.sh script/*.sh
./install-all.sh
```

> **สิ่งที่สคริปต์นี้จะทำโดยอัตโนมัติ:**
> 1.  **Step 1:** ติดตั้งเครื่องมือพื้นฐาน (Git, SSH, FluxCD, Helm, etc.)
> 2.  **Step 2:** ติดตั้ง pgAdmin4 (Web Interface)
> 3.  **Step 3:** ติดตั้ง K3s Cluster และตั้งค่าสิทธิ์การใช้งาน
> 4.  **Step 4:** ตั้งชื่อ Tenant (สาขา) และตั้งค่า Hosts
> 5.  **Step 5:** Bootstrap FluxCD ตามสภาพแวดล้อม (Staging/Production)
> 6.  **Step 6:** ติดตั้ง Cluster Services (Postgres, Redis, Asynqmon, Terminal CM)
> 7.  **Step 7:** สรุปข้อมูลการเข้าใช้งานไว้ใน `~/okj-install/install-summary.txt`

---

## การรันแยกทีละขั้นตอน (Manual)

หากคุณต้องการรันแยกเอง สามารถทำได้ตามลำดับดังนี้:

1.  **เตรียมระบบและเครื่องมือ**
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
3.  **ติดตั้ง Cluster Services**
    ```bash
    cd ~/okj-install/OKJ-Setup
    ./install-services.sh
    ```

## การแก้ปัญหาเบื้องต้น
*   **ดูสถานะ Cluster**: `sudo kubectl get nodes` หรือ `sudo kubectl get pods -A`
*   **เมื่อ IP เครื่องเปลี่ยน**: หากย้ายที่ตั้งแล้วเข้า Kubernetes ไม่ได้ ให้รัน:
    ```bash
    cd ~/okj-install/script
    ./04-update-ip-k3s.sh
    ```
*   **เช็คข้อมูลการเข้าใช้งาน**:
    ```bash
    cat ~/okj-install/install-summary.txt
    ```

**หมายเหตุ:** ไฟล์ `configmap/pos-shop-service-cm.yaml` จะไม่ถูกติดตั้งอัตโนมัติแบบสมบูรณ์เนื่องจากต้องแก้ Token ประจำสาขาด้วยตัวเองก่อนใช้งาน