# ==========================================================
# Proxmox Friday VM Backup Pipeline to NAS (VM 100 - 103)
# Grouped by Folder: All_Backups_YYYYMMDD_HHMMSS
# Auto-Retention: Keep Latest 3 Backup Folders
# Step 2/2: vzdump & LINE Flex Message Alert
# ==========================================================

# ตรวจจับ error ผ่าน pipeline ทันที
set -o pipefail

START_TIME=$(date +%s)
LOG_FILE="/var/log/nas_backup.log"
# --- Network, Storage & Retention Settings ---
NAS_MOUNT="/mnt/pve/Proxmox-backup"
NAS_IP=""
PROXMOX_IP=$(hostname -I | awk '{print $1}')

# กำหนดให้เก็บ 3 โฟลเดอร์ล่าสุด (หากเกิน 3 จะลบทิ้งทันที)
KEEP_BACKUPS=3

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FOLDER="All_Backups_${TIMESTAMP}"
TARGET_DIR="${NAS_MOUNT}/${BACKUP_FOLDER}"

echo "==========================================================" | tee -a "$LOG_FILE"
echo "[+] Starting Friday VM Backup Pipeline (Proxmox -> NAS)" | tee -a "$LOG_FILE"
echo "[*] Target Folder: ${BACKUP_FOLDER}" | tee -a "$LOG_FILE"
echo "==========================================================" | tee -a "$LOG_FILE"

# ----------------------------------------------------------
# 0. ตรวจสอบการเชื่อมต่อและสร้างโฟลเดอร์บน NAS
# ----------------------------------------------------------
if [ ! -d "$NAS_MOUNT" ]; then
    echo "[-] [ERROR] Mount point '$NAS_MOUNT' not found! Exiting..." | tee -a "$LOG_FILE"
    exit 1
fi

mkdir -p "$TARGET_DIR"
echo "[+] Created directory: $TARGET_DIR" | tee -a "$LOG_FILE"

SUCCESS_COUNT=0
FAIL_COUNT=0

# ----------------------------------------------------------
# 1. สำรองข้อมูล VM 100 (FROG-Server)
# ----------------------------------------------------------
echo -e "\n[1/4] Backing up FROG-Server (VM 100)..." | tee -a "$LOG_FILE"
if vzdump 100 --dumpdir "$TARGET_DIR" --mode snapshot --compress zstd 2>&1 | tee -a "$LOG_FILE"; then
    VM100_STATUS="สถานะ: สำรองข้อมูลลงโฟลเดอร์เรียบร้อย"
    VM100_COLOR="#10B981"
    ((SUCCESS_COUNT++))
else
    VM100_STATUS="สถานะ: สำรองข้อมูลล้มเหลว"
    VM100_COLOR="#EF4444"
    ((FAIL_COUNT++))
fi

# ----------------------------------------------------------
# 2. สำรองข้อมูล VM 101 (Linux Mint Master)
# ----------------------------------------------------------
echo -e "\n[2/4] Backing up Linux Mint (VM 101)..." | tee -a "$LOG_FILE"
if vzdump 101 --dumpdir "$TARGET_DIR" --mode snapshot --compress zstd 2>&1 | tee -a "$LOG_FILE"; then
    VM101_STATUS="สถานะ: สำรองข้อมูลลงโฟลเดอร์เรียบร้อย"
    VM101_COLOR="#10B981"
    ((SUCCESS_COUNT++))
else
    VM101_STATUS="สถานะ: สำรองข้อมูลล้มเหลว"
    VM101_COLOR="#EF4444"
    ((FAIL_COUNT++))
fi

# ----------------------------------------------------------
# 3. สำรองข้อมูล VM 102 (Windows Master)
# ----------------------------------------------------------
echo -e "\n[3/4] Backing up Windows (VM 102)..." | tee -a "$LOG_FILE"
if vzdump 102 --dumpdir "$TARGET_DIR" --mode snapshot --compress zstd 2>&1 | tee -a "$LOG_FILE"; then
    VM102_STATUS="สถานะ: สำรองข้อมูลลงโฟลเดอร์เรียบร้อย"
    VM102_COLOR="#10B981"
    ((SUCCESS_COUNT++))
else
    VM102_STATUS="สถานะ: สำรองข้อมูลล้มเหลว"
    VM102_COLOR="#EF4444"
    ((FAIL_COUNT++))
fi

# ----------------------------------------------------------
# 4. สำรองข้อมูล VM 103 (Ubuntu Master)
# ----------------------------------------------------------
echo -e "\n[4/4] Backing up Ubuntu (VM 103)..." | tee -a "$LOG_FILE"
if vzdump 103 --dumpdir "$TARGET_DIR" --mode snapshot --compress zstd 2>&1 | tee -a "$LOG_FILE"; then
    VM103_STATUS="สถานะ: สำรองข้อมูลลงโฟลเดอร์เรียบร้อย"
    VM103_COLOR="#10B981"
    ((SUCCESS_COUNT++))
else
    VM103_STATUS="สถานะ: สำรองข้อมูลล้มเหลว"
    VM103_COLOR="#EF4444"
    ((FAIL_COUNT++))
fi

# ----------------------------------------------------------
# 5. หมุนเวียนลบโฟลเดอร์เก่า (เก็บ 3 ชุดล่าสุด)
# ----------------------------------------------------------
echo -e "\n[*] Checking and Cleaning old backup folders (Keep: latest $KEEP_BACKUPS)..." | tee -a "$LOG_FILE"
CLEANED_COUNT=0
cd "$NAS_MOUNT" || exit 1

for OLD_DIR in $(ls -d All_Backups_* 2>/dev/null | sort -r | tail -n +$((KEEP_BACKUPS + 1))); do
    if [ -d "$OLD_DIR" ]; then
        echo "[-] Removing old backup folder: $OLD_DIR" | tee -a "$LOG_FILE"
        rm -rf "$OLD_DIR"
        ((CLEANED_COUNT++))
    fi
done

if [ "$CLEANED_COUNT" -gt 0 ]; then
    CLEANUP_TEXT="ลบโฟลเดอร์เก่าทิ้ง: $CLEANED_COUNT ชุด (คงเหลือ $KEEP_BACKUPS ชุดล่าสุด)"
else
    CLEANUP_TEXT="ยังไม่มีโฟลเดอร์เกินโควตา (เก็บ $KEEP_BACKUPS ชุดล่าสุด)"
fi
echo "[+] Cleanup completed: $CLEANUP_TEXT" | tee -a "$LOG_FILE"

# ----------------------------------------------------------
# 6. คำนวณเวลา และ ส่ง LINE Flex Message แจ้งเตือน
# ----------------------------------------------------------
BACKUP_END_TIME=$(date +%s)
BACKUP_DURATION=$((BACKUP_END_TIME - START_TIME))

# คำนวณ ชั่วโมง, นาที และ วินาที
BACKUP_HOURS=$((BACKUP_DURATION / 3600))
BACKUP_MINUTES=$(((BACKUP_DURATION % 3600) / 60))
BACKUP_SECS=$((BACKUP_DURATION % 60))

# ถ้าเกิน 1 ชม. ให้แสดงชั่วโมงด้วย ถ้าไม่ถึงให้แสดงแค่นาที
if [ "$BACKUP_HOURS" -gt 0 ]; then
    DURATION_TEXT="${BACKUP_HOURS} ชั่วโมง ${BACKUP_MINUTES} นาที ${BACKUP_SECS} วิ"
else
    DURATION_TEXT="${BACKUP_MINUTES} นาที ${BACKUP_SECS} วิ"
fi

FINISH_TIME_2=$(date "+%H:%M:%S")

if [ $FAIL_COUNT -eq 0 ]; then
    HEADER_TITLE="สำรองข้อมูล VM ลง NAS สำเร็จสมบูรณ์"
    HEADER_COLOR="#10B981"
else
    HEADER_TITLE="สำรองข้อมูล VM มีบางรายการล้มเหลว"
    HEADER_COLOR="#EF4444"
fi

FLEX_ALERT_2=$(cat <<EOF
{
  "to": "${LINE_GROUP_ID}",
  "messages": [
    {
      "type": "flex",
      "altText": "แจ้งเตือน: สำรองข้อมูล VM ลง NAS เสร็จสิ้น",
      "contents": {
        "type": "bubble",
        "size": "giga",
        "header": {
          "type": "box",
          "layout": "vertical",
          "backgroundColor": "#0F172A",
          "paddingTop": "18px",
          "paddingBottom": "18px",
          "contents": [
            {
              "type": "box",
              "layout": "horizontal",
              "contents": [
                { "type": "text", "text": "● ระบบแจ้งเตือน (ขั้นตอนที่ 2/2)", "color": "${HEADER_COLOR}", "weight": "bold", "size": "xs" },
                { "type": "text", "text": "${FINISH_TIME_2} น.", "color": "#64748B", "size": "xs", "align": "end" }
              ]
            },
            {
              "type": "text",
              "text": "${HEADER_TITLE}",
              "weight": "bold",
              "size": "md",
              "color": "#F8FAFC",
              "margin": "xs"
            },
            {
              "type": "text",
	      "text": "IP Proxmox: ${PROXMOX_IP} | IP NAS: ${NAS_IP} (ใช้เวลา ${DURATION_TEXT})",
              "size": "xs",
              "color": "#38BDF8",
              "margin": "xs"
            }
          ]
        },
        "body": {
          "type": "box",
          "layout": "vertical",
          "backgroundColor": "#020617",
          "spacing": "md",
          "paddingAll": "16px",
          "contents": [
            {
              "type": "box",
              "layout": "vertical",
              "backgroundColor": "#0F172A",
              "cornerRadius": "8px",
              "paddingAll": "12px",
              "contents": [
                { "type": "text", "text": "📁 โฟลเดอร์จัดเก็บรอบนี้", "weight": "bold", "size": "sm", "color": "#F59E0B" },
                { "type": "text", "text": "${BACKUP_FOLDER}", "size": "xs", "color": "#FCD34D", "margin": "xs", "wrap": true },
                { "type": "text", "text": "♻️ ${CLEANUP_TEXT}", "size": "xxs", "color": "#94A3B8", "margin": "xs" }
              ]
            },
            {
              "type": "box",
              "layout": "vertical",
              "backgroundColor": "#0F172A",
              "cornerRadius": "8px",
              "paddingAll": "12px",
              "contents": [
                { "type": "text", "text": "🐸 FROG-Server (VM 100)", "weight": "bold", "size": "sm", "color": "#34D399" },
                { "type": "text", "text": "${VM100_STATUS}", "size": "xs", "color": "${VM100_COLOR}", "margin": "xs", "weight": "bold" }
              ]
            },
            {
              "type": "box",
              "layout": "vertical",
              "backgroundColor": "#0F172A",
              "cornerRadius": "8px",
              "paddingAll": "12px",
              "contents": [
                { "type": "text", "text": "🐧 Linux Mint (VM 101)", "weight": "bold", "size": "sm", "color": "#38BDF8" },
                { "type": "text", "text": "${VM101_STATUS}", "size": "xs", "color": "${VM101_COLOR}", "margin": "xs", "weight": "bold" }
              ]
            },
            {
              "type": "box",
              "layout": "vertical",
              "backgroundColor": "#0F172A",
              "cornerRadius": "8px",
              "paddingAll": "12px",
              "contents": [
                { "type": "text", "text": "🪟 Windows (VM 102)", "weight": "bold", "size": "sm", "color": "#60A5FA" },
                { "type": "text", "text": "${VM102_STATUS}", "size": "xs", "color": "${VM102_COLOR}", "margin": "xs", "weight": "bold" }
              ]
            },
            {
              "type": "box",
              "layout": "vertical",
              "backgroundColor": "#0F172A",
              "cornerRadius": "8px",
              "paddingAll": "12px",
              "contents": [
                { "type": "text", "text": "🟠 Ubuntu (VM 103)", "weight": "bold", "size": "sm", "color": "#FB923C" },
                { "type": "text", "text": "${VM103_STATUS}", "size": "xs", "color": "${VM103_COLOR}", "margin": "xs", "weight": "bold" }
              ]
            }
          ]
        }
      }
    }
  ]
}
EOF
)

# ยิงแจ้งเตือนเข้า LINE Messaging API
curl -sS -X POST https://api.line.me/v2/bot/message/push \
-H 'Content-Type: application/json' \
-H "Authorization: Bearer ${LINE_TOKEN}" \
-d "${FLEX_ALERT_2}"

echo -e "\n==========================================================" | tee -a "$LOG_FILE"
echo "[+] Friday Pipeline Completed! Kept 3 latest backups." | tee -a "$LOG_FILE"
echo "==========================================================" | tee -a "$LOG_FILE"
