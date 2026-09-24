# System Architecture

## ภาพรวมระบบ

ระบบแบ่งเครือข่ายออกเป็นสองส่วนเพื่อป้องกัน DHCP และ PXE กระทบกับเครือข่ายใช้งานปกติของบริษัท

- VLAN 10 ใช้สำหรับเชื่อมต่อเครือข่ายบริษัทและอัปเดตเครื่องต้นแบบ
- VLAN 20 ใช้สำหรับ PXE Boot, Capture และ Deploy ระบบปฏิบัติการ
- Proxmox VE ใช้บริหารเครื่องเสมือนและเครื่องต้นแบบ
- FOG Project ใช้จัดการอิมเมจและงาน Deploy
- NAS ใช้จัดเก็บอิมเมจผ่าน NFS

## Network Diagram

```mermaid
flowchart TD
    COMPANY["Company Network<br>VLAN 10"] --> PROXMOX["Proxmox VE"]

    PROXMOX --> FOG["FOG Server"]
    PROXMOX --> WINDOWS["Windows Master"]
    PROXMOX --> UBUNTU["Ubuntu Master"]
    PROXMOX --> MINT["Linux Mint Master"]

    FOG --> IMAGING["PXE and Imaging Network<br>VLAN 20"]
    WINDOWS --> IMAGING
    UBUNTU --> IMAGING
    MINT --> IMAGING

    IMAGING --> NAS["NAS Storage<br>NFS"]
    IMAGING --> CLIENT1["Client Computer 1"]
    IMAGING --> CLIENT2["Client Computer 2"]
    IMAGING --> CLIENTN["Additional Clients"]

    การทำงานของระบบ
Capture Workflow
1. เปิดเครื่องต้นแบบบน Proxmox VE
2. อัปเดตระบบปฏิบัติการผ่านเครือข่าย
3. ปิดเครื่องต้นแบบ
4. เปลี่ยนลำดับการบูตเป็นเครือข่าย PXE
5. เปิดเครื่องและเข้าสู่ FOG
6. Capture อิมเมจไปจัดเก็บบน NAS
7. ตรวจสอบผลการ Capture
8. แจ้งผลให้ผู้ดูแลระบบผ่าน LINE
Deploy Workflow
1. เชื่อมต่อเครื่องลูกเข้ากับเครือข่าย Imaging
2. เปิดเครื่องและบูตผ่าน PXE
3. เครื่องลูกติดต่อ FOG Server
4. เลือกอิมเมจที่กำหนด
5. Deploy อิมเมจแบบ Unicast หรือ Multicast
6. เมื่อเสร็จแล้ว เครื่องลูกบูตจากดิสก์ภายใน
Image Rotation
ระบบใช้อิมเมจแบบ A/B เพื่อเก็บอิมเมจรุ่นปัจจุบันและรุ่นก่อนหน้า หากอิมเมจใหม่เกิดปัญหา ผู้ดูแลระบบสามารถย้อนกลับไปใช้อิมเมจเดิมได้
Security Considerations
- แยกเครือข่าย PXE ออกจากเครือข่ายบริษัท
- ไม่จัดเก็บ Password หรือ API Token ใน Repository
- จำกัดการ Deploy อัตโนมัติเฉพาะ VLAN หรือพอร์ตที่กำหนด
- ตรวจสอบการเชื่อมต่อ NAS ก่อนเริ่ม Capture หรือ Deploy
