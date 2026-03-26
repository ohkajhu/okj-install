# คู่มือติดตั้งระบบ OKJ POS (Full Installation Guide)

คู่มือฉบับนี้รวบรวมขั้นตอนการติดตั้งระบบ OKJ POS ตั้งแต่เริ่มต้นบน Windows โดยใช้ WSL (Windows Subsystem for Linux) และ Ubuntu 22.04 LTS อย่างละเอียด

---

## สิ่งที่ต้องเตรียม (Prerequisites)
1. **เครื่องคอมพิวเตอร์**: ระบบปฏิบัติการ Windows (แนะนำ Windows 10 หรือ 11)
2. **อินเทอร์เน็ต**: สำหรับดาวน์โหลดแพ็กเกจ
3. **ไฟล์ติดตั้ง**: ชุดไฟล์ในโฟลเดอร์ `OJ-Setup` 

---

## ขั้นตอนที่ 1: ติดตั้ง WSL และ Ubuntu (ฝั่ง Windows)

เพื่อให้เครื่อง Windows สามารถรันระบบ Linux (Ubuntu) ที่เป็นฐานของเซิร์ฟเวอร์ POS ได้

1. **ติดตั้ง Windows Terminal** (ถ้ายังไม่มี):
   - รันไฟล์ `Windows Terminal Installer.exe` ในโฟลเดอร์ `OJ-Setup`

2. **ติดตั้ง Ubuntu**:
   - รันไฟล์ `Ubuntu.exe` ในโฟลเดอร์ `OJ-Setup`
   - รอจนติดตั้งเสร็จ หน้าจอดำจะขึ้นมาให้ตั้งชื่อผู้ใช้งาน
   - **สำคัญ:** ให้ตั้งชื่อ User ว่า `okjadmin` (เพื่อให้ตรงกับสคริปต์ `Start WSL.bat`)
   - ตั้ง Password 

3. **ตรวจสอบชื่อ Distro (สำคัญ)**:
   - เปิด **Command Prompt** หรือ **PowerShell** แล้วรันคำสั่ง:
     ```powershell
     wsl -l
     ```
   - จะเห็นรายชื่อ Distro ที่ติดตั้งไว้ เช่น:
     ```
     Windows Subsystem for Linux Distributions:
     Ubuntu (Default)
     ```
   - **ต้องตรวจสอบว่าชื่อเป็น `Ubuntu`** เพราะไฟล์ `Start WSL.bat` ใช้ `-d Ubuntu` ในการเรียก
   - ถ้าชื่อเป็น `Ubuntu-22.04` หรืออื่น ให้แก้ไขใน `Start WSL.bat` ให้ตรงกัน เช่น:
     ```bat
     start wsl -d Ubuntu-22.04 -u okjadmin bash -c "watch -n 1 'sudo kubectl get po -A'; exec bash"
     ```

---

## ขั้นตอนที่ 2: เตรียมไฟล์เข้าสู่ WSL

เมื่อติดตั้ง Ubuntu เสร็จแล้ว เราต้องนำไฟล์สคริปต์ติดตั้งเข้าไปในระบบ Linux

1. เปิด **Ubuntu** (หรือเปิดผ่าน Windows Terminal)
2. พิมพ์คำสั่งเพื่อสร้างโฟลเดอร์และก๊อปปี้ไฟล์จาก Windows เข้ามา:
   *(หมายเหตุ: ปรับ path ให้ตรงกับที่อยู่ไฟล์จริงบนเครื่อง Windows)*


   # 1. สร้างโฟลเดอร์เก็บไฟล์ (ใช้ -p เพื่อไม่ให้ Error ถ้ามีโฟลเดอร์อยู่แล้ว)
   mkdir -p ~/usb
   # 2. ก๊อปปี้ไฟล์จาก Downloads ของ Windows มายัง WSL (ใช้คำสั่งดึงชื่อ User อัตโนมัติ)
   # หมายเหตุ: หากโฟลเดอร์ไม่ได้ชื่อ OJ-Setup หรือไม่ได้อยู่ที่ Downloads ให้เปลี่ยนให้ตรงกับชื่อไฟล์และที่อยู่ปัจจุบัน
   cp -r /mnt/c/Users/$(powershell.exe -c "echo \$env:USERNAME" | tr -d '\r')/Downloads/OJ-Setup/* ~/usb/

   # 3. เข้าไปยังโฟลเดอร์ script และเปลี่ยนสิทธิ์ไฟล์ให้รันได้
   cd ~/usb/script
   chmod +x *.sh

---

## ขั้นตอนที่ 3: รันสคริปต์ติดตั้งระบบ (ใน WSL)

ทำตามลำดับต่อไปนี้:

### 3.1 ติดตั้งเครื่องมือพื้นฐาน (Tools & Utilities)
สคริปต์นี้จะลง Desktop Environment (XFCE4), AnyDesk, Git, Docker tools, FluxCD, Helm, Kubeconform ฯลฯ

```bash
cd ~/usb/script
   ./01-install-tools-k3s.sh
```
> **สิ่งที่เกิดขึ้น:** สคริปต์จะอัปเดตระบบและติดตั้งโปรแกรมจำเป็น ใช้เวลาสักพัก

ติดตั้ง pgAdmin ด้วยให้รัน `./01-setup-pgadmin.sh`

```bash
   ./01-setup-pgadmin.sh
```

### 3.2 ติดตั้ง Kubernetes (K3s)
สคริปต์นี้จะลง K3s Cluster, ปิด Swap, และตั้งค่า Certificate

```bash
sudo ./02-install-k3s.sh
```
> **สิ่งที่เกิดขึ้น:**
> - ติดตั้ง K3s
> - สร้าง Alias `k` แทน `kubectl`
> - สร้างไฟล์ Config ให้พร้อมใช้งาน
> - รอจนกว่าจะขึ้นข้อความว่า Pods ทั้งหมด Running

### 3.3 ตั้งค่า Environment ประจำสาขา
ขั้นตอนนี้สำคัญมาก เป็นการระบุว่าเครื่องนี้คือ **สาขาไหน**

```bash
   ./03-set-env.sh
```
> **สิ่งที่ต้องทำ:**
> - กรอก **TENANT NAME:** ชื่อสาขาภาษาอังกฤษ (เช่น `OJ00`, `OJ01`)
>
> *สคริปต์จะแก้ไขไฟล์ `/etc/environment` และ `/etc/hosts` ให้อัตโนมัติเพื่อชี้โดเมนไปยัง IP Server กลาง*

---

## ขั้นตอนที่ 4: เชื่อมต่อ GitOps (FluxCD)

เพื่อให้ระบบดึง Code และ Config ล่าสุดมาจาก Git Repository

1. **แตกไฟล์ Bootstrap**:
   ```bash
   cd ~
   tar -xvf ~/usb/flux-bootstrap.tar.gz --no-same-owner --no-same-permissions
   ```

2. **รันสคริปต์ติดตั้ง Flux**:
   ```bash
   cd .bootstrap
   sudo ./install-prd.sh
   ```
   
---

## ขั้นตอนที่ 5: ติดตั้ง Application ลง Cluster

เมื่อฐานระบบพร้อมแล้ว ให้ลงโปรแกรม POS และ Database:

1. **สร้าง Namespace และลง Database (Postgres)**:
   ```bash
   cd ~/usb
   sudo k create ns pgsql
   sudo k apply -f okj-pos-pgsql.yaml -n pgsql
   ```

2. **ลง Redis และ Monitor**:
   ```bash
   sudo k apply -f redis.yaml -n apps
   sudo k apply -f asynqmon.yaml -n apps
   ```

3. **ลง ConfigMap ของสาขา**:
   ```bash
   cd ~/usb/configmap
   sudo k apply -f pos-shop-service-cm.yaml -n apps
   sudo k apply -f pos-shop-terminal-cm.yaml -n apps
   ```
   *หมายเหตุ: ควรตรวจสอบไฟล์ `pos-shop-service-cm.yaml` เพื่อแก้ไข Token ให้ตรงกับสาขาจริงก่อน apply*

---

## ขั้นตอนที่ 6: ตรวจสอบความเรียบร้อย (Validating)

1. **สั่งให้ Flux อัปเดตทันที**:
   ```bash
   sudo flux reconcile ks flux-system --with-source
   ```

2. **เช็คสถานะ Pods**:
   ```bash
   k get pods -A
   ```
   *ทุกอย่างควรขึ้นสถานะ `Running` หรือ `Completed`*

3. **ทดสอบใช้งาน**:
   - ลองปิด Terminal ทั้งหมด
   - เปิดไฟล์ `Start WSL.bat` จากฝั่ง Windows
   - หน้าจอควรจะเปิดมาพร้อมแสดงสถานะของ Kubernetes Monitor ทันที

---

## ขั้นตอนที่ 7: ตั้งค่าให้เปิดระบบอัตโนมัติ (Startup)

เพื่อให้ระบบพร้อมใช้งานทันทีที่เปิดเครื่อง Windows เราจะนำไฟล์ `Start WSL.bat` ไปใส่ไว้ใน Startup Folder

1. **ก๊อปปี้ไฟล์**: คลิกขวาที่ไฟล์ `Start WSL.bat` แล้วเลือก **Copy**
2. **เปิดโฟลเดอร์ Startup**:
   - กดปุ่ม `Windows` + `R` ที่คีย์บอร์ด
   - พิมพ์คำว่า `shell:startup` แล้วกด **Enter**
   - โฟลเดอร์ Startup ของ Windows จะเด้งขึ้นมา
3. **วาง Shortcut**:
   - คลิกขวาในพื้นที่ว่างของโฟลเดอร์ Startup แล้วเลือก **Paste Shortcut** (แนะนำให้ Paste Shortcut เพื่ออ้างอิงไฟล์ต้นฉบับ หากมีการแก้ไขจะได้ไม่ต้องแก้หลายที่)
   - หรือเลือก **Paste** ไปเลยก็ได้ถ้ายืนยันจะใช้ไฟล์นี้

หลังจากนี้ ทุกครั้งที่ Restart เครื่อง Windows ระบบจะรันไฟล์นี้และเปิด WSL ให้โดยอัตโนมัติ

---

## การแก้ไขปัญหาเบื้องต้น (Troubleshooting)

- **IP เปลี่ยน/ย้ายเครื่อง**: รัน `cd ~/usb/script && sudo ./04-update-ip-k3s.sh`
- **ต้องการลบ K3s**: รัน `sudo ./02-uninstall-k3s.sh`
- **ต้องการลบ Tools ทั้งหมด**: รัน `sudo ./01-uninstall-tools-k3s.sh`