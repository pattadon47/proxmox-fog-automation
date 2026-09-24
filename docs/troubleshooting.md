# Troubleshooting

## FOG Unable to Find Image Path

สาเหตุเกิดจาก FOG Server ไม่พบพื้นที่จัดเก็บอิมเมจบน NAS

แนวทางตรวจสอบ:

- ตรวจสอบว่า NAS เปิดใช้งาน
- ตรวจสอบ NFS Permission
- ตรวจสอบว่า `/images` ถูก Mount
- ตรวจสอบ Path ใน FOG Storage Node

## Multicast Does Not Start

แนวทางตรวจสอบ:

- ตรวจสอบ FOGMulticastManager
- ตรวจสอบการเชื่อมต่อเครื่องลูก
- ตรวจสอบ VLAN และ Multicast ของสวิตช์
- ตรวจสอบว่า `udp-sender` ทำงาน

## NFS Access Denied

แนวทางตรวจสอบ:

- ตรวจสอบ IP ที่ได้รับอนุญาตบน NAS
- ตรวจสอบสิทธิ์ Read/Write
- ตรวจสอบ NFS Version
- ตรวจสอบ Export Path

## Proxmox Storage Nearly Full

แนวทางแก้ไข:

- ตรวจสอบ Snapshot และ Unused Disk
- ย้ายดิสก์ VM ไปยัง NAS
- ไม่ลบ Logical Volume โดยตรง
- ควรรักษาพื้นที่ว่างอย่างน้อย 15–20 เปอร์เซ็นต์
