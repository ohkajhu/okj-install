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

เมื่อติดตั้ง Ubuntu เสร็จแล้ว เราต้องนำไฟล์สคริปต์ติดตั้งเข้าไปในระบบ Linux โดยคุณสามารถเลือกทำได้ 2 วิธี:

### วิธีที่ 1: ใช้ Bootstrap Script (แนะนำ - ง่ายที่สุด)
รันคำสั่งต่อไปนี้เพียงบรรทัดเดียวใน Ubuntu:
```bash
curl -sSL https://raw.githubusercontent.com/ohkajhu/okj-install/main/bootstrap.sh | bash
```
> **สิงที่เกิดขึ้น:** สคริปต์จะ Clone โปรเจกต์จาก Git และนำไฟล์สำหรับ WSL มาวางไว้ที่ `~/okj-install` ให้โดยอัตโนมัติ

---

### วิธีที่ 2: ก๊อปปี้ไฟล์จาก Windows ด้วยตัวเอง
1. เปิด **Ubuntu**
2. พิมพ์คำสั่งเพื่อก๊อปปี้ไฟล์จากโฟลเดอร์ที่ดาวน์โหลดไว้บน Windows:
   *(หมายเหตุ: ปรับ path ให้ตรงกับที่อยู่ไฟล์จริงบนเครื่อง Windows)*
   ```bash
   mkdir -p ~/okj-install
   cp -r /mnt/c/Users/$(powershell.exe -c "echo \$env:USERNAME" | tr -d '\r')/Downloads/OJ-Setup/* ~/okj-install/
   cd ~/okj-install/script
   chmod +x *.sh
   ```

---

## ขั้นตอนที่ 3: รันสคริปต์ติดตั้งระบบ (วิธีที่แนะนำ - เร็วที่สุด) 🚀

เราได้ทำสคริปต์ **Master Installer** เพื่อรันขั้นตอนการติดตั้งทั้งหมด (01, 01-setup, 02, 03 และ Flux Bootstrap) ให้โดยอัตโนมัติในคำสั่งเดียว:

```bash
cd ~/okj-install/script
./00-install-all.sh
```
> **สิ่งที่สคริปต์นี้จะทำ:**
> 1. ติดตั้ง Tools พื้นฐาน (`01-install-tools-k3s.sh`)
> 2. ติดตั้ง pgAdmin4 (`01-setup-pgadmin.sh`)
> 3. ติดตั้ง K3s Cluster (`02-install-k3s.sh`)
> 4. ตั้งค่า Environment ประจำสาขา (`03-set-env.sh`)
> 5. แตกไฟล์และติดตั้ง Flux Bootstrap (`install-stg.sh` หรือ `install-prd.sh`)

---

## ขั้นตอนการติดตั้ง (กรณีต้องการรันแยกทีละขั้นตอน)

หากคุณต้องการรันแยกเอง สามารถทำได้ตามลำดับดังนี้:

### 3.1 ติดตั้งเครื่องมือพื้นฐาน (Tools & Utilities)
```bash
cd ~/okj-install/script
./01-install-tools-k3s.sh
./01-setup-pgadmin.sh
```

### 3.2 ติดตั้ง Kubernetes (K3s)
```bash
sudo ./02-install-k3s.sh
```

### 3.3 ตั้งค่า Environment ประจำสาขา
```bash
./03-set-env.sh
```

### 3.4 ติดตั้ง Flux Bootstrap
```bash
cd ~
tar -xvf ~/okj-install/flux-bootstrap.tar.gz --no-same-owner --no-same-permissions
cd .bootstrap
# เลือกสคริปต์ตามสภาพแวดล้อม
sudo ./install-stg.sh  # สำหรับ Staging
# หรือ
sudo ./install-prd.sh  # สำหรับ Production
```
   
---

## ขั้นตอนที่ 5: ติดตั้ง Application ลง Cluster

เมื่อฐานระบบพร้อมแล้ว ให้ลงโปรแกรม POS และ Database:

1. **สร้าง Namespace และลง Database (Postgres)**:
   ```bash
   cd ~/okj-install
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
   cd ~/okj-install/configmap
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

- **IP เปลี่ยน/ย้ายเครื่อง**: รัน `cd ~/okj-install/script && sudo ./04-update-ip-k3s.sh`
- **ต้องการลบ K3s**: รัน `sudo ./02-uninstall-k3s.sh`
- **ต้องการลบ Tools ทั้งหมด**: รัน `sudo ./01-uninstall-tools-k3s.sh`