# คู่มือใช้งาน OKJ Setup 

คู่มือวิธีใช้งาน `OKJ-Setup` เพื่อเตรียมเครื่อง Ubuntu ให้พร้อมทำงานเป็นเซิร์ฟเวอร์ OKJ POS ที่ใช้ K3s พร้อมเครื่องมือสำคัญ เช่น FluxCD, Redis, CloudNativePG, AnyDesk และ pgAdmin

## โครงสร้างไฟล์หลัก ๆ
| โฟลเดอร์/ไฟล์ | ใช้ทำอะไร |
|
| `script/` | รวมสคริปต์ Bash สำหรับติดตั้ง/ถอนการติดตั้งโปรแกรมที่จำเป็น |
| `configmap/` | ไฟล์ตั้งค่า ConfigMap สำหรับ POS |
| `redis.yaml` | ไฟล์สำหรับติดตั้ง Redis (มี ConfigMap, Deployment, Service) |
| `okj-pos-pgsql.yaml` | ไฟล์ CloudNativePG สำหรับ PostgreSQL พร้อม Secret และ NodePort |
| `asynqmon.yaml` | ไฟล์ติดตั้ง Asynq Monitor (Deployment + Service + Ingress) |
| `flux-bootstrap.tar.gz` | ไฟล์บีบอัดที่ใช้สำหรับ bootstrap Flux |

```
OKJ-Setup/
├── configmap/
│   ├── pos-shop-service-cm.yaml        # ไฟล์ configmap ของ pos-shop-service (ต้องแก้ Token แต่ละสาขา)
│   └── pos-shop-terminal-cm.yaml       # ไฟล์ configmap ของ pos-shop-terminal
├── script/
│   ├── 01-install-tools-k3s.sh         # ติดตั้ง Desktop , Git , SSH , FluxCD , yq , kustomize , Helm , Kubeconform , curl
│   ├── 01-uninstall-tools-k3s.sh       # ถอนการติดตั้งเครื่องมือพื้นฐาน
│   ├── 01-setup-pgadmin.sh             # ติดตั้ง pgAdmin4 แบบเว็บผ่าน Apache
│   ├── 01-uninstall-pgadmin.sh         # ถอนการติดตั้ง pgAdmin4
│   ├── 02-install-k3s.sh               # ติดตั้ง K3s
│   ├── 02-uninstall-k3s.sh             # ถอนการติดตั้ง K3s ออกจากระบบ
│   ├── 03-set-env.sh                   # ตั้งค่า `/etc/environment` และ `/etc/hosts`
│   ├── 04-update-ip-k3s.sh             # อัปเดต IP ใน kubeconfig เมื่อเครื่องย้ายที่ ใช้ตอนเชื่อมต่อคลัสเตอร์ไม่ได้เพราะ IP เปลี่ยน
├── asynqmon.yaml                       # Manifest Deployment/Service/Ingress สำหรับ Asynq Monitor UI
├── flux-bootstrap.tar.gz               # ไฟล์ bootstrap ของ Flux (ต้องแตกไฟล์เพื่อติดตั้ง Flux)
├── okj-pos-pgsql.yaml                  # Manifest CloudNativePG สำหรับ PostgreSQL ของระบบ POS
├── README.md                           # คู่มือ
└── redis.yaml                          # Manifest Redis (ConfigMap + Deployment + Service)
```

## ก่อนเริ่มใช้งานควรมีสิ่งนี้
- เครื่อง Ubuntu 20.04 ขึ้นไป และสามารถใช้ `sudo` ได้
- อินเทอร์เน็ตสำหรับดาวน์โหลดแพ็กเกจ

## เริ่มต้นใช้งาน (ใช้ USB)
```bash
sudo fdisk -l
mkdir ~/usb
sudo mount /dev/sdb1 ~/usb
cd ~/usb/script
```

## ลำดับการติดตั้งที่แนะนำ
1. **ติดตั้งชุดเครื่องมือพื้นฐาน**

   ```bash
   ./01-install-tools-k3s.sh
   ./01-setup-pgadmin.sh
   ```
   
2. **ติดตั้ง K3s และสร้าง kubeconfig**

   ```bash
   sudo ./02-install-k3s.sh
   ```

3. **ตั้งค่า Environment และ hosts สำหรับแต่ละสาขา**

   ```bash
   ./03-set-env.sh
   ```

4. **ติดตั้ง Bootstrap Flux**

   ```bash
   cd ~
   tar -xvf ~/usb/flux-bootstrap.tar.gz --no-same-owner --no-same-permissions
   cd .bootstrap
   sudo ./install-prd.sh
   ```

5. **ติดตั้งบริการต่าง ๆ ในคลัสเตอร์**

   cd ~/usb
   ```bash
   sudo kubectl create namespace pgsql 
   sudo kubectl apply -f okj-pos-pgsql.yaml -n pgsql
   sudo kubectl apply -f redis.yaml -n apps
   sudo kubectl apply -f asynqmon.yaml -n apps
   ```

ุ6. **ติดตั้งบริการต่าง ๆ ในคลัสเตอร์**

   cd ~/usb/configmap
   ```bash
   sudo kubectl apply -f pos-shop-service-cm.yaml -n apps
   sudo kubectl apply -f pos-shop-terminal-cm.yaml -n apps
   ```

7. **สั่งให้ Flux ดึงค่าล่าสุด**

   ```bash
   sudo flux reconcile ks flux-system --with-source
   sudo flux reconcile kustomization cache-apps --with-source
   sudo flux get ks
   sudo flux get source oci 
   ```

## อธิบายสคริปต์ในโฟลเดอร์ `script/`
| ชื่อไฟล์ | ทำอะไร |
|
| `01-install-tools-k3s.sh` | ติดตั้ง Desktop , Git , SSH , FluxCD , yq , kustomize , Helm , Kubeconform , curl |
| `01-uninstall-tools-k3s.sh` | ถอนการติดตั้งเครื่องมือพื้นฐาน |
| `01-setup-pgadmin.sh` | ติดตั้ง pgAdmin4 แบบเว็บผ่าน Apache |
| `01-uninstall-pgadmin.sh` | ถอนการติดตั้ง pgAdmin4 |
| `02-install-k3s.sh` | ติดตั้ง K3s และตั้ง alias `k` |
| `02-uninstall-k3s.sh` | ถอนการติดตั้ง K3s ออกจากระบบ |
| `03-set-env.sh` | ตั้งค่า `/etc/environment` และ `/etc/hosts` |
| `04-update-ip-k3s.sh` | อัปเดต IP ใน kubeconfig เมื่อเครื่องย้ายที่ ใช้ตอนเชื่อมต่อคลัสเตอร์ไม่ได้เพราะ IP เปลี่ยน |

## สรุปไฟล์ Kubernetes
- `okj-pos-pgsql.yaml` : สร้างคลัสเตอร์ PostgreSQL ด้วย CloudNativePG มี Secret (`cnpg-app-user`, `cnpg-superuser`) และเปิด NodePort 30432
- `redis.yaml` : ติดตั้ง Redis 7.4 พร้อมตั้ง Resource และ Service ภายใน namespace `apps`
- `asynqmon.yaml` : เปิดหน้า UI ของ Asynq ผ่าน Ingress `asynqmon.ohkajhu.com`
- `configmap/pos-shop-service-cm.yaml` : เก็บค่า environment สำหรับ POS service (ต้องเปลี่ยนรหัส/โทเคนตามแต่ละสาขา)
- `configmap/pos-shop-terminal-cm.yaml` : ระบุปลายทาง API สำหรับ POS terminal

## แก้ปัญหาเบื้องต้นและตรวจสอบหลังติดตั้ง
- ดูสถานะคลัสเตอร์: `sudo kubectl get nodes`, `sudo kubectl get pods -A`
- ถ้า Pod มีปัญหาให้ใช้ `kubectl describe pod <ชื่อ> -n <namespace>`
- ถ้าเปลี่ยนที่ตั้งแล้ว IP เปลี่ยน: รัน `./04-update-ip-k3s.sh`
- ถ้าต้องการถอนการติดตั้งระบบ: `sudo ./02-uninstall-k3s.sh` + `./01-uninstall-tools-k3s.sh`

**สำคัญ:** ก่อนนำไปใช้จริงในแต่ละสาขา อย่าลืมปรับค่าต่าง ๆ ให้ตรงกับสภาพแวดล้อมของสาขานั้น ๆ เสมอ